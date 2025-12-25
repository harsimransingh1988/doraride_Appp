// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Your **Browser** key (HTTP referrers restriction) with:
/// - Places API (New)  **ENABLED**
/// - Maps JavaScript API **ENABLED**  (the map on this page)
///
/// IMPORTANT (Web): in Google Cloud Console → Credentials → your key:
///   Application restrictions:  HTTP referrers (web sites)
///   Add:
///     https://test.doraride.com/*
///     https://doraride.com/*
///     http://localhost:*/*   (for local dev)
///
/// If suggestions still don't appear:
///   - Make sure billing is enabled
///   - You enabled "Places API (New)" (not only legacy)
///   - The referrer matches exactly your origin (scheme + host + port)
const String kPlacesWebApiKey = 'YOUR_BROWSER_PLACES_API_KEY';

class LocationSearchPage extends StatefulWidget {
  const LocationSearchPage({super.key});
  @override
  State<LocationSearchPage> createState() => _LocationSearchPageState();
}

class _LocationSearchPageState extends State<LocationSearchPage> {
  // Text controllers + focus + overlay links
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();

  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();

  final _fromLink = LayerLink();
  final _toLink = LayerLink();

  OverlayEntry? _fromOverlay;
  OverlayEntry? _toOverlay;

  Timer? _debounce;

  // Predictions
  List<_Prediction> _fromPreds = [];
  List<_Prediction> _toPreds = [];

  // Selected results (after details resolve)
  _ResolvedPlace? _fromResolved;
  _ResolvedPlace? _toResolved;

  // Country bias / location bias (optional)
  String? _country; // null = worldwide; e.g., 'CA', 'US'

