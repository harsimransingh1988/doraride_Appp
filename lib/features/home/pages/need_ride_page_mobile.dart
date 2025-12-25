// lib/features/home/pages/need_ride_page.dart
//
// NeedRidePage with cross-platform autocomplete using HTTP Places API (no google_place).
// No dart:html / dart:js / js_util, so this compiles on Android / iOS / Web.
//
// Features kept:
//  - Create / edit / cancel ride request
//  - Date + time selection with validation
//  - Seats stepper
//  - Pets, luggage size, notes
//  - Firestore persistence
//  - Autocomplete for From / To using Google Places HTTP API
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:doraride_appp/services/places_service.dart';

const _kThemeBlue = Color(0xFF180D3B);
final DateFormat _dateDisplayFormatter = DateFormat('EEE, MMM d, yyyy');

// Your Places API key
const String kGooglePlacesApiKey = 'AIzaSyCDw81VLlIITSG1IOK8G2cTIi5lPY-TeW8';

class NeedRidePage extends StatefulWidget {
  final String? requestIdToEdit;

  const NeedRidePage({super.key, this.requestIdToEdit});

  @override
  State<NeedRidePage> createState() => _NeedRidePageState();
}

class _NeedRidePageState extends State<NeedRidePage> {
  final _formKey = GlobalKey<FormState>();

  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _dateCtrl = TextEditingController(); // YYYY-MM-DD
  final TextEditingController _timeCtrl = TextEditingController();

  int _seats = 1;
  bool _allowsPets = false;
  String _luggageSize = 'M';
  final _notesCtrl = TextEditingController();

  // ========= Autocomplete (overlay UI like SearchPage) =========
  final FocusNode _fromFocus = FocusNode();
  final FocusNode _toFocus = FocusNode();
  final LayerLink _fromLink = LayerLink();
  final LayerLink _toLink = LayerLink();
  OverlayEntry? _fromOverlay;
  OverlayEntry? _toOverlay;
  Timer? _debounce;
  List<_PlacePrediction> _fromPreds = [];
  List<_PlacePrediction> _toPreds = [];

  // optional location bias
  double? _userLat;
  double? _userLng;

  // blur guard so tap can complete before overlay closes
  bool _overlayPointerDown = false;

  // ✅ Google Places HTTP service (no package dependency)
  late final PlacesService _places;

  // ========= Time parsing helper =========
  TimeOfDay? get _timeOfDayFromController {
    if (_timeCtrl.text.isEmpty) return null;
    try {
      final format = DateFormat.jm();
      final dt = format.parse(_timeCtrl.text);
      return TimeOfDay.fromDateTime(dt);
    } catch (_) {
      return null;
    }
  }

  // ========= Load-for-edit =========
  Future<void> _loadRequestForEdit(String requestId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('requests')
          .doc(requestId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;

        DateTime? date;
        if (data['date'] is Timestamp) {
          date = (data['date'] as Timestamp).toDate();
        } else if (data['date'] is String) {
          date = DateTime.tryParse(data['date']);
        }

        String timeString = '';
        if (data['time'] is String) {
          timeString = data['time'] as String;
        }

        setState(() {
          _fromCtrl.text = (data['origin'] ?? '') as String;
          _toCtrl.text = (data['destination'] ?? '') as String;

          if (date != null) {
            _dateCtrl.text = _toStorageDate(date);
          }

          _timeCtrl.text = timeString;

          _seats = (data['seatsRequired'] as int?) ?? 1;
          _allowsPets = (data['allowsPets'] as bool?) ?? false;
          _luggageSize = (data['luggageSize'] ?? 'M') as String;
          _notesCtrl.text = (data['notes'] ?? '') as String;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: Request not found.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading request for edit: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();

    // ✅ init HTTP places service
    _places = PlacesService(apiKey: kGooglePlacesApiKey);


    if (widget.requestIdToEdit != null) {
      _loadRequestForEdit(widget.requestIdToEdit!);
    }

    _maybeInitLocation();

    // focus listeners with small delay so overlay-taps can finish
    _fromFocus.addListener(() {
      if (!_fromFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 120), () {
          if (!_overlayPointerDown) _removeFromOverlay();
        });
      } else if (_fromPreds.isNotEmpty) {
        _showFromOverlay();
      }
    });

    _toFocus.addListener(() {
      if (!_toFocus.hasFocus) {
        Future.delayed(const Duration(milliseconds: 120), () {
          if (!_overlayPointerDown) _removeToOverlay();
        });
      } else if (_toPreds.isNotEmpty) {
        _showToOverlay();
      }
    });

    // debounced input listeners
    _fromCtrl.addListener(() => _debounceRun(() => _fetchPreds(isFrom: true)));
    _toCtrl.addListener(() => _debounceRun(() => _fetchPreds(isFrom: false)));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeFromOverlay();
    _removeToOverlay();
    _fromFocus.dispose();
    _toFocus.dispose();

    _fromCtrl.dispose();
    _toCtrl.dispose();
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ================= Location bias (optional) =================
  Future<void> _maybeInitLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      setState(() {
        _userLat = pos.latitude;
        _userLng = pos.longitude;
      });
    } catch (_) {
      // ignore
    }
  }

