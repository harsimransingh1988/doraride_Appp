// lib/common/widgets/location_autocomplete_field.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class LocationResult {
  final String placeId;
  final String primaryText;
  final String secondaryText;
  final double? lat;
  final double? lng;

  LocationResult({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
    this.lat,
    this.lng,
  });
}

class LocationAutocompleteField extends StatefulWidget {
  final String apiKey;                // Google *Browser/Server* API key with Places enabled
  final String hintText;
  final void Function(LocationResult result) onSelected;
  final String? countryFilter;        // e.g. 'ca' or null
  final String language;              // e.g. 'en'
  final bool citiesOnly;              // if true, restricts to cities via types='(cities)'
  final int minChars;                 // when to start querying (default 3)

  const LocationAutocompleteField({
    super.key,
    required this.apiKey,
    required this.hintText,
    required this.onSelected,
    this.countryFilter,
    this.language = 'en',
    this.citiesOnly = true,
    this.minChars = 3,
  });

  @override
  State<LocationAutocompleteField> createState() => _LocationAutocompleteFieldState();
}

class _LocationAutocompleteFieldState extends State<LocationAutocompleteField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _debouncer = _Debouncer(const Duration(milliseconds: 300));
  final _uuid = const Uuid();

  OverlayEntry? _overlayEntry;
  List<LocationResult> _suggestions = [];
  String _sessionToken = '';
  int _reqSerial = 0;  // guards against out-of-order responses
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _newSession();
    _controller.addListener(_onChanged);
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _newSession() => _sessionToken = _uuid.v4();

  void _onFocus() {
    if (!_focus.hasFocus) {
      _removeOverlay();
    } else if (_suggestions.isNotEmpty) {
      _showOverlay();
    }
  }

  void _onChanged() {
    final text = _controller.text.trim();
    if (text.length < widget.minChars) {
      setState(() {
        _suggestions = [];
        _error = null;
        _loading = false;
      });
      _removeOverlay();
      return;
    }
    _debouncer(() => _fetchSuggestions(text));
  }

  Future<void> _fetchSuggestions(String input) async {
    final mySerial = ++_reqSerial;
    setState(() {
      _loading = true;
      _error = null;
    });

    final params = <String, String>{
      'input': input,
      'key': widget.apiKey,
      'sessiontoken': _sessionToken,
      'language': widget.language,
      if (widget.citiesOnly) 'types': '(cities)', // city bias
      if (widget.countryFilter != null) 'components': 'country:${widget.countryFilter}',
    };

    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', params);

    try {
      final res = await http.get(uri);
      if (!mounted) return;
      if (mySerial != _reqSerial) return; // a newer request is in-flight

      if (res.statusCode != 200) {
        _handleError('Network error (${res.statusCode})');
        return;
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final status = (data['status'] as String?) ?? 'UNKNOWN_ERROR';

      if (status == 'OK' || status == 'ZERO_RESULTS') {
        final preds = (data['predictions'] as List).cast<Map<String, dynamic>>();
        final items = preds.map((p) {
          final sf = (p['structured_formatting'] as Map?) ?? const {};
          return LocationResult(
            placeId: p['place_id'] as String,
            primaryText: (sf['main_text'] as String?) ?? (p['description'] as String? ?? ''),
            secondaryText: (sf['secondary_text'] as String?) ?? '',
          );
        }).toList();

        setState(() {
          _suggestions = items;
          _loading = false;
          _error = null;
        });

        if (items.isEmpty) {
          _removeOverlay();
        } else {
          _showOverlay();
        }
      } else {
        final msg = (data['error_message'] as String?) ?? status;
        _handleError('Autocomplete failed: $msg');
      }
    } catch (e) {
      if (!mounted || mySerial != _reqSerial) return;
      _handleError('Request error: $e');
    }
  }

  Future<LocationResult?> _fetchDetails(LocationResult base) async {
    final mySerial = ++_reqSerial; // block older responses
    setState(() {
      _loading = true;
      _error = null;
    });

    final params = <String, String>{
      'place_id': base.placeId,
      'key': widget.apiKey,
      'sessiontoken': _sessionToken,
      'language': widget.language,
      'fields': 'name,formatted_address,geometry',
    };

    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', params);

    try {
      final res = await http.get(uri);
      if (!mounted) return null;
      if (mySerial != _reqSerial) return null;

      if (res.statusCode != 200) {
        _handleError('Network error (${res.statusCode})');
        return null;
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final status = (data['status'] as String?) ?? 'UNKNOWN_ERROR';
      if (status != 'OK') {
        final msg = (data['error_message'] as String?) ?? status;
        _handleError('Details failed: $msg');
        return null;
      }

      final result = (data['result'] as Map<String, dynamic>);
      final loc = (result['geometry'] as Map?)?['location'] as Map?;
      final finalized = LocationResult(
        placeId: base.placeId,
        primaryText: (result['name'] as String?) ?? base.primaryText,
        secondaryText: (result['formatted_address'] as String?) ?? base.secondaryText,
        lat: (loc?['lat'] as num?)?.toDouble(),
        lng: (loc?['lng'] as num?)?.toDouble(),
      );

      setState(() {
        _loading = false;
        _error = null;
      });
      return finalized;
    } catch (e) {
      if (!mounted || mySerial != _reqSerial) return null;
      _handleError('Details error: $e');
      return null;
    }
  }

  void _handleError(String msg) {
    setState(() {
      _loading = false;
      _error = msg;
      _suggestions = [];
    });
    _removeOverlay();
  }

  void _showOverlay() {
    _removeOverlay();
    final rb = context.findRenderObject() as RenderBox?;
    if (rb == null) return;

    final size = rb.size;
    final offset = rb.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // tap-outside to close
          Positioned.fill(
            child: GestureDetector(onTap: _removeOverlay, behavior: HitTestBehavior.opaque),
          ),
          Positioned(
            left: offset.dx,
            top: offset.dy + size.height + 4,
            width: size.width,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: _suggestions.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final s = _suggestions[i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_outlined),
                            title: Text(s.primaryText),
                            subtitle:
                                s.secondaryText.isNotEmpty ? Text(s.secondaryText) : null,
                            onTap: () async {
                              _removeOverlay();
                              final details = await _fetchDetails(s);
                              if (details != null) {
                                _controller.text = details.primaryText;
                                _newSession(); // ✅ new session after selection
                                widget.onSelected(details);
                              }
                            },
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _loading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : (_controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _controller.clear();
                      setState(() {
                        _suggestions = [];
                        _error = null;
                      });
                      _removeOverlay();
                    },
                  )
                : null),
        errorText: _error,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: true,
      ),
      textInputAction: TextInputAction.next,
    );
  }
}

class _Debouncer {
  final Duration delay;
  Timer? _t;
  _Debouncer(this.delay);
  void call(void Function() f) {
    _t?.cancel();
    _t = Timer(delay, f);
  }
}