  @override
  void initState() {
    super.initState();

    // Debounce typing
    _fromCtrl.addListener(() => _debounced(() => _fetchPreds(isFrom: true)));
    _toCtrl.addListener(() => _debounced(() => _fetchPreds(isFrom: false)));

    // manage overlays on focus change
    _fromFocus.addListener(() {
      if (!_fromFocus.hasFocus) _removeFromOverlay();
      if (_fromFocus.hasFocus && _fromPreds.isNotEmpty) _showFromOverlay();
    });
    _toFocus.addListener(() {
      if (!_toFocus.hasFocus) _removeToOverlay();
      if (_toFocus.hasFocus && _toPreds.isNotEmpty) _showToOverlay();
    });
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

  // ------------------ Places REST ------------------

  Future<void> _fetchPreds({required bool isFrom}) async {
    final text = (isFrom ? _fromCtrl.text : _toCtrl.text).trim();
    if (text.isEmpty) {
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

    final uri = Uri.https(
      'places.googleapis.com',
      '/v1/places:autocomplete',
      {
        'input': text,
        'languageCode': 'en',
        // City-only suggestions and worldwide are handled via includeTypes & no region.
        // You can loosen to general places by removing includeTypes.
        'includeQueryPredictions': 'false',
      },
    );

    final headers = {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': kPlacesWebApiKey,
      'X-Goog-FieldMask':
          'suggestions.placePrediction.placeId,suggestions.placePrediction.text,suggestions.placePrediction.structuredFormat',
    };

    // You can nudge to cities-only by adding structured filters.
    // The v1 API supports 'typesFilter' via request body (not query).
    final body = jsonEncode({
      'input': text,
      if (_country != null) 'locationBias': {'rectangle': _countryRect(_country!)},
      // Limit to locality + admin areas to get city-like suggestions:
      'includeQueryPredictions': false,
      'typesFilter': [
        'locality', // cities/towns
        'administrative_area_level_1',
        'administrative_area_level_2',
      ],
    });

    try {
      final res = await http.post(uri, headers: headers, body: body);
      if (res.statusCode != 200) {
        // Swallow to avoid UX break
        return;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = (data['suggestions'] as List<dynamic>? ?? []);
      final preds = raw
          .map((e) => _Prediction.fromJson(e as Map<String, dynamic>))
          .where((p) => p.placeId.isNotEmpty && p.description.isNotEmpty)
          .toList();

      setState(() {
        if (isFrom) {
          _fromPreds = preds;
          if (_fromFocus.hasFocus && preds.isNotEmpty) _showFromOverlay();
        } else {
          _toPreds = preds;
          if (_toFocus.hasFocus && preds.isNotEmpty) _showToOverlay();
        }
      });
    } catch (_) {
      // ignore network errors for UX
    }
  }

  Future<_ResolvedPlace?> _resolvePlace(String placeId, String label) async {
    final uri = Uri.https(
      'places.googleapis.com',
      '/v1/places/$placeId',
      {'languageCode': 'en'},
    );

    final headers = {
      'X-Goog-Api-Key': kPlacesWebApiKey,
      'X-Goog-FieldMask': 'id,displayName,formattedAddress,location',
    };

    final res = await http.get(uri, headers: headers);
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final loc = (data['location'] ?? {}) as Map<String, dynamic>;
    final lat = (loc['latitude'] as num?)?.toDouble();
    final lng = (loc['longitude'] as num?)?.toDouble();

    return _ResolvedPlace(
      description: label,
      placeId: placeId,
      lat: lat,
      lng: lng,
    );
  }

  // ------------------ Overlays ------------------

  void _showFromOverlay() {
    _fromOverlay?.remove();
    _fromOverlay = _buildOverlay(
      link: _fromLink,
      preds: _fromPreds,
      onTap: (p) async {
        final resolved = await _resolvePlace(p.placeId, p.description);
        if (resolved == null) return;
        setState(() {
          _fromResolved = resolved;
          _fromCtrl.text = resolved.description;
          _fromPreds = [];
        });
        _removeFromOverlay();
        _fromFocus.unfocus();
      },
    );
    Overlay.of(context).insert(_fromOverlay!);
  }

  void _showToOverlay() {
    _toOverlay?.remove();
    _toOverlay = _buildOverlay(
      link: _toLink,
      preds: _toPreds,
      onTap: (p) async {
        final resolved = await _resolvePlace(p.placeId, p.description);
        if (resolved == null) return;
        setState(() {
          _toResolved = resolved;
          _toCtrl.text = resolved.description;
          _toPreds = [];
        });
        _removeToOverlay();
        _toFocus.unfocus();
      },
    );
    Overlay.of(context).insert(_toOverlay!);
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
    required List<_Prediction> preds,
    required void Function(_Prediction) onTap,
  }) {
    final width = MediaQuery.of(context).size.width - 24; // page padding 12+12
    return OverlayEntry(
      builder: (_) => Positioned(
        width: width,
        left: 12,
        child: CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          offset: const Offset(0, 52),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: preds.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = preds[i];
                  return ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(p.description),
                    onTap: () => onTap(p),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _debounced(void Function() f) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), f);
  }

  bool get _ready => _fromResolved != null && _toResolved != null;

  // Optional: simple country rectangles for location biasing (keeps API happy)
  Map<String, dynamic> _countryRect(String cc) {
    // These are generous bounding boxes—good enough for biasing.
    switch (cc.toUpperCase()) {
      case 'CA':
        return {
          'low': {'latitude': 41.67, 'longitude': -141.00},
          'high': {'latitude': 83.11, 'longitude': -52.62},
        };
      case 'US':
        return {
          'low': {'latitude': 24.52, 'longitude': -124.77},
          'high': {'latitude': 49.38, 'longitude': -66.95},
        };
      default:
        // World (rough): no bias, but API requires a rectangle if you pass locationBias.
        return {
          'low': {'latitude': -60.0, 'longitude': -179.9},
          'high': {'latitude': 85.0, 'longitude': 179.9},
        };
    }
  }

  // ------------------ UI ------------------

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF279C56);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: green,
        foregroundColor: Colors.white,
        title: const Text('Search locations'),
      ),
      body: Stack(
        children: [
          // Simple colored background "map" placeholder so this file stays standalone.
          // If you already mount GoogleMap elsewhere, you can plug it in here.
          Container(color: const Color(0xFFE8F5E9)),
          ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            children: [
              _CountryRow(
                value: _country,
                onChanged: (v) => setState(() => _country = v),
              ),
              const SizedBox(height: 8),

              // FROM
              CompositedTransformTarget(
                link: _fromLink,
                child: TextField(
                  controller: _fromCtrl,
                  focusNode: _fromFocus,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _fromCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _fromCtrl.clear();
                                _fromResolved = null;
                                _fromPreds = [];
                              });
                              _removeFromOverlay();
                            },
                          ),
                    labelText: 'From',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                  ),
                  onTap: () {
                    if (_fromPreds.isNotEmpty) _showFromOverlay();
                  },
                ),
              ),
              const SizedBox(height: 12),

              // TO
              CompositedTransformTarget(
                link: _toLink,
                child: TextField(
                  controller: _toCtrl,
                  focusNode: _toFocus,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _toCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _toCtrl.clear();
                                _toResolved = null;
                                _toPreds = [];
                              });
                              _removeToOverlay();
                            },
                          ),
                    labelText: 'To',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    filled: true,
                  ),
                  onTap: () {
                    if (_toPreds.isNotEmpty) _showToOverlay();
                  },
                ),
              ),
              const SizedBox(height: 18),

              // Swap
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    final a = _fromCtrl.text;
                    _fromCtrl.text = _toCtrl.text;
                    _toCtrl.text = a;
                    final r = _fromResolved;
                    _fromResolved = _toResolved;
                    _toResolved = r;
                    setState(() {});
                  },
                  icon: const Icon(Icons.swap_vert),
                  label: const Text('Swap'),
                ),
              ),
            ],
          ),

          // Bottom button
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _ready
                    ? () {
                        Navigator.of(context).pop({
                          'from': _fromResolved!.toJson(),
                          'to': _toResolved!.toJson(),
                        });
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                ),
                child: const Text('Use these locations'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------ Small UI helpers ------------------

class _CountryRow extends StatelessWidget {
  final String? value; // null = worldwide
  final ValueChanged<String?> onChanged;
  const _CountryRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.public, color: Colors.black54),
        const SizedBox(width: 10),
        const Text('Country:', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        DropdownButton<String?>(
          value: value,
          items: const [
            DropdownMenuItem(value: null, child: Text('Worldwide')),
            DropdownMenuItem(value: 'CA', child: Text('Canada')),
            DropdownMenuItem(value: 'US', child: Text('United States')),
          ],
          onChanged: onChanged,
        ),
        const Spacer(),
        const Text('City-only', style: TextStyle(color: Colors.black54)),
      ],
    );
  }
}

// ------------------ Models ------------------

class _Prediction {
  final String placeId;
  final String description;
  _Prediction({required this.placeId, required this.description});

  factory _Prediction.fromJson(Map<String, dynamic> json) {
    final p = (json['placePrediction'] ?? {}) as Map<String, dynamic>;
    final tf = (p['text'] ?? {}) as Map<String, dynamic>;
    final desc = (tf['text'] ?? '') as String? ?? '';
    return _Prediction(
      placeId: (p['placeId'] ?? '') as String? ?? '',
      description: desc,
    );
  }
}

class _ResolvedPlace {
  final String description;
  final String placeId;
  final double? lat;
  final double? lng;

  const _ResolvedPlace({
    required this.description,
    required this.placeId,
    required this.lat,
    required this.lng,
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        'placeId': placeId,
        'lat': lat,
        'lng': lng,
      };
}