  // ================= Autocomplete =================
  void _debounceRun(void Function() run) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), run);
  }

  Future<void> _fetchPreds({required bool isFrom}) async {
    final text = (isFrom ? _fromCtrl.text : _toCtrl.text).trim();
    if (text.length < 2) {
      setState(() {
        if (isFrom) {
          _fromPreds = [];
          _removeFromOverlay();
        } else {
          _toPreds = [];
          _removeToOverlay();
        }
      });
      return;
    }

    try {
      final preds = await _getPlacePredictions(text);
      setState(() {
        if (isFrom) {
          _fromPreds = preds;
          if (_fromFocus.hasFocus && preds.isNotEmpty) _showFromOverlay();
        } else {
          _toPreds = preds;
          if (_toFocus.hasFocus && preds.isNotEmpty) _showToOverlay();
        }
      });
    } catch (e) {
      debugPrint('Autocomplete error: $e');
      setState(() {
        if (isFrom) {
          _fromPreds = [];
          _removeFromOverlay();
        } else {
          _toPreds = [];
          _removeToOverlay();
        }
      });
    }
  }

  /// ✅ Places Autocomplete via our HTTP service (no google_place).
  Future<List<_PlacePrediction>> _getPlacePredictions(String input) async {
    // Optional: bias (not required)
    // If you want country restriction, pass countryCode: 'IN'
    // If you later extend PlacesService with location bias, you can wire it here.

    final results = await _places.autocomplete(
      input,
      countryCode: 'IN',
    );

    return results
        .map((s) => _PlacePrediction(description: s.description, placeId: s.placeId))
        .where((p) => p.description.isNotEmpty && p.placeId.isNotEmpty)
        .toList();
  }

  Future<void> _selectPrediction({
    required bool isFrom,
    required _PlacePrediction p,
  }) async {
    setState(() {
      if (isFrom) {
        _fromCtrl.text = p.description;
        _fromPreds = [];
        _removeFromOverlay();
        _fromFocus.unfocus();
      } else {
        _toCtrl.text = p.description;
        _toPreds = [];
        _removeToOverlay();
        _toFocus.unfocus();
      }
    });
  }

  // ================= Overlays (same interaction behaviour) =================
  void _showFromOverlay() {
    _fromOverlay?.remove();
    _fromOverlay = _buildOverlay(
      link: _fromLink,
      preds: _fromPreds,
      onTap: (p) => _selectPrediction(isFrom: true, p: p),
    );
    Overlay.of(context)!.insert(_fromOverlay!);
  }

  void _showToOverlay() {
    _toOverlay?.remove();
    _toOverlay = _buildOverlay(
      link: _toLink,
      preds: _toPreds,
      onTap: (p) => _selectPrediction(isFrom: false, p: p),
    );
    Overlay.of(context)!.insert(_toOverlay!);
  }

  void _removeFromOverlay() {
    _fromOverlay?.remove();
    _fromOverlay = null;
  }

  void _removeToOverlay() {
    _toOverlay?.remove();
    _toOverlay = null;
  }

  OverlayEntry _buildOverlay({
    required LayerLink link,
    required List<_PlacePrediction> preds,
    required void Function(_PlacePrediction) onTap,
  }) {
    final mq = MediaQuery.of(context);
    final double width = mq.size.width - 32; // match page padding

    return OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _removeFromOverlay();
                _removeToOverlay();
              },
            ),
          ),
          Positioned(
            width: width,
            left: 16,
            child: CompositedTransformFollower(
              link: link,
              showWhenUnlinked: false,
              offset: const Offset(0, 54),
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: preds.isEmpty
                      ? const SizedBox.shrink()
                      : Listener(
                          onPointerDown: (_) => _overlayPointerDown = true,
                          onPointerUp: (_) => Future.microtask(
                              () => _overlayPointerDown = false),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: preds.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final p = preds[i];
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => onTap(p),
                                child: ListTile(
                                  dense: true,
                                  leading:
                                      const Icon(Icons.place_outlined),
                                  title: Text(p.description),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= Helpers (unchanged) =================
  Future<User> _ensureSignedIn() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
    return auth.currentUser!;
  }

  String _toStorageDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _displayDate(String store) {
    final d = DateTime.tryParse(store);
    return d == null ? 'Select date' : _dateDisplayFormatter.format(d);
  }

  String _displayTime(String store) {
    return store.isEmpty ? 'Select time' : store;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final init = _dateCtrl.text.isEmpty
        ? now.add(const Duration(days: 1))
        : (DateTime.tryParse(_dateCtrl.text) ?? now);
    final d = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
      initialDate: init,
    );
    if (d != null) setState(() => _dateCtrl.text = _toStorageDate(d));
  }

  void _showTimeDropdown(BuildContext context) async {
    final now = DateTime.now();
    TimeOfDay initialTime =
        _timeOfDayFromController ?? TimeOfDay.fromDateTime(now);

    final snappedMinute = (initialTime.minute / 15).round() * 15;
    initialTime = initialTime.replacing(
      minute: snappedMinute % 60,
      hour: initialTime.hour + (snappedMinute ~/ 60),
    );

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final minute = (picked.minute / 15).round() * 15;
      final finalTime = picked.replacing(
        minute: minute % 60,
        hour: picked.hour + (minute ~/ 60),
      );

      final dt = DateTime(
        now.year,
        now.month,
        now.day,
        finalTime.hour,
        finalTime.minute,
      );
      setState(() {
        _timeCtrl.text = DateFormat.jm().format(dt);
      });
    }
  }

  DateTime? _departure() {
    final timeOfDay = _timeOfDayFromController;
    if (_dateCtrl.text.isEmpty || timeOfDay == null) return null;
    final d = DateTime.tryParse(_dateCtrl.text);
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day, timeOfDay.hour, timeOfDay.minute);
  }

  Future<Map<String, String>> _userMeta() async {
    final u = await _ensureSignedIn();
    final prefs = await SharedPreferences.getInstance();
    final name = (u.displayName?.trim().isNotEmpty ?? false)
        ? u.displayName!.trim()
        : (prefs.getString('display_name') ?? 'Rider');
    return {'uid': u.uid, 'name': name};
  }

  Future<void> _showSuccessDialog(BuildContext context, bool isEditing) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(isEditing ? 'Update Successful' : 'Request Posted'),
          content: Text(
            isEditing
                ? 'Your request has been successfully updated and saved.'
                : 'Your ride request has been successfully posted.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop('trips');
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deletePost() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Cancellation'),
        content: const Text(
            'Are you sure you want to cancel this request? It will be moved to the Canceled/Rejected section.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Do Not Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );

    if (confirm == true && widget.requestIdToEdit != null) {
      try {
        await FirebaseFirestore.instance
            .collection('requests')
            .doc(widget.requestIdToEdit)
            .update({
          'status': 'cancelled',
          'deletedAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Request deleted successfully.')),
          );
          Navigator.of(context).pop('trips');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  // ---------- submit (same rules) ----------
  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final dep = _departure();
    final isEditing = widget.requestIdToEdit != null;

    if (!isEditing) {
      if (dep == null || !dep.isAfter(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('The selected date and time must be in the future.')),
        );
        return;
      }
    } else {
      if (dep == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a valid date and time.')),
        );
        return;
      }
    }

    try {
      final meta = await _userMeta();
      final collection = FirebaseFirestore.instance.collection('requests');

      final Map<String, dynamic> data = {
        'origin': _fromCtrl.text.trim(),
        'destination': _toCtrl.text.trim(),
        'date': Timestamp.fromDate(dep!),
        'time': _timeCtrl.text.trim(),
        'seatsRequired': _seats,
        'allowsPets': _allowsPets,
        'luggageSize': _luggageSize,
        'notes': _notesCtrl.text.trim(),
        'status': 'active',
        'riderUid': meta['uid'],
        'riderName': meta['name'],
      };

      if (isEditing) {
        await collection.doc(widget.requestIdToEdit!).update(data);
      } else {
        data['postedAt'] = FieldValue.serverTimestamp();
        await collection.add(data);
      }

      if (!mounted) return;
      await _showSuccessDialog(context, isEditing);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to ${isEditing ? 'update' : 'post'}: $e'),
        ),
      );
    }
  }

  Widget _label(String text, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: _kThemeBlue),
            const SizedBox(width: 8),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.requestIdToEdit != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Request' : 'Need a Ride'),
        actions: isEditing
            ? [
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('Cancel Request'),
                  onPressed: _deletePost,
                )
              ]
            : [],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _label('From', Icons.my_location_outlined),
              CompositedTransformTarget(
                link: _fromLink,
                child: TextFormField(
                  controller: _fromCtrl,
                  focusNode: _fromFocus,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Origin',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Origin is required.' : null,
                  onTap: () {
                    if (_fromPreds.isNotEmpty) _showFromOverlay();
                  },
                ),
              ),
              const SizedBox(height: 12),

              _label('To', Icons.place_outlined),
              CompositedTransformTarget(
                link: _toLink,
                child: TextFormField(
                  controller: _toCtrl,
                  focusNode: _toFocus,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Destination',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Destination is required.'
                      : null,
                  onTap: () {
                    if (_toPreds.isNotEmpty) _showToOverlay();
                  },
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(child: _label('Date', Icons.calendar_today_outlined)),
                  const SizedBox(width: 12),
                  Expanded(child: _label('Time', Icons.access_time)),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _dateCtrl,
                      readOnly: true,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: 'Select date',
                        labelText: _displayDate(_dateCtrl.text),
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Date is required.' : null,
                      onTap: _pickDate,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _timeCtrl,
                      readOnly: true,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: 'Select time',
                        labelText: _displayTime(_timeCtrl.text),
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Time is required.' : null,
                      onTap: () => _showTimeDropdown(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _label('Seats needed', Icons.event_seat_outlined),
              _SeatsStepperField(
                initialValue: _seats,
                onChanged: (v) => setState(() => _seats = v.clamp(1, 8)),
              ),
              const SizedBox(height: 16),

              _label('Preferences', Icons.tune),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Pets OK'),
                    selected: _allowsPets,
                    onSelected: (v) => setState(() => _allowsPets = v),
                  ),
                  ChoiceChip(
                    label: const Text('Luggage: N'),
                    selected: _luggageSize == 'N',
                    onSelected: (_) => setState(() => _luggageSize = 'N'),
                  ),
                  ChoiceChip(
                    label: const Text('Luggage: S'),
                    selected: _luggageSize == 'S',
                    onSelected: (_) => setState(() => _luggageSize = 'S'),
                  ),
                  ChoiceChip(
                    label: const Text('Luggage: M'),
                    selected: _luggageSize == 'M',
                    onSelected: (_) => setState(() => _luggageSize = 'M'),
                  ),
                  ChoiceChip(
                    label: const Text('Luggage: L'),
                    selected: _luggageSize == 'L',
                    onSelected: (_) => setState(() => _luggageSize = 'L'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _label('Notes (optional)', Icons.notes_outlined),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Anything drivers should know?',
                ),
              ),

              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(isEditing ? 'Save Changes' : 'Post request'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ====================================================================
// Stepper Field for typeable input and +/- buttons (UNCHANGED)
// ====================================================================

class _SeatsStepperField extends StatefulWidget {
  final int initialValue;
  final ValueChanged<int> onChanged;

  const _SeatsStepperField({
    super.key,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_SeatsStepperField> createState() => _SeatsStepperFieldState();
}

class _SeatsStepperFieldState extends State<_SeatsStepperField> {
  late final TextEditingController _controller;
  final int _maxSeats = 8;
  final int _minSeats = 1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue.toString());
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(_SeatsStepperField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _controller.text = widget.initialValue.toString();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _updateValue(int newValue) {
    if (newValue < _minSeats || newValue > _maxSeats) return;

    widget.onChanged(newValue);

    _controller.text = newValue.toString();
    _controller.selection =
        TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
  }

  void _onTextChanged() {
    final text = _controller.text.trim();
    final n = int.tryParse(text);

    if (n != null && n >= _minSeats && n <= _maxSeats) {
      if (n != widget.initialValue) {
        widget.onChanged(n);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentValue = widget.initialValue;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: currentValue > _minSeats
                ? () => _updateValue(currentValue - 1)
                : null,
            icon: Icon(
              Icons.remove,
              color: currentValue > _minSeats ? _kThemeBlue : Colors.grey,
            ),
            splashRadius: 20,
          ),
          Expanded(
            child: TextFormField(
              controller: _controller,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, color: _kThemeBlue),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
                filled: false,
              ),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (v == null || v.isEmpty) {
                  return 'Seat count is required.';
                }
                if (n == null || n < _minSeats) {
                  return 'Minimum 1 seat required.';
                }
                if (n > _maxSeats) {
                  return 'Maximum $_maxSeats seats allowed here.';
                }
                return null;
              },
            ),
          ),
          IconButton(
            onPressed: currentValue < _maxSeats
                ? () => _updateValue(currentValue + 1)
                : null,
            icon: Icon(
              Icons.add,
              color: currentValue < _maxSeats ? _kThemeBlue : Colors.grey,
            ),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }
}

// ================= Models =================

class _PlacePrediction {
  final String description;
  final String placeId;

  _PlacePrediction({required this.description, required this.placeId});
}
