// lib/features/home/pages/offer_ride_page_mobile.dart
// NOTE: Mobile version with HTTP Google Places autocomplete (NO google_place)
// LIVE VEHICLE PHOTO: Mobile picker + Firebase Storage upload + preview + trips/trips_live updates
// Upload path follows your rules: vehicles/{uid}/{plate}/... or user_uploads/{uid}/...

// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'package:latlong2/latlong.dart'; // ✅ for LatLng if needed
import 'package:doraride_appp/services/places_service.dart'; // ✅ NEW
import 'package:doraride_appp/services/get_place_details_cached.dart'; // ✅ if you cache details

import '../../../app_router.dart';

// Brand color
const _kThemeBlue = Color(0xFF180D3B);
final DateFormat _dateDisplayFormatter = DateFormat('EEE, MMM d, yyyy');

// ------------------------------
// Places Autocomplete (Mobile)
// ------------------------------

class _PlacePrediction {
  final String description;
  final String placeId;
  final Object? rawPrediction;

  _PlacePrediction({
    required this.description,
    required this.placeId,
    this.rawPrediction,
  });
}

class _PlacesMobile {
  static late PlacesService _places;

  static void initialize(String apiKey) {
    _places = PlacesService(apiKey: apiKey);

  }

  static Future<bool> _waitForGoogleMaps({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // Mobile uses HTTP Places API, nothing to "wait" for.
    return true;
  }

  static Future<List<_PlacePrediction>> autocomplete(
    String input, {
    String? country,
  }) async {
    if (input.trim().isEmpty) return const [];

    try {
      final results = await _places.autocomplete(
        input,
        countryCode: (country != null && country.isNotEmpty) ? country : null,
        language: 'en',
      );

      return results.map((p) {
        return _PlacePrediction(
          description: p.description,
          placeId: p.placeId,
          rawPrediction: p,
        );
      }).toList();
    } catch (e) {
      debugPrint('Places autocomplete error: $e');
      return [];
    }
  }
}

class _PlacesField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final String? country;
  final FormFieldValidator<String>? validator;
  final TextInputAction textInputAction;
  final void Function()? onChangedForPriceRecompute;

  /// description = full display text from Google
  /// countryName = best guess country name (optional, may be null)
  final void Function(String description, String? countryName)? onPlaceSelected;

  const _PlacesField({
    required this.controller,
    required this.hintText,
    this.country,
    this.validator,
    this.textInputAction = TextInputAction.next,
    this.onChangedForPriceRecompute,
    this.onPlaceSelected,
  });

  @override
  State<_PlacesField> createState() => _PlacesFieldState();
}

class _PlacesFieldState extends State<_PlacesField> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlay;
  List<_PlacePrediction> _items = const [];
  Timer? _deb;
  bool _focused = false;
  bool _overlayPointerDown = false;

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocus);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _deb?.cancel();
    _removeOverlay();
    _focusNode.removeListener(_handleFocus);
    _focusNode.dispose();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _handleFocus() {
    setState(() => _focused = _focusNode.hasFocus);
    if (!_focusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 120), () {
        if (!_overlayPointerDown) _removeOverlay();
      });
    } else {
      _maybeQuery();
    }
  }

  void _onTextChanged() {
    widget.onChangedForPriceRecompute?.call();
    _maybeQuery();
  }

  void _maybeQuery() {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 300), () async {
      final q = widget.controller.text.trim();
      if (!_focused || q.length < 2) {
        _items = const [];
        _updateOverlay();
        return;
      }
      final res = await _PlacesMobile.autocomplete(q, country: widget.country);
      if (!mounted) return;
      _items = res;
      _updateOverlay();
    });
  }

  void _updateOverlay() {
    if (!_focused || _items.isEmpty) {
      _removeOverlay();
      return;
    }
    if (_overlay == null) {
      _overlay = OverlayEntry(builder: _buildOverlay);
      Overlay.of(context, rootOverlay: true).insert(_overlay!);
    } else {
      _overlay!.markNeedsBuild();
    }
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  Widget _buildOverlay(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 360;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _removeOverlay,
          ),
        ),
        Positioned.fill(
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            offset: const Offset(0, 52),
            child: Material(
              elevation: 4,
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 280, minWidth: width, maxWidth: width),
                child: Listener(
                  onPointerDown: (_) => _overlayPointerDown = true,
                  onPointerUp: (_) => Future.microtask(() => _overlayPointerDown = false),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemBuilder: (_, i) {
                      final p = _items[i];
                      return ListTile(
                        leading: const Icon(Icons.location_on_outlined, size: 20),
                        title: Text(p.description),
                        onTap: () async {
                          widget.controller.text = p.description;
                          widget.controller.selection = TextSelection.fromPosition(
                            TextPosition(offset: widget.controller.text.length),
                          );

                          final guessedCountry =
                              _extractCountryFromPlaceDescription(p.description);

                          widget.onPlaceSelected?.call(p.description, guessedCountry);

                          _removeOverlay();
                          _focusNode.unfocus();
                        },
                      );
                    },
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemCount: _items.length,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: TextFormField(
        focusNode: _focusNode,
        controller: widget.controller,
        textInputAction: widget.textInputAction,
        decoration: InputDecoration(
          hintText: widget.hintText,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.search),
        ),
        validator: widget.validator,
        onTap: () {
          if (_items.isNotEmpty) _updateOverlay();
        },
      ),
    );
  }
}

// ------------------------------
// Currency helpers (top level)
// ------------------------------

/// Small internal model for a currency result
class _CurrencyInfo {
  final String code;
  final String symbol;
  final String name;
  const _CurrencyInfo({
    required this.code,
    required this.symbol,
    required this.name,
  });
}

/// Extract a country name from a Google Places description like:
/// "Paris, Île-de-France, France" → "France"
String? _extractCountryFromPlaceDescription(String description) {
  final trimmed = description.trim();
  if (trimmed.isEmpty) return null;

  final parts = trimmed.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return null;

  return parts.last;
}

// ------------------------------
// OfferRidePage
// ------------------------------

class _TripStop {
  final TextEditingController locationCtrl;
  _TripStop({required String location}) : locationCtrl = TextEditingController(text: location);
  void dispose() => locationCtrl.dispose();
}

class OfferRidePage extends StatefulWidget {
  final String? tripIdToEdit;
  const OfferRidePage({super.key, this.tripIdToEdit});

  @override
  State<OfferRidePage> createState() => _OfferRidePageState();
}

class _OfferRidePageState extends State<OfferRidePage> {
  final _formKey = GlobalKey<FormState>();
  bool get isEditing => widget.tripIdToEdit != null;

  bool _hasAcceptedBookings = false;

  // 🌍 Currency auto-detected from origin via Google Places + REST Countries
  // Default to INR; will auto-change after user picks a location.
  String _currencyCode = 'INR';
  String _currencySymbol = '₹';
  String _currencyName = 'Indian rupee';

  // Itinerary
  final TextEditingController _originCtrl = TextEditingController();
  final TextEditingController _destinationCtrl = TextEditingController();
  final List<_TripStop> _stops = [];
  bool get _canAddMoreStops => _stops.length < 7;

  // Date / time
  final TextEditingController _dateCtrl = TextEditingController();
  final TextEditingController _timeCtrl = TextEditingController();

  // Return
  bool _returnEnabled = false;
  final TextEditingController _returnDateCtrl = TextEditingController();
  final TextEditingController _returnTimeCtrl = TextEditingController();

  // Seats / pricing / prefs / etc.
  int _seats = 1;
  final TextEditingController _tripPriceCtrl = TextEditingController();
  final Map<String, TextEditingController> _segmentPriceCtrls = {};
  final TextEditingController _extraLuggagePriceCtrl = TextEditingController();
  final TextEditingController _premiumExtraCtrl = TextEditingController();
  String _luggageSize = 'M';
  int _backRow = 3;
  bool _otherWinter = false;
  bool _otherBikes = false;
  bool _otherSkis = false;
  bool _otherPets = false;
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _companyCtrl = TextEditingController();
  final TextEditingController _modelCtrl = TextEditingController();
  final TextEditingController _yearCtrl = TextEditingController();
  final TextEditingController _colorCtrl = TextEditingController();
  final TextEditingController _plateCtrl = TextEditingController();

