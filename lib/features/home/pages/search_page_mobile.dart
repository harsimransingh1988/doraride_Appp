// lib/features/home/pages/search_page_mobile.dart
// Mobile (Android/iOS) version using HTTP Places Autocomplete (no google_place)
// No dart:html imports here.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart'; // ✅ LatLng

// ✅ NEW: our replacement for google_place
import 'package:doraride_appp/services/places_service.dart';

// Firebase + router
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:doraride_appp/app_router.dart';

// Notifications page
import '../../notifications/notifications_page.dart';

// Place details cache
import 'package:doraride_appp/services/get_place_details_cached.dart';

/// ✅ Put your Google Places API key here (same key you were using before)
const String kGooglePlacesApiKey = "AIzaSyCDw81VLlIITSG1IOK8G2cTIi5lPY-TeW8";

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  // --- form state ---
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  DateTime? _date;
  int _seats = 1;

  // --- recents persistence ---
  static const _prefsKey = 'recent_trips_v3';
  final DateFormat _dateDisplayFormatter = DateFormat('EEE, MMM d, yyyy');
  List<_Recent> _recents = [];

  // --- Autocomplete for mobile ---
  final FocusNode _fromFocus = FocusNode();
  final FocusNode _toFocus = FocusNode();
  final LayerLink _fromLink = LayerLink();
  final LayerLink _toLink = LayerLink();
  OverlayEntry? _fromOverlay;
  OverlayEntry? _toOverlay;
  Timer? _debounce;

  // suggestions
  List<_PlacePrediction> _fromPreds = [];
  List<_PlacePrediction> _toPreds = [];

  // user location (optional, for biasing)
  double? _userLat;
  double? _userLng;

  // ✅ Places service (replaces google_place)
  late final PlacesService _places;

  // Guard so blur doesn't kill overlay before tap
  bool _overlayPointerDown = false;

  @override
  void initState() {
    super.initState();

    // ✅ init PlacesService
    _places = PlacesService(apiKey: kGooglePlacesApiKey);

    _loadRecents();
    _maybeInitLocation();

    // Close overlays when field loses focus
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

    // Debounced listeners for autocomplete
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
    super.dispose();
  }

  // =========================
  // User location (bias)
  // =========================
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

  // =========================
  // Places Autocomplete (Mobile Logic)
  // =========================
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
      final predictions = await _getPlacePredictions(text);

      setState(() {
        if (isFrom) {
          _fromPreds = predictions;
          if (_fromFocus.hasFocus && predictions.isNotEmpty) _showFromOverlay();
        } else {
          _toPreds = predictions;
          if (_toFocus.hasFocus && predictions.isNotEmpty) _showToOverlay();
        }
      });
    } catch (_) {
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

  Future<List<_PlacePrediction>> _getPlacePredictions(String input) async {
    try {
      final LatLng? bias = (_userLat != null && _userLng != null)
          ? LatLng(_userLat!, _userLng!)
          : null;

      // ✅ HTTP autocomplete via PlacesService
      final results = await _places.autocomplete(
        input,
        language: 'en',
        location: bias,
        radiusMeters: bias != null ? 50000 : null,
      );

      // results expected: list of {description, placeId}
      return results
          .map((p) => _PlacePrediction(
                description: p.description,
                placeId: p.placeId,
              ))
          .toList();
    } catch (e) {
      debugPrint('Places autocomplete error: $e');
      return [];
    }
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

    // Cache the place details (lat/lng/currency) for result page
    try {
      await getPlaceDetailsCached(p.placeId);
    } catch (_) {
      // Ignore cache errors
    }
  }

  // =========== Overlays ===========
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
    required Future<void> Function(_PlacePrediction) onTap,
  }) {
    final mq = MediaQuery.of(context);
    final double width = mq.size.width - 28;

    return OverlayEntry(
      builder: (_) => Stack(
        children: [
          // Backdrop to capture taps outside and close overlay
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _removeFromOverlay();
                _removeToOverlay();
              },
            ),
          ),

          // The anchored dropdown
          Positioned(
            width: width,
            left: 14,
            child: CompositedTransformFollower(
              link: link,
              showWhenUnlinked: false,
              offset: const Offset(0, 48),
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: preds.isEmpty
                      ? const SizedBox.shrink()
                      : Listener(
                          // Mark that we started a tap inside the overlay
                          onPointerDown: (_) => _overlayPointerDown = true,
                          onPointerUp: (_) =>
                              Future.microtask(() => _overlayPointerDown = false),
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
                                onTap: () async {
                                  await onTap(p);
                                },
                                child: ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.place_outlined),
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

  // =========================
  // Recents: load/save/clear
  // =========================
  Future<void> _loadRecents() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? const <String>[];
    final parsed = list
        .map((s) => _Recent.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
    setState(() => _recents = parsed.take(5).toList());
  }

  Future<void> _saveRecent(_Recent r) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? <String>[];

    final existing = list
        .map((s) => _Recent.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .where((e) =>
            !(e.from == r.from &&
                e.to == r.to &&
                (e.dateIso ?? '') == (r.dateIso ?? '')))
        .toList();

    final updated = [
      jsonEncode(r.copyWith(savedAt: DateTime.now()).toJson()),
      ...existing.map((e) => jsonEncode(e.toJson())),
    ];

    await prefs.setStringList(_prefsKey, updated.take(5).toList());
    await _loadRecents();
  }

  Future<void> _removeRecentAt(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? <String>[];
    if (index < 0 || index >= list.length) return;
    list.removeAt(index);
    await prefs.setStringList(_prefsKey, list);
    await _loadRecents();
  }

  Future<void> _clearAllRecents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    await _loadRecents();
  }

  // =========================
  // UI helpers
  // =========================
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Select trip date (optional)',
    );
    if (picked != null) setState(() => _date = picked);
  }

  String get _dateLabel {
    if (_date == null) return 'Optional: Select date';
    return _dateDisplayFormatter.format(_date!);
  }

  void _swap() {
    final t = _fromCtrl.text;
    _fromCtrl.text = _toCtrl.text;
    _toCtrl.text = t;
    setState(() {});
  }

  Future<void> _submit() async {
    final from = _fromCtrl.text.trim();
    final to = _toCtrl.text.trim();

    if (from.isEmpty || to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill From and To')),
      );
      return;
    }

    await _saveRecent(_Recent(
      from: from,
      to: to,
      dateIso: _date?.toIso8601String(),
      seats: _seats,
    ));

    if (!mounted) return;

    Navigator.pushNamed(
      context,
      Routes.searchResults,
      arguments: {
        'from': from,
        'to': to,
        'date': _date?.toIso8601String(),
        'seats': _seats,
      },
    );
  }

  // =========================
  // Map Picker Integration
  // =========================
  void _showMapPickerHint(bool forFrom) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Drag the map to select ${forFrom ? 'starting' : 'destination'} location'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Got it',
          onPressed: () {},
        ),
      ),
    );
  }

  Future<void> _openPicker({required bool forFrom}) async {
    _showMapPickerHint(forFrom);

    final initialQuery = (forFrom ? _fromCtrl.text : _toCtrl.text).trim();

    final result = await Navigator.of(context).pushNamed(
      Routes.mapPicker,
      arguments: {'initialQuery': initialQuery},
    );

    if (result != null && result is Map) {
      final address = result['address'] as String? ?? '';

      if (address.isNotEmpty) {
        setState(() {
          if (forFrom) {
            _fromCtrl.text = address;
            _fromPreds = [];
            _removeFromOverlay();
            _fromFocus.unfocus();
          } else {
            _toCtrl.text = address;
            _toPreds = [];
            _removeToOverlay();
            _toFocus.unfocus();
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${forFrom ? 'From' : 'To'} location set to: $address'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // =========================
  // Build
  // =========================
  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF279C56);
    final radius = BorderRadius.circular(22);

    return Scaffold(
      backgroundColor: green,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: green,
        elevation: 0,
        centerTitle: true,
        title: const _BrandTitle(),
        actions: const [
          _NotificationsBell(),
          _ProfileAvatar(),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
          children: [
            // Search card
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: radius,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  )
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  const SizedBox(height: 4),

                  // FROM
                  _RowPad(
                    child: Row(
                      children: [
                        const Icon(Icons.my_location_outlined,
                            color: Colors.black87),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CompositedTransformTarget(
                            link: _fromLink,
                            child: TextField(
                              controller: _fromCtrl,
                              focusNode: _fromFocus,
                              decoration: const InputDecoration(
                                hintText: 'From (city)',
                                border: InputBorder.none,
                              ),
                              onTap: () {
                                if (_fromPreds.isNotEmpty) _showFromOverlay();
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Pick location on map',
                          icon: const Icon(Icons.map_outlined, size: 20),
                          onPressed: () => _openPicker(forFrom: true),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // TO
                  _RowPad(
                    child: Row(
                      children: [
                        const Icon(Icons.place_outlined, color: Colors.black87),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CompositedTransformTarget(
                            link: _toLink,
                            child: TextField(
                              controller: _toCtrl,
                              focusNode: _toFocus,
                              decoration: const InputDecoration(
                                hintText: 'To (city)',
                                border: InputBorder.none,
                              ),
                              onTap: () {
                                if (_toPreds.isNotEmpty) _showToOverlay();
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Pick location on map',
                          icon: const Icon(Icons.map_outlined, size: 20),
                          onPressed: () => _openPicker(forFrom: false),
                        ),

                        // ✅ FIX: compact swap button (prevents overflow)
                        IconButton(
                          tooltip: 'Swap',
                          onPressed: _swap,
                          icon: Icon(Icons.swap_vert, color: green, size: 22),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // date + seats
                  _RowPad(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 7,
                          child: InkWell(
                            onTap: _pickDate,
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              height: 40,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.black26),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_today_rounded,
                                    size: 18,
                                    color: Color(0xFF2E7D32),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _dateLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _date == null
                                            ? Colors.black45
                                            : const Color(0xFF2E7D32),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (_date != null) ...[
                                    IconButton(
                                      tooltip: 'Clear date',
                                      onPressed: () => setState(() => _date = null),
                                      icon: const Icon(
                                        Icons.close,
                                        size: 18,
                                        color: Colors.black45,
                                      ),
                                    ),
                                  ]
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 5,
                          child: _SeatsStepper(
                            value: _seats,
                            onChanged: (v) => setState(() => _seats = v.clamp(1, 8)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  // Search button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _submit,
                        icon: const Icon(Icons.search),
                        label: const Text(
                          'Search rides',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A1452),
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Recent searches
            if (_recents.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent searches',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextButton(
                    onPressed: _clearAllRecents,
                    child: const Text(
                      'Clear all',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...List.generate(_recents.length, (i) {
                final r = _recents[i];
                final when =
                    r.dateIso == null ? 'Any date' : _prettyDate(r.dateIso!);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        Routes.searchResults,
                        arguments: {
                          'from': r.from,
                          'to': r.to,
                          'date': r.dateIso,
                          'seats': r.seats,
                        },
                      );
                    },
                    leading: const Icon(Icons.history),
                    title: Text('${r.from} → ${r.to}'),
                    subtitle: Text('$when • ${r.seats} seat(s)'),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _removeRecentAt(i),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }

  String _prettyDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return 'Any date';
    try {
      return DateFormat('MMM d, yyyy').format(d);
    } catch (_) {
      const m = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return '${m[d.month - 1]} ${d.day}, ${d.year}';
    }
  }
}

// ————— Small widgets —————

class _BrandTitle extends StatelessWidget {
  const _BrandTitle();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/logo_white.png',
          height: 22,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
        const SizedBox(width: 8),
        const Text(
          'DoraRide',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

// 🔔 Bell with unread counter
class _NotificationsBell extends StatelessWidget {
  const _NotificationsBell();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: IconButton(
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pushNamed(Routes.login),
        ),
      );
    }

    final uid = user.uid;

    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots();

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          final unread = snapshot.data?.docs.length ?? 0;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.notifications_none_rounded,
                  color: Colors.white,
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NotificationsPage(),
                    ),
                  );
                },
              ),
              if (unread > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Center(
                      child: Text(
                        unread > 9 ? '9+' : unread.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar();

  String _nameFrom(User? user, Map<String, dynamic>? data) {
    final first = (data?['firstName'] ?? '').toString().trim();
    final last = (data?['lastName'] ?? '').toString().trim();
    final merged = [first, last].where((s) => s.isNotEmpty).join(' ');
    if (merged.isNotEmpty) return merged;

    final dn = user?.displayName?.trim() ?? '';
    if (dn.isNotEmpty) return dn;

    final email = user?.email ?? '';
    if (email.isNotEmpty) return email.split('@').first;

    return 'User';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.of(context).pushNamed(Routes.login),
          child: const CircleAvatar(
            radius: 16,
            child: Icon(Icons.person, size: 16),
          ),
        ),
      );
    }

    final stream =
        FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).pushNamed(Routes.homeProfile),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snap) {
            final data = snap.data?.data();
            final photoUrl = (data?['photoUrl'] ?? user.photoURL ?? '')
                .toString()
                .trim();
            final name = _nameFrom(user, data);
            final initial = (name.isNotEmpty ? name[0] : 'U').toUpperCase();

            return CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF180D3B),
              foregroundColor: Colors.white,
              backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
              child: photoUrl.isEmpty
                  ? Text(
                      initial,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    )
                  : null,
            );
          },
        ),
      ),
    );
  }
}

class _SeatsStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _SeatsStepper({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          const Icon(Icons.event_seat_outlined, size: 16),
          const SizedBox(width: 5),

          // ✅ FIX: flexible label (prevents overflow on narrow width)
          const Flexible(
            child: Text(
              'Seats',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          const SizedBox(width: 4),
          const Spacer(),

          _IconBtn(
            icon: Icons.remove,
            onTap: value > 1 ? () => onChanged(value - 1) : null,
          ),

          Container(
            width: 22,
            alignment: Alignment.center,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '$value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          _IconBtn(
            icon: Icons.add,
            onTap: value < 8 ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _IconBtn({required this.icon, this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: onTap == null ? Colors.black12 : const Color(0xFFEAEAF4),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 16,
          color: onTap == null ? Colors.black38 : const Color(0xFF1A1452),
        ),
      ),
    );
  }
}

class _RowPad extends StatelessWidget {
  final Widget child;
  const _RowPad({required this.child});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: child,
      );
}

// ————— Models —————

class _Recent {
  final String from;
  final String to;
  final String? dateIso;
  final int seats;
  final DateTime? savedAt;

  _Recent({
    required this.from,
    required this.to,
    required this.dateIso,
    required this.seats,
    this.savedAt,
  });

  _Recent copyWith({
    String? from,
    String? to,
    String? dateIso,
    int? seats,
    DateTime? savedAt,
  }) =>
      _Recent(
        from: from ?? this.from,
        to: to ?? this.to,
        dateIso: dateIso ?? this.dateIso,
        seats: seats ?? this.seats,
        savedAt: savedAt ?? this.savedAt,
      );

  Map<String, dynamic> toJson() => {
        'from': from,
        'to': to,
        'dateIso': dateIso,
        'seats': seats,
        'savedAt': savedAt?.toIso8601String(),
      };

  factory _Recent.fromJson(Map<String, dynamic> json) => _Recent(
        from: (json['from'] ?? '') as String,
        to: (json['to'] ?? '') as String,
        dateIso: json['dateIso'] as String?,
        seats: (json['seats'] ?? 1) as int,
        savedAt: json['savedAt'] == null
            ? null
            : DateTime.tryParse(json['savedAt'] as String),
      );
}

class _PlacePrediction {
  final String description;
  final String placeId;

  _PlacePrediction({required this.description, required this.placeId});
}