  // vehicle choice from Vehicles page
  String? _selectedVehicleId;

  // NEW: selected recent trip template id for dropdown
  String? _selectedTemplateTripId;

  // Vehicle photo state
  File? _vehiclePhoto;
  Uint8List? _vehiclePhotoBytesWeb;
  String? _vehiclePhotoUrl;
  double? _uploadProgress;
  bool _agreeRules = false;

  List<String> _currentSegmentTitles = [];
  bool get _hasAnySegmentPricesFilled =>
      _segmentPriceCtrls.values.any((c) => c.text.isNotEmpty);

  // Auth
  final _auth = FirebaseAuth.instance;
  User? get _user => _auth.currentUser;
  Future<void> _ensureSignedIn() async {
    if (_auth.currentUser == null) await _auth.signInAnonymously();
  }

  // Google Places API key - YOU NEED TO ADD YOUR OWN KEY HERE
  static const String _googlePlacesApiKey = 'AIzaSyCDw81VLlIITSG1IOK8G2cTIi5lPY-TeW8';

  @override
  void initState() {
    super.initState();
    // Initialize Google Places for mobile
    _PlacesMobile.initialize(_googlePlacesApiKey);

    _recomputeSegmentPrices();
    _ensureSignedIn();
    _tripPriceCtrl.addListener(_updateFullSegmentPrice);
    if (widget.tripIdToEdit != null) {
      _loadTripForEdit(widget.tripIdToEdit!);
    }
  }

  void _disposeSegmentControllers() {
    for (final c in _segmentPriceCtrls.values) {
      c.dispose();
    }
    _segmentPriceCtrls.clear();
  }

  void _updateFullSegmentPrice() {
    final main = _tripPriceCtrl.text.trim();
    final o = _originCtrl.text.trim().toLowerCase();
    final d = _destinationCtrl.text.trim().toLowerCase();
    if (o.isEmpty || d.isEmpty) return;
    final key = '$o to $d';
    final ctrl = _segmentPriceCtrls[key];
    if (ctrl != null && ctrl.text.trim() != main) {
      ctrl.text = main;
      ctrl.selection = TextSelection.fromPosition(
        TextPosition(offset: ctrl.text.length),
      );
    }
  }

  /// Call REST Countries API to get currency data for a given country name.
  /// https://restcountries.com/v3.1/name/{name}?fields=currencies,name
  Future<_CurrencyInfo?> _lookupCurrencyForCountry(String countryName) async {
    try {
      final path = '/v3.1/name/$countryName';

      // 1) exact (fullText=true)
      final uriFull = Uri.https('restcountries.com', path, {
        'fullText': 'true',
        'fields': 'currencies,name',
      });

      http.Response resp;
      try {
        resp = await http.get(uriFull).timeout(const Duration(seconds: 8));
      } on TimeoutException {
        resp = http.Response('', 408);
      }

      if (resp.statusCode == 404 || resp.statusCode == 400 || resp.statusCode == 408) {
        // 2) relaxed search (no fullText)
        final uriLoose = Uri.https('restcountries.com', path, {
          'fields': 'currencies,name',
        });
        resp = await http.get(uriLoose).timeout(const Duration(seconds: 8));
      }

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        debugPrint('REST Countries error (${resp.statusCode}): ${resp.body}');
        return null;
      }

      final decoded = jsonDecode(resp.body);
      Map<String, dynamic>? firstCountry;
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        firstCountry = (decoded.first as Map).cast<String, dynamic>();
      } else if (decoded is Map<String, dynamic>) {
        firstCountry = decoded;
      }

      if (firstCountry == null) return null;

      final currenciesRaw = firstCountry['currencies'];
      if (currenciesRaw is! Map) return null;

      final currencies = currenciesRaw.cast<String, dynamic>();
      if (currencies.isEmpty) return null;

      final entry = currencies.entries.first;
      final code = entry.key;
      final data = (entry.value as Map).cast<String, dynamic>();

      final name = (data['name'] as String?) ?? code;
      final symbol = (data['symbol'] as String?) ?? code;

      return _CurrencyInfo(code: code, symbol: symbol, name: name);
    } catch (e) {
      debugPrint('Currency lookup failed: $e');
      return null;
    }
  }

  /// Public helper: update the page-level currency from a Places description
  /// Optionally accepts an explicit country name (from our heuristic).
  Future<void> _updateCurrencyFromPlace(
    String placeDescription, {
    String? countryOverride,
  }) async {
    final countryName = (countryOverride?.trim().isNotEmpty ?? false)
        ? countryOverride!.trim()
        : _extractCountryFromPlaceDescription(placeDescription);

    if (countryName == null) {
      // No clear country found; keep existing currency as fallback.
      return;
    }

    final info = await _lookupCurrencyForCountry(countryName);
    if (!mounted || info == null) return;

    setState(() {
      _currencyCode = info.code;
      _currencySymbol = info.symbol;
      _currencyName = info.name;
    });
  }

  Future<void> _loadTripForEdit(String tripId) async {
    try {
      final tripRef = FirebaseFirestore.instance.collection('trips').doc(tripId);

      final bookingsSnap = await tripRef
          .collection('booking_requests')
          .where('status', isEqualTo: 'accepted')
          .limit(1)
          .get();
      final lock = bookingsSnap.docs.isNotEmpty;

      final doc = await tripRef.get();
      if (!doc.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Trip not found for editing.')),
        );
        return;
      }

      final data = doc.data()!;

      // Clear old state
      for (final s in _stops) s.dispose();
      _stops.clear();
      _disposeSegmentControllers();

      _originCtrl.text = (data['origin'] ?? '') as String;
      _destinationCtrl.text = (data['destination'] ?? '') as String;

      final stopsDataList = (data['stops'] as List<dynamic>?)
              ?.map((s) => s is Map ? s['location'] : s.toString())
              .toList() ??
          [];
      for (final loc in stopsDataList) {
        _stops.add(_TripStop(location: loc));
      }

      if (data['date'] is Timestamp) {
        final dt = (data['date'] as Timestamp).toDate();
        _dateCtrl.text = _toStorageFormat(dt);
        _timeCtrl.text = (data['time'] ?? DateFormat.jm().format(dt)) as String;
      }
      _returnEnabled = false;

      final seatsAvail = (data['seatsAvailable'] as int?) ?? 1;
      final basePrice = (data['pricePerSeat'] as num?)?.toStringAsFixed(2) ?? '';
      final premiumExtra = (data['premiumExtra'] as num?)?.toStringAsFixed(2) ?? '';
      final extraLuggagePrice =
          (data['extraLuggagePrice'] as num?)?.toStringAsFixed(2) ?? '';

      // Read existing currency (if any)
      final existingCode = data['currencyCode'] as String?;
      final existingSymbol = data['currencySymbol'] as String?;
      final existingName = data['currencyName'] as String?;

      setState(() {
        _hasAcceptedBookings = lock;
        _seats = seatsAvail;
        _tripPriceCtrl.text = basePrice;
        _premiumExtraCtrl.text = premiumExtra;
        _extraLuggagePriceCtrl.text = extraLuggagePrice;
        _luggageSize = (data['luggageSize'] ?? 'M') as String;
        _otherPets = (data['allowsPets'] as bool?) ?? false;
        _descCtrl.text = (data['description'] ?? '') as String;
        _agreeRules = true;

        _vehiclePhotoUrl = (data['carPhotoUrl'] as String?);

        if (existingCode != null && existingSymbol != null) {
          _currencyCode = existingCode;
          _currencySymbol = existingSymbol;
          if (existingName != null && existingName.isNotEmpty) {
            _currencyName = existingName;
          }
        }
      });

      final seg =
          (data['segmentPrices'] as Map<String, dynamic>?)?.cast<String, num>() ?? {};
      _recomputeSegmentPrices();
      for (final e in seg.entries) {
        if (_segmentPriceCtrls.containsKey(e.key)) {
          _segmentPriceCtrls[e.key]!.text = e.value.toStringAsFixed(2);
        }
      }

      _companyCtrl.text = (data['carCompany'] ?? '') as String;
      _modelCtrl.text = (data['carModel'] ?? '') as String;
      _colorCtrl.text = (data['carColor'] ?? '') as String;
      _yearCtrl.text =
          (data['carYear'] is int) ? (data['carYear'] as int).toString() : '';
      _plateCtrl.text = (data['carPlate'] ?? '') as String;

      // ✅ Only auto-detect currency if no stored currency exists
      if (existingCode == null || existingSymbol == null) {
        _updateCurrencyFromPlace(_originCtrl.text);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading data: $e')),
      );
    }
  }

  /// NEW: Reuse one of the driver's last trips as a template (NOT edit mode).
  /// NOTE: As requested, this copies everything EXCEPT date & time.
  Future<void> _reuseTripFromTemplate(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    if (data == null) return;

    // Clear old stops & segment controllers
    for (final s in _stops) {
      s.dispose();
    }
    _stops.clear();
    _disposeSegmentControllers();

    // Basic itinerary
    final origin = (data['origin'] ?? '') as String;
    final destination = (data['destination'] ?? '') as String;
    final stopsDataList = (data['stops'] as List<dynamic>?)
            ?.map((s) => s is Map ? s['location'] : s.toString())
            .toList() ??
        [];

    // Date/time from previous trip are intentionally NOT reused
    // (driver must choose fresh date & time)
    String storedDate = '';
    String storedTime = '';

    final rawDate = data['date'];
    if (rawDate is Timestamp) {
      // We still parse it only to maybe show something later if needed,
      // but we DO NOT set controllers with this.
      final dt = rawDate.toDate();
      storedDate = _toStorageFormat(dt);
      storedTime = DateFormat.jm().format(dt);
    } else if (rawDate is String && rawDate.isNotEmpty) {
      storedDate = rawDate;
    }

    final basePrice = (data['pricePerSeat'] as num?)?.toStringAsFixed(2) ?? '';
    final premiumExtra =
        (data['premiumExtra'] as num?)?.toStringAsFixed(2) ?? '';
    final extraLuggagePrice =
        (data['extraLuggagePrice'] as num?)?.toStringAsFixed(2) ?? '';

    final existingCode = data['currencyCode'] as String?;
    final existingSymbol = data['currencySymbol'] as String?;
    final existingName = data['currencyName'] as String?;

    setState(() {
      // Itinerary
      _originCtrl.text = origin;
      _destinationCtrl.text = destination;
      for (final loc in stopsDataList) {
        _stops.add(_TripStop(location: loc));
      }

      // 🚨 IMPORTANT: Date/time NOT prefilled (user must choose again)
      _dateCtrl.clear();
      _timeCtrl.clear();

      // No return prefilled; driver can add if needed
      _returnEnabled = false;
      _returnDateCtrl.clear();
      _returnTimeCtrl.clear();

      // Seats & pricing
      _seats = (data['seatsTotal'] as int?) ?? 1;
      _tripPriceCtrl.text = basePrice;
      _premiumExtraCtrl.text = premiumExtra;
      _extraLuggagePriceCtrl.text = extraLuggagePrice;

      // Trip prefs
      _luggageSize = (data['luggageSize'] ?? 'M') as String;
      _otherPets = (data['allowsPets'] as bool?) ?? false;
      _descCtrl.text = (data['description'] ?? '') as String;
      _backRow = (data['backRowLimit'] as int?) ?? _backRow;
      _otherWinter = (data['otherWinter'] as bool?) ?? _otherWinter;
      _otherBikes = (data['otherBikes'] as bool?) ?? _otherBikes;
      _otherSkis = (data['otherSkis'] as bool?) ?? _otherSkis;

      // Vehicle details
      _companyCtrl.text = (data['carCompany'] ?? '') as String;
      _modelCtrl.text = (data['carModel'] ?? '') as String;
      _colorCtrl.text = (data['carColor'] ?? '') as String;
      _yearCtrl.text = (data['carYear'] is int)
          ? (data['carYear'] as int).toString()
          : (data['carYear']?.toString() ?? '');
      _plateCtrl.text = (data['carPlate'] ?? '') as String;

      _vehiclePhotoUrl = (data['carPhotoUrl'] as String?);
      _vehiclePhoto = null;
      _vehiclePhotoBytesWeb = null;

      // Currency
      if (existingCode != null && existingSymbol != null) {
        _currencyCode = existingCode;
        _currencySymbol = existingSymbol;
        if (existingName != null && existingName.isNotEmpty) {
          _currencyName = existingName;
        }
      }

      // Make sure the form is fully editable (this is NOT edit mode)
      _hasAcceptedBookings = false;
      _agreeRules = true;
    });

    // Rebuild segment prices based on restored itinerary & apply stored values
    _recomputeSegmentPrices();
    final seg =
        (data['segmentPrices'] as Map<String, dynamic>?)?.cast<String, num>() ?? {};
    for (final e in seg.entries) {
      if (_segmentPriceCtrls.containsKey(e.key)) {
        _segmentPriceCtrls[e.key]!.text = e.value.toStringAsFixed(2);
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Trip loaded. Choose a new date & time and post again.'),
      ),
    );
  }

  @override
  void dispose() {
    _originCtrl.dispose();
    _destinationCtrl.dispose();
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    _returnDateCtrl.dispose();
    _returnTimeCtrl.dispose();

    _tripPriceCtrl.removeListener(_updateFullSegmentPrice);
    _tripPriceCtrl.dispose();

    _extraLuggagePriceCtrl.dispose();
    _premiumExtraCtrl.dispose();
    _descCtrl.dispose();
    _companyCtrl.dispose();
    _modelCtrl.dispose();
    _yearCtrl.dispose();
    _colorCtrl.dispose();
    _plateCtrl.dispose();

    for (final s in _stops) s.dispose();
    _disposeSegmentControllers();
    super.dispose();
  }

  String _toStorageFormat(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _getDisplayDate(String storedDate) {
    if (storedDate.isEmpty) return 'Select date';
    try {
      final date = DateTime.parse(storedDate);
      return _dateDisplayFormatter.format(date);
    } catch (_) {
      return 'Select date';
    }
  }

  String _getDisplayTime(String storedTime, BuildContext context) {
    if (storedTime.isEmpty) return 'Select time';
    return storedTime;
  }

  Future<void> _pickDate(TextEditingController target) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
      initialDate:
          target.text.isNotEmpty ? DateTime.tryParse(target.text) ?? now : now,
    );
    if (picked != null) setState(() => target.text = _toStorageFormat(picked));
  }

  DateTime? _parseTime(String timeString, DateTime baseDate) {
    if (timeString.isEmpty) return null;
    final candidates = [DateFormat.jm(), DateFormat.Hm()];
    DateTime? parsed;
    for (final f in candidates) {
      try {
        parsed = f.parse(timeString);
        break;
      } catch (_) {}
    }
    if (parsed == null) return null;
    return DateTime(baseDate.year, baseDate.month, baseDate.day, parsed.hour, parsed.minute);
  }

  Future<void> _pickTime(TextEditingController target) async {
    TimeOfDay initialTime = TimeOfDay.now();
    if (target.text.isNotEmpty) {
      try {
        final dt = DateFormat.jm().parse(target.text);
        initialTime = TimeOfDay.fromDateTime(dt);
      } catch (_) {}
    }

    final snapped = (initialTime.minute / 15).round() * 15;
    initialTime = initialTime.replacing(
      minute: snapped % 60,
      hour: initialTime.hour + (snapped ~/ 60),
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked != null) {
      final m = (picked.minute / 15).round() * 15;
      final finalTime = picked.replacing(minute: m % 60, hour: picked.hour + (m ~/ 60));
      setState(() => target.text = finalTime.format(context));
    }
  }

  void _swapOriginDestination() {
    final o = _originCtrl.text;
    _originCtrl.text = _destinationCtrl.text;
    _destinationCtrl.text = o;
    _recomputeSegmentPrices();
    _updateCurrencyFromPlace(_originCtrl.text);
  }

  void _addStop() {
    if (!_canAddMoreStops) return;
    setState(() {
      _stops.add(_TripStop(location: ''));
      _recomputeSegmentPrices();
    });
  }

  void _removeStop(int i) {
    setState(() {
      _stops[i].dispose();
      _stops.removeAt(i);
      _recomputeSegmentPrices();
    });
  }

  void _recomputeSegmentPrices() {
    final points = <String>[
      _originCtrl.text.trim(),
      ..._stops.map((s) => s.locationCtrl.text.trim()),
      _destinationCtrl.text.trim(),
    ].where((p) => p.isNotEmpty).toList();

    final newTitles = <String>[];
    if (points.length >= 2) {
      for (var i = 0; i < points.length; i++) {
        for (var j = i + 1; j < points.length; j++) {
          final title = '${points[i]} to ${points[j]}';
          if (i == 0 && j == points.length - 1) continue;
          newTitles.add(title);
        }
      }
    }

    final current = _segmentPriceCtrls.keys.toSet();
    final newer = newTitles.toSet();

    for (final dead in current.difference(newer)) {
      _segmentPriceCtrls[dead]?.dispose();
      _segmentPriceCtrls.remove(dead);
    }
    for (final add in newer.difference(current)) {
      _segmentPriceCtrls[add] = TextEditingController();
    }

    _currentSegmentTitles = newTitles;
    setState(_updateFullSegmentPrice);
  }

  Future<void> _pushPhotoUrlToLiveIfEditing() async {
    if (!isEditing || widget.tripIdToEdit == null || _vehiclePhotoUrl == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('trips_live')
          .doc(widget.tripIdToEdit)
          .set({'carPhotoUrl': _vehiclePhotoUrl}, SetOptions(merge: true));
    } catch (_) {}
  }

  String? _validateItineraryChronology() {
    final all = <String>{};
    if (_originCtrl.text.trim().isNotEmpty) {
      all.add(_originCtrl.text.trim().toLowerCase());
    }
    for (final s in _stops) {
      final t = s.locationCtrl.text.trim();
      if (t.isEmpty) continue;
      if (!all.add(t.toLowerCase())) return 'Duplicate location found: $t.';
    }
    final d = _destinationCtrl.text.trim();
    if (d.isNotEmpty && !all.add(d.toLowerCase())) {
      return 'Duplicate location found: $d.';
    }
    return null;
  }

  Future<void> _deletePost() async {
    if (_hasAcceptedBookings) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot cancel a trip that has accepted bookings.')),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Cancellation'),
        content: const Text(
            'Are you sure you want to cancel this trip? It will be moved to the Canceled section.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Do Not Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Post'),
          ),
        ],
      ),
    );
    if (confirm != true || widget.tripIdToEdit == null) return;

    try {
      await FirebaseFirestore.instance.collection('trips').doc(widget.tripIdToEdit).update({
        'status': 'cancelled',
        'deletedAt': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance.collection('trips_live').doc(widget.tripIdToEdit).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Trip successfully canceled.')));
      Navigator.of(context).popUntil((r) => r.isFirst);
      Navigator.of(context).pushReplacementNamed(Routes.home, arguments: 'trips');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to cancel: $e')));
    }
  }

  Future<void> _showSuccessDialog(
      BuildContext context, bool isEditing, bool hasReturn) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(isEditing ? 'Update Successful' : 'Trip Posted'),
        content: Text(isEditing
            ? 'Your trip has been successfully updated and saved.'
            : 'Your trip ${hasReturn ? "and your return trip" : ""} have been successfully posted.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              Navigator.of(context).pushReplacementNamed(Routes.home, arguments: 'trips');
            },
            child: const Text('OK'),
          )
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_hasAcceptedBookings) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This trip has accepted bookings and cannot be saved.')),
      );
      return;
    }

    final dep = _composeDeparture();
    final isEditing = widget.tripIdToEdit != null;

    if (!isEditing) {
      if (dep == null || dep.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The main departure time must be in the future.')),
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

    final chronoError = _validateItineraryChronology();
    if (chronoError != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Chronology error: $chronoError')));
      return;
    }

    DateTime? returnDep;
    if (_returnEnabled) {
      returnDep = _composeReturnDeparture();
      if (returnDep == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a valid return date and time.')),
        );
        return;
      }
    }

    await _ensureSignedIn();
    final uid = _user?.uid ?? 'unknown';

    final profile =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final driverName = (profile.data()?['displayName'] ?? 'Driver') as String;
    final carModel = (profile.data()?['carModel'] ?? '') as String;
    final carColor = (profile.data()?['carColor'] ?? '') as String;

    final basePrice = double.tryParse(_tripPriceCtrl.text.trim()) ?? 0.0;
    final extraLuggage = double.tryParse(_extraLuggagePriceCtrl.text.trim());
    final premiumExtra = double.tryParse(_premiumExtraCtrl.text.trim());
    final hasPremium = premiumExtra != null && premiumExtra > 0;

    final stopsData = _stops
        .where((s) => s.locationCtrl.text.trim().isNotEmpty)
        .map((s) => {'location': s.locationCtrl.text.trim()})
        .toList(growable: false);

    final segPrices = <String, double>{};
    final o = _originCtrl.text.trim().toLowerCase();
    final d = _destinationCtrl.text.trim().toLowerCase();
    final fullKey = '$o to $d';
    if (basePrice > 0) segPrices[fullKey] = basePrice;
    for (final t in _currentSegmentTitles) {
      final v = double.tryParse(_segmentPriceCtrls[t]?.text.trim() ?? '');
      if (v != null) segPrices[t] = v;
    }

    try {
      final trips = FirebaseFirestore.instance.collection('trips');
      final live = FirebaseFirestore.instance.collection('trips_live');

      final Map<String, dynamic> outboundTrip = {
        'driverId': uid,
        'driverName': driverName,
        'origin': _originCtrl.text.trim(),
        'destination': _destinationCtrl.text.trim(),
        'originLower': o,
        'destinationLower': d,
        'date': Timestamp.fromDate(dep!),
        'time': _timeCtrl.text.trim(),
        'status': 'active',
        'stops': stopsData,
        'segmentPrices': segPrices.isEmpty ? null : segPrices,
        'pricePerSeat': basePrice,
        'extraLuggagePrice': extraLuggage,
        'isPremiumSeatAvailable': hasPremium,
        'premiumExtra': hasPremium ? premiumExtra : null,
        'seatsTotal': _seats,
        'seatsAvailable': _seats,
        'allowsPets': _otherPets,
        'luggageSize': _luggageSize,
        'backRowLimit': _backRow,
        'description': _descCtrl.text.trim(),
        'carModel': carModel,
        'carColor': carColor,
        'carCompany':
            _companyCtrl.text.trim().isEmpty ? null : _companyCtrl.text.trim(),
        'carYear': _yearCtrl.text.trim().isEmpty
            ? null
            : int.tryParse(_yearCtrl.text.trim()),
        'carPlate':
            _plateCtrl.text.trim().isEmpty ? null : _plateCtrl.text.trim(),
        'carPhotoUrl': _vehiclePhotoUrl,
        'createdAt': FieldValue.serverTimestamp(),

        // NEW: fields for auto-start / auto-complete
        'autoStatus': 'scheduled', // scheduled → ongoing → completed
        'startedAt': null,
        'completedAt': null,

        // 🌍 NEW: currency
        'currencyCode': _currencyCode,
        'currencySymbol': _currencySymbol,
        'currencyName': _currencyName,
      };

      String tripId;
      if (isEditing) {
        tripId = widget.tripIdToEdit!;
        outboundTrip.remove('createdAt');
        await trips.doc(tripId).update(outboundTrip);
      } else {
        final ref = await trips.add(outboundTrip);
        tripId = ref.id;

        if (_returnEnabled && returnDep != null) {
          final returnStops = stopsData.reversed.toList();
          final ro = _destinationCtrl.text.trim().toLowerCase();
          final rd = _originCtrl.text.trim().toLowerCase();

          final returnSegPrices = <String, double>{};

          // ✅ Mirror full base seat price for full route (Toronto → Montreal etc.)
          if (basePrice > 0) {
            returnSegPrices['$ro to $rd'] = basePrice;
          }

          // ✅ Mirror all segment prices: A → B (outbound) => B → A (return)
          segPrices.forEach((key, value) {
            // Skip outbound full key; already mirrored by ro/rd above
            if (key == fullKey) return;

            final parts = key.split(' to ');
            if (parts.length != 2) return;

            final from = parts[0];
            final to = parts[1];

            final reversedKey = '$to to $from';

            // Do not overwrite if somehow already set
            returnSegPrices.putIfAbsent(reversedKey, () => value);
          });

          final Map<String, dynamic> returnTrip = {
            'driverId': uid,
            'driverName': driverName,
            'origin': _destinationCtrl.text.trim(),
            'destination': _originCtrl.text.trim(),
            'originLower': ro,
            'destinationLower': rd,
            'date': Timestamp.fromDate(returnDep),
            'time': _returnTimeCtrl.text.trim(),
            'status': 'active',
            'stops': returnStops,
            'segmentPrices':
                returnSegPrices.isEmpty ? null : returnSegPrices,
            'pricePerSeat': basePrice,
            'extraLuggagePrice': extraLuggage,
            'isPremiumSeatAvailable': hasPremium,
            'premiumExtra': hasPremium ? premiumExtra : null,
            'seatsTotal': _seats,
            'seatsAvailable': _seats,
            'allowsPets': _otherPets,
            'luggageSize': _luggageSize,
            'backRowLimit': _backRow,
            'description': _descCtrl.text.trim(),
            'carModel': carModel,
            'carColor': carColor,
            'carCompany': _companyCtrl.text.trim().isEmpty
                ? null
                : _companyCtrl.text.trim(),
            'carYear': _yearCtrl.text.trim().isEmpty
                ? null
                : int.tryParse(_yearCtrl.text.trim()),
            'carPlate': _plateCtrl.text.trim().isEmpty
                ? null
                : _plateCtrl.text.trim(),
            'carPhotoUrl': _vehiclePhotoUrl,
            'createdAt': FieldValue.serverTimestamp(),

            // NEW: same auto fields for return trip
            'autoStatus': 'scheduled',
            'startedAt': null,
            'completedAt': null,

            // 🌍 NEW: currency for return
            'currencyCode': _currencyCode,
            'currencySymbol': _currencySymbol,
            'currencyName': _currencyName,
          };

          final rRef = await trips.add(returnTrip);
          final rId = rRef.id;

          final returnLive = {
            'driverId': uid,
            'driverName': driverName,
            'origin': _destinationCtrl.text.trim(),
            'destination': _originCtrl.text.trim(),
            'originLower': ro,
            'destinationLower': rd,
            'dateOut': Timestamp.fromDate(returnDep),
            'time': _returnTimeCtrl.text.trim(),
            'status': 'open',
            'price': basePrice,
            'pricePerSeat': basePrice,
            'extraLuggagePrice': extraLuggage,
            'isPremiumSeatAvailable': hasPremium,
            'premiumExtra': hasPremium ? premiumExtra : null,
            'seatsTotal': _seats,
            'seatsAvailable': _seats,
            'allowsPets': _otherPets,
            'luggageSize': _luggageSize,
            'backRowLimit': _backRow,
            'carModel': carModel,
            'carColor': carColor,
            'stops': returnStops,
            'carPhotoUrl': _vehiclePhotoUrl,

            // 🌍 NEW: currency in live mirror
            'currencyCode': _currencyCode,
            'currencySymbol': _currencySymbol,
            'currencyName': _currencyName,
          };
          await live.doc(rId).set(returnLive, SetOptions(merge: true));
        }
      }

      final outboundLive = {
        'driverId': uid,
        'driverName': driverName,
        'origin': _originCtrl.text.trim(),
        'destination': _destinationCtrl.text.trim(),
        'originLower': o,
        'destinationLower': d,
        'dateOut': Timestamp.fromDate(dep),
        'time': _timeCtrl.text.trim(),
        'status': 'open',
        'price': basePrice,
        'pricePerSeat': basePrice,
        'extraLuggagePrice': extraLuggage,
        'isPremiumSeatAvailable': hasPremium,
        'premiumExtra': hasPremium ? premiumExtra : null,
        'seatsTotal': _seats,
        'seatsAvailable': _seats,
        'allowsPets': _otherPets,
        'luggageSize': _luggageSize,
        'backRowLimit': _backRow,
        'carModel': carModel,
        'carColor': carColor,
        'stops': stopsData,
        'carPhotoUrl': _vehiclePhotoUrl,

        // 🌍 NEW: currency in live mirror
        'currencyCode': _currencyCode,
        'currencySymbol': _currencySymbol,
        'currencyName': _currencyName,
      };
      await live.doc(tripId).set(outboundLive, SetOptions(merge: true));

      if (!mounted) return;
      await _showSuccessDialog(
          context, isEditing, _returnEnabled && returnDep != null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to ${isEditing ? 'update' : 'post'}: $e')),
      );
    }
  }

  DateTime? _composeDeparture() {
    if (_dateCtrl.text.isEmpty || _timeCtrl.text.isEmpty) return null;
    final d = DateTime.tryParse(_dateCtrl.text);
    if (d == null) return null;
    return _parseTime(_timeCtrl.text, d);
  }

  DateTime? _composeReturnDeparture() {
    if (_returnDateCtrl.text.isEmpty || _returnTimeCtrl.text.isEmpty) return null;
    final d = DateTime.tryParse(_returnDateCtrl.text);
    if (d == null) return null;
    return _parseTime(_returnTimeCtrl.text, d);
  }

  // Helper to open URLs
  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link.')),
        );
      }
    }
  }

  // ---- Saved vehicles dropdown + Add button ----
  Widget _buildSavedVehiclePicker() {
    final user = _user;
    if (user == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('vehicles')
          .orderBy('updatedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No saved vehicles yet.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.black.withOpacity(0.7)),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kThemeBlue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () =>
                      Navigator.of(context).pushNamed(Routes.vehicles),
                  icon: const Icon(Icons.add),
                  label: const Text('Add new vehicle'),
                ),
              ),
            ],
          );
        }

        final docs = snapshot.data!.docs;
        _selectedVehicleId ??= docs.first.id;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose vehicle',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedVehicleId,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: docs.map((d) {
                final v = d.data();
                final title =
                    '${v['make'] ?? ''} ${v['model'] ?? ''} (${v['plate'] ?? ''}) • ${v['seats'] ?? ''} seats';
                return DropdownMenuItem<String>(
                  value: d.id,
                  child: Text(title),
                );
              }).toList(),
              onChanged: (value) {
                if (value == null) return;
                final doc = docs.firstWhere((d) => d.id == value);
                final v = doc.data();
                setState(() {
                  _selectedVehicleId = value;
                  _companyCtrl.text = (v['make'] ?? '') as String;
                  _modelCtrl.text = (v['model'] ?? '') as String;
                  _colorCtrl.text = (v['color'] ?? '') as String;
                  _plateCtrl.text = (v['plate'] ?? '') as String;

                  final s = v['seats'];
                  if (s is int && s > 0) _seats = s;

                  final photo = v['photoUrl'];
                  if (photo is String && photo.isNotEmpty) {
                    _vehiclePhotoUrl = photo;
                    _vehiclePhoto = null;
                    _vehiclePhotoBytesWeb = null;
                  }
                });
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _kThemeBlue,
                  foregroundColor: Colors.white,
                ),
                onPressed: () =>
                    Navigator.of(context).pushNamed(Routes.vehicles),
                icon: const Icon(Icons.add),
                label: const Text('Add new vehicle'),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Trip' : 'Post a Trip'),
        backgroundColor: _kThemeBlue,
      ),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _hasAcceptedBookings,
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (_hasAcceptedBookings)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.amber[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber[600]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock, color: Colors.amber[800]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'This trip has accepted bookings and can no longer be edited or canceled.',
                            style: TextStyle(
                                color: Colors.amber[800],
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ---------- NEW: Recent trips dropdown (reuse last 5) ----------
                if (!isEditing && _user != null) ...[
                  Text(
                    'Repeat a previous trip',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Text(
                      'Select one of your last 5 trips to reuse all details. You will still need to choose a new date and time.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.black.withOpacity(0.6),
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    future: FirebaseFirestore.instance
                        .collection('trips')
                        .where('driverId', isEqualTo: _user!.uid)
                        .orderBy('createdAt', descending: true)
                        .limit(5)
                        .get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: LinearProgressIndicator(),
                        );
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(
                            'You have no previous trips yet.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Colors.black.withOpacity(0.6),
                                ),
                          ),
                        );
                      }

                      final docs = snapshot.data!.docs;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            value: _selectedTemplateTripId,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Select a recent trip to reuse',
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            isExpanded: true,
                            items: docs.map((d) {
                              final data = d.data();
                              final origin =
                                  (data['origin'] ?? '') as String? ?? '';
                              final destination =
                                  (data['destination'] ?? '') as String? ?? '';

                              DateTime? dt;
                              final rawDate = data['date'];
                              if (rawDate is Timestamp) {
                                dt = rawDate.toDate();
                              } else if (rawDate is String &&
                                  rawDate.isNotEmpty) {
                                dt = DateTime.tryParse(rawDate);
                              }

                              final dateStr = dt == null
                                  ? '–'
                                  : _dateDisplayFormatter.format(dt);
                              String timeStr =
                                  (data['time'] ?? '') as String? ?? '';
                              if (timeStr.isEmpty && dt != null) {
                                timeStr = DateFormat('h:mm a').format(dt);
                              }

                              final pricePerSeat =
                                  (data['pricePerSeat'] as num?)
                                          ?.toDouble() ??
                                      0.0;
                              final seatsTotal =
                                  (data['seatsTotal'] as int?) ?? 1;
                              final cSym =
                                  (data['currencySymbol'] as String?) ??
                                      _currencySymbol;

                              final label =
                                  '$origin → $destination • $dateStr at $timeStr • $cSym${pricePerSeat.toStringAsFixed(2)}/seat • $seatsTotal seats';

                              return DropdownMenuItem<String>(
                                value: d.id,
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width - 48,
                                  ),
                                  child: Text(
                                    label,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              final doc =
                                  docs.firstWhere((d) => d.id == value);
                              setState(() {
                                _selectedTemplateTripId = value;
                              });
                              _reuseTripFromTemplate(doc);
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],

                Text('Itinerary',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: Text(
                    "Your origin, destination, and stops you're willing to make along the way.",
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.black.withOpacity(.60)),
                  ),
                ),
                const SizedBox(height: 16),

                _Labeled(
                  label: 'Origin',
                  icon: Icons.my_location_outlined,
                  child: _PlacesField(
                    controller: _originCtrl,
                    hintText: 'Start location',
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Please enter an origin.' : null,
                    onChangedForPriceRecompute: () {
                      _recomputeSegmentPrices();
                    },
                    onPlaceSelected: (placeDescription, countryName) {
                      _updateCurrencyFromPlace(
                        placeDescription,
                        countryOverride: countryName,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),

                _Labeled(
                  label: 'Destination',
                  icon: Icons.place_outlined,
                  trailing: IconButton(
                    tooltip: 'Swap',
                    onPressed: _swapOriginDestination,
                    icon: const Icon(Icons.swap_vert),
                  ),
                  child: _PlacesField(
                    controller: _destinationCtrl,
                    hintText: 'End location',
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Please enter a destination.' : null,
                    onChangedForPriceRecompute: _recomputeSegmentPrices,
                    onPlaceSelected: (placeDescription, countryName) {
                      if (_originCtrl.text.isEmpty) {
                        _updateCurrencyFromPlace(
                          placeDescription,
                          countryOverride: countryName,
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),

                ...List.generate(_stops.length, (i) {
                  final stop = _stops[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _Labeled(
                      label: 'Stop ${i + 1}',
                      icon: Icons.location_on_outlined,
                      trailing: IconButton(
                        onPressed: () => _removeStop(i),
                        icon: const Icon(Icons.close),
                        tooltip: 'Remove stop',
                      ),
                      child: _PlacesField(
                        controller: stop.locationCtrl,
                        hintText: 'City or address',
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Please enter a stop location or remove it.'
                            : null,
                        onChangedForPriceRecompute: _recomputeSegmentPrices,
                      ),
                    ),
                  );
                }),

                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E66F5),
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onPressed: _canAddMoreStops ? _addStop : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add stop'),
                  ),
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: _Labeled(
                        label: 'Date',
                        icon: Icons.calendar_today_outlined,
                        child: TextFormField(
                          controller: _dateCtrl,
                          readOnly: true,
                          decoration: InputDecoration(
                            hintText: 'Select date',
                            border: const OutlineInputBorder(),
                            labelText: _getDisplayDate(_dateCtrl.text),
                            floatingLabelBehavior: FloatingLabelBehavior.never,
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Please select a date.' : null,
                          onTap: () => _pickDate(_dateCtrl),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Labeled(
                        label: 'Time',
                        icon: Icons.access_time,
                        child: TextFormField(
                          controller: _timeCtrl,
                          readOnly: true,
                          decoration: InputDecoration(
                            hintText: 'Select time',
                            border: const OutlineInputBorder(),
                            labelText: _getDisplayTime(_timeCtrl.text, context),
                            floatingLabelBehavior: FloatingLabelBehavior.never,
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Please select a time.' : null,
                          onTap: () => _pickTime(_timeCtrl),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Return trip',
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Add return trip'),
                  value: _returnEnabled,
                  onChanged: isEditing ? null : (v) => setState(() => _returnEnabled = v),
                  tileColor: isEditing ? Colors.grey[200] : null,
                ),
                if (_returnEnabled && !isEditing) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _Labeled(
                          label: 'Return date',
                          icon: Icons.calendar_today_outlined,
                          child: TextFormField(
                            controller: _returnDateCtrl,
                            readOnly: true,
                            decoration: InputDecoration(
                              hintText: 'Select date',
                              border: const OutlineInputBorder(),
                              labelText: _getDisplayDate(_returnDateCtrl.text),
                              floatingLabelBehavior: FloatingLabelBehavior.never,
                            ),
                            validator: (v) => _returnEnabled
                                ? ((v == null || v.isEmpty)
                                    ? 'Please select a return date.'
                                    : null)
                                : null,
                            onTap: () => _pickDate(_returnDateCtrl),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Labeled(
                          label: 'Return time',
                          icon: Icons.access_time,
                          child: TextFormField(
                            controller: _returnTimeCtrl,
                            readOnly: true,
                            decoration: InputDecoration(
                              hintText: 'Select time',
                              border: const OutlineInputBorder(),
                              labelText: _getDisplayTime(_returnTimeCtrl.text, context),
                              floatingLabelBehavior: FloatingLabelBehavior.never,
                            ),
                            validator: (v) {
                              if (!_returnEnabled) return null;
                              if (v == null || v.isEmpty) {
                                return 'Please select a return time.';
                              }
                              final out = _composeDeparture();
                              final ret = _composeReturnDeparture();
                              if (out != null && ret != null) {
                                if (ret.isBefore(out.add(const Duration(hours: 1)))) {
                                  return 'Return must be at least 1hr after departure.';
                                }
                              }
                              return null;
                            },
                            onTap: () => _pickTime(_returnTimeCtrl),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (isEditing)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      "Return trips cannot be added or edited after posting. Please post a new trip for the return journey.",
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey[600]),
                    ),
                  ),

                const SizedBox(height: 16),

                _Labeled(
                  label: 'Seats',
                  icon: Icons.event_seat_outlined,
                  child: _SeatsStepperField(
                    initialValue: _seats,
                    onChanged: (v) => setState(() => _seats = v),
                  ),
                ),

                const SizedBox(height: 16),

                // Currency indicator
                Row(
                  children: [
                    const Icon(Icons.payments_outlined, size: 18, color: _kThemeBlue),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Currency: $_currencySymbol $_currencyCode'
                        '${_currencyName.isNotEmpty ? ' ($_currencyName)' : ''}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.black.withOpacity(0.8),
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                _Labeled(
                  label: 'Trip price (per seat)',
                  icon: Icons.attach_money,
                  child: TextFormField(
                    controller: _tripPriceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      prefixText: '$_currencySymbol ',
                      hintText: 'e.g. 25',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        _hasAnySegmentPricesFilled ? _optPosNumber(v) : _reqPosNumber(v),
                  ),
                ),

                const SizedBox(height: 12),

                if (_currentSegmentTitles.isNotEmpty) ...[
                  Row(
                    children: const [
                      Icon(Icons.tune, size: 18, color: _kThemeBlue),
                      SizedBox(width: 8),
                      Text('Edit Price for each stop',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: _kThemeBlue)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Text(
                      'Set prices for all possible point-to-point segments.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.black.withOpacity(.6)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._currentSegmentTitles.map((title) {
                    final ctrl = _segmentPriceCtrls[title]!;
                    final recommended =
                        20 + (_currentSegmentTitles.indexOf(title) * 5);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            'Recommended: $_currencySymbol$recommended or less per seat',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Colors.black.withOpacity(0.6)),
                          ),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: ctrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              prefixText: '$_currencySymbol ',
                              hintText: 'e.g. 20',
                              border: const OutlineInputBorder(),
                              fillColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceVariant,
                              filled: true,
                            ),
                            validator: _reqPosNumber,
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('All segment prices are required when set.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.black.withOpacity(.6))),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),

                _Labeled(
                  label: 'Extra luggage price (per item)',
                  icon: Icons.luggage_outlined,
                  child: TextFormField(
                    controller: _extraLuggagePriceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      hintText: 'e.g. 5 (optional)',
                      border: OutlineInputBorder(),
                    ),
                    validator: _optPosNumber,
                  ),
                ),

                const SizedBox(height: 16),

                _Labeled(
                  label: 'Premium seat extra charge (optional)',
                  icon: Icons.event_seat,
                  child: TextFormField(
                    controller: _premiumExtraCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      hintText: 'e.g. 10',
                      border: OutlineInputBorder(),
                    ),
                    validator: _optPosNumber,
                  ),
                ),

                const SizedBox(height: 16),

                Text('Trip preferences',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),

                Text('Luggage', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill('No luggage', _luggageSize == 'N',
                        () => setState(() => _luggageSize = 'N'),
                        Icons.work_outline),
                    _pill('S', _luggageSize == 'S',
                        () => setState(() => _luggageSize = 'S'),
                        Icons.work_outline),
                    _pill('M', _luggageSize == 'M',
                        () => setState(() => _luggageSize = 'M'), Icons.work),
                    _pill('L', _luggageSize == 'L',
                        () => setState(() => _luggageSize = 'L'),
                        Icons.business_center),
                  ],
                ),
                const SizedBox(height: 12),

                Text('Back row seating',
                    style: Theme.of(context).textTheme.titleSmall),
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: Text(
                    'Pledge to a maximum of 2 people in the back for better reviews',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.black.withOpacity(0.6)),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _pill('Max 2 people', _backRow == 2,
                        () => setState(() => _backRow = 2),
                        Icons.airline_seat_recline_extra),
                    _pill('3 people', _backRow == 3,
                        () => setState(() => _backRow = 3), Icons.chair),
                  ],
                ),
                const SizedBox(height: 12),

                Text('Other', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chipToggle('Winter tires', _otherWinter,
                        (v) => setState(() => _otherWinter = v), Icons.ac_unit),
                    _chipToggle('Bikes', _otherBikes,
                        (v) => setState(() => _otherBikes = v),
                        Icons.directions_bike),
                    _chipToggle(
                        'Skis & snowboards',
                        _otherSkis,
                        (v) => setState(() => _otherSkis = v),
                        Icons.ac_unit_outlined),
                    _chipToggle('Pets', _otherPets,
                        (v) => setState(() => _otherPets = v), Icons.pets),
                  ],
                ),

                const SizedBox(height: 16),

                _Labeled(
                  label: 'Description',
                  icon: Icons.notes_outlined,
                  child: TextFormField(
                    controller: _descCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Anything riders should know?',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Saved vehicles + add button
                _buildSavedVehiclePicker(),
                const SizedBox(height: 12),

                _VehicleDetailsSection(
                  companyCtrl: _companyCtrl,
                  modelCtrl: _modelCtrl,
                  yearCtrl: _yearCtrl,
                  colorCtrl: _colorCtrl,
                  plateCtrl: _plateCtrl,
                  vehiclePhoto: _vehiclePhoto,
                  vehiclePhotoBytesWeb: _vehiclePhotoBytesWeb,
                  vehiclePhotoUrl: _vehiclePhotoUrl,
                  uploadProgress: _uploadProgress,
                  onPickImage: _pickImageMobile,
                ),

                const SizedBox(height: 24),

                Text('Rules when posting a trip',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(
                            fontWeight: FontWeight.w700, color: Colors.black)),
                const SizedBox(height: 16),
                _buildRuleItem(
                  icon: Icons.access_time_filled,
                  title: 'Be reliable',
                  subtitle:
                      'Only post a trip if you\'re sure you\'re driving and show up on time.',
                ),
                _buildRuleItem(
                  icon: Icons.phone_android,
                  title: 'No cash',
                  subtitle:
                      'All passengers pay online and you receive a payout after the trip.',
                ),
                _buildRuleItem(
                  icon: Icons.warning_amber,
                  title: 'Drive safely',
                  subtitle:
                      'Stick to the speed limit and do not use your phone while driving.',
                ),

                const SizedBox(height: 8),

                FormField<bool>(
                  initialValue: _agreeRules,
                  validator: (v) =>
                      v == true ? null : 'You must agree to the rules to post.',
                  builder: (state) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 24,
                              width: 24,
                              child: Checkbox(
                                value: _agreeRules,
                                activeColor: state.hasError
                                    ? Theme.of(context).colorScheme.error
                                    : _kThemeBlue,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onChanged: (v) {
                                  setState(() => _agreeRules = v ?? false);
                                  state.didChange(v);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: Colors.black),
                                  children: [
                                    const TextSpan(
                                        text: 'I agree to these rules, to the '),
                                    TextSpan(
                                      text: 'Driver Cancellation Policy',
                                      style: const TextStyle(
                                        decoration: TextDecoration.underline,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black,
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () => _launchUrl(
                                            'https://doraride.com/driver-cancellation-policy.html'),
                                    ),
                                    const TextSpan(text: ', '),
                                    TextSpan(
                                      text: 'Terms of Service',
                                      style: const TextStyle(
                                        decoration: TextDecoration.underline,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black,
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () => _launchUrl(
                                            'https://doraride.com/terms-and-conditions.html'),
                                    ),
                                    const TextSpan(text: ' and the '),
                                    TextSpan(
                                      text: 'Privacy Policy',
                                      style: const TextStyle(
                                        decoration: TextDecoration.underline,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black,
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () => _launchUrl(
                                            'https://doraride.com/privacy-policy.html'),
                                    ),
                                    const TextSpan(
                                      text:
                                          ', and I understand that my account could be suspended if I break the rules.',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (state.hasError)
                          Padding(
                            padding:
                                const EdgeInsets.only(left: 12.0, top: 4.0),
                            child: Text(
                              state.errorText ?? '',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 12),
                            ),
                          ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 8),
                // DELETE / CANCEL TRIP BUTTON (Only when editing and no accepted bookings)
                if (isEditing && !_hasAcceptedBookings) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _deletePost,
                      child: const Text('Cancel / Delete Trip'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _hasAcceptedBookings ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor:
                          _hasAcceptedBookings ? Colors.grey : _kThemeBlue,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(isEditing ? 'Save Changes' : 'Post trip'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRuleItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor:
                Theme.of(context).colorScheme.primary.withOpacity(0.1),
            child: Icon(icon, color: _kThemeBlue),
          ),
          const SizedBox(height: 12),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(
                      fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.black.withOpacity(0.7))),
        ],
      ),
    );
  }

  // ---------------- VEHICLE PHOTO: pick + upload ----------------

  Future<void> _pickImageMobile(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    setState(() {
      _vehiclePhoto = File(picked.path);
      _vehiclePhotoBytesWeb = null;
    });

    await _uploadVehiclePhoto(
      file: _vehiclePhoto,
      fileNameHint: picked.name,
    );
  }

  Future<void> _uploadVehiclePhoto({
    File? file,
    Uint8List? webBytes,
    String? fileNameHint,
  }) async {
    try {
      await _ensureSignedIn();
      final uid = _user?.uid;
      if (uid == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not signed in — cannot upload.')),
        );
        return;
      }

      final plateRaw = _plateCtrl.text.trim();
      final safePlate = plateRaw.isEmpty ? null : plateRaw.toUpperCase().replaceAll('/', '-');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = (fileNameHint != null && fileNameHint.contains('.'))
          ? fileNameHint.split('.').last
          : 'jpg';

      final path = safePlate != null
          ? 'vehicles/$uid/$safePlate/car_$ts.$ext'
          : 'user_uploads/$uid/car_$ts.$ext';

      final ref = FirebaseStorage.instance.ref().child(path);
      UploadTask task;
      if (file != null) {
        task = ref.putFile(file, SettableMetadata(contentType: 'image/$ext'));
      } else {
        return;
      }

      task.snapshotEvents.listen((s) {
        if (s.totalBytes > 0) {
          setState(() => _uploadProgress = s.bytesTransferred / s.totalBytes);
        }
      });

      final snap = await task;
      final url = await snap.ref.getDownloadURL();

      setState(() {
        _vehiclePhotoUrl = url;
        _uploadProgress = null;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle photo uploaded.')),
      );

      await _pushPhotoUrlToLiveIfEditing();
    } catch (e) {
      setState(() => _uploadProgress = null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image upload failed: $e')),
      );
    }
  }

  String? _reqPosNumber(String? v) {
    if (v == null || v.trim().isEmpty) return 'Price is required.';
    final n = double.tryParse(v);
    if (n == null || n <= 0) return 'Enter a valid price.';
    return null;
  }

  String? _optPosNumber(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = double.tryParse(v);
    if (n == null || n < 0) return 'Enter a valid amount.';
    return null;
  }
}

// ----- small shared UI bits -----

class _Labeled extends StatelessWidget {
  final String label;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  const _Labeled({
    required this.label,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle =
        Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(label, style: labelStyle),
            const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _SeatsStepperField extends StatefulWidget {
  final int initialValue;
  final ValueChanged<int> onChanged;
  const _SeatsStepperField({super.key, required this.initialValue, required this.onChanged});
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
    if (n != null && n >= _minSeats && n <= _maxSeats && n != widget.initialValue) {
      widget.onChanged(n);
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
            onPressed:
                currentValue > _minSeats ? () => _updateValue(currentValue - 1) : null,
            icon: Icon(Icons.remove,
                color: currentValue > _minSeats ? _kThemeBlue : Colors.grey),
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
                if (v == null || v.isEmpty) return 'Seat count is required.';
                if (n == null || n < _minSeats) return 'Minimum 1 seat required.';
                if (n > _maxSeats) return 'Maximum $_maxSeats seats allowed here.';
                return null;
              },
            ),
          ),
          IconButton(
            onPressed:
                currentValue < _maxSeats ? () => _updateValue(currentValue + 1) : null,
            icon: Icon(Icons.add,
                color: currentValue < _maxSeats ? _kThemeBlue : Colors.grey),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }
}

// Vehicle details section
class _VehicleDetailsSection extends StatelessWidget {
  final TextEditingController companyCtrl;
  final TextEditingController modelCtrl;
  final TextEditingController yearCtrl;
  final TextEditingController colorCtrl;
  final TextEditingController plateCtrl;
  final File? vehiclePhoto;
  final Uint8List? vehiclePhotoBytesWeb;
  final String? vehiclePhotoUrl;
  final double? uploadProgress;
  final Function(ImageSource) onPickImage;

  const _VehicleDetailsSection({
    required this.companyCtrl,
    required this.modelCtrl,
    required this.yearCtrl,
    required this.colorCtrl,
    required this.plateCtrl,
    this.vehiclePhoto,
    this.vehiclePhotoBytesWeb,
    this.vehiclePhotoUrl,
    this.uploadProgress,
    required this.onPickImage,
  });

  Widget _iconField({
    required IconData icon,
    required String hint,
    required TextEditingController controller,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      validator: validator,
    );
  }

  String? _yearValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Year is required.';
    final year = int.tryParse(v);
    final now = DateTime.now().year;
    if (year == null || year < 1900 || year > now + 1) {
      return 'Enter a valid year (e.g., $now)';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    ImageProvider? preview;
    if (vehiclePhoto != null) {
      preview = FileImage(vehiclePhoto!);
    } else if (vehiclePhotoBytesWeb != null) {
      preview = MemoryImage(vehiclePhotoBytesWeb!);
    } else if (vehiclePhotoUrl != null && vehiclePhotoUrl!.isNotEmpty) {
      preview = NetworkImage(vehiclePhotoUrl!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Vehicle details',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _iconField(
                icon: Icons.directions_car_outlined,
                hint: 'Company name',
                controller: companyCtrl,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter the company name.'
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _iconField(
                icon: Icons.directions_car_filled_outlined,
                hint: 'e.g. Toyota Corolla',
                controller: modelCtrl,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter the vehicle model.'
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _iconField(
                icon: Icons.calendar_today_outlined,
                hint: 'Year',
                controller: yearCtrl,
                keyboardType: TextInputType.number,
                validator: _yearValidator,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _iconField(
                icon: Icons.color_lens_outlined,
                hint: 'Color',
                controller: colorCtrl,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter the vehicle color.'
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _iconField(
          icon: Icons.confirmation_number_outlined,
          hint: 'Plate',
          controller: plateCtrl,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Please enter the license plate.' : null,
        ),
        const SizedBox(height: 12),
        _Labeled(
          label: 'Vehicle photo',
          icon: Icons.photo_camera_outlined,
          child: Column(
            children: [
              GestureDetector(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (_) => _ImagePickerDialog(
                      onCameraTap: () {
                        onPickImage(ImageSource.camera);
                        Navigator.pop(context);
                      },
                      onGalleryTap: () {
                        onPickImage(ImageSource.gallery);
                        Navigator.pop(context);
                      },
                    ),
                  );
                },
                child: Container(
                  height: 160,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    image: preview != null
                        ? DecorationImage(image: preview, fit: BoxFit.cover)
                        : null,
                  ),
                  child: preview == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.add_a_photo_outlined, size: 28),
                            SizedBox(height: 8),
                            Text('Add vehicle photo'),
                          ],
                        )
                      : null,
                ),
              ),
              if (uploadProgress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: uploadProgress),
                const SizedBox(height: 4),
                Text(
                  'Uploading ${((uploadProgress! * 100).clamp(0, 100)).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ImagePickerDialog extends StatelessWidget {
  final VoidCallback onCameraTap;
  final VoidCallback onGalleryTap;
  const _ImagePickerDialog({
    required this.onCameraTap,
    required this.onGalleryTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Choose from Library'),
            onTap: onGalleryTap),
        ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Take Photo'),
            onTap: onCameraTap),
      ]),
    );
  }
}

// Small chips
Widget _pill(String text, bool selected, VoidCallback onTap, IconData icon) {
  final style = selected
      ? const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)
      : const TextStyle(color: Colors.black, fontWeight: FontWeight.w600);
  return RawChip(
    label: Text(text, style: style),
    avatar: Icon(icon, size: 18, color: selected ? Colors.white : Colors.black),
    selected: selected,
    onPressed: onTap,
    backgroundColor: Colors.white,
    selectedColor: _kThemeBlue,
    checkmarkColor: Colors.white,
    shape: StadiumBorder(
      side: BorderSide(
        color: selected ? _kThemeBlue : Colors.black.withOpacity(0.3),
      ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    labelPadding: const EdgeInsets.only(right: 6),
  );
}

Widget _chipToggle(
    String text, bool value, ValueChanged<bool> onChanged, IconData icon) {
  final color = value ? _kThemeBlue : Colors.black;
  return RawChip(
    label: Text(text),
    avatar: Icon(icon, size: 18, color: color),
    selected: value,
    onSelected: onChanged,
    backgroundColor: Colors.white,
    selectedColor: Colors.white,
    labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
    shape: StadiumBorder(
      side: BorderSide(
          color: value ? _kThemeBlue : Colors.black.withOpacity(0.3)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    labelPadding: const EdgeInsets.only(right: 6),
    showCheckmark: false,
  );
}