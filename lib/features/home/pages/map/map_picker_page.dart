// lib/features/home/pages/map/map_picker_page.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

// Use your existing config and JS geocoder (web)
import 'package:doraride_appp/common/config/maps_config.dart';
import 'package:doraride_appp/common/web/js_geocoder.dart' as jsgeo;

// Native HTTP geocoder for non-web; dummy on web via conditional import
import 'native_geocoder.dart'
    if (dart.library.html) 'dummy_geocoder.dart' as nativegeo;

class MapPickerPage extends StatefulWidget {
  final String initialQuery;

  const MapPickerPage({super.key, this.initialQuery = ''});

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  static const CameraPosition _defaultPosition = CameraPosition(
    target: LatLng(43.6532, -79.3832), // Toronto fallback
    zoom: 12,
  );

  GoogleMapController? _mapController;
  LatLng _cameraPosition = _defaultPosition.target;
  LatLng? _selectedLocation;

  String _selectedAddress = '';
  bool _isLoading = true;
  bool _isGeocoding = false;

  // Debounce for camera idle geocode
  Timer? _idleDebounce;
  static const _idleDebounceMs = 350;

  // Simple retry
  int _retryCount = 0;
  final int _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  @override
  void dispose() {
    _idleDebounce?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initializeLocation() async {
    Position? position;
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (enabled) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm != LocationPermission.denied &&
            perm != LocationPermission.deniedForever) {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
          );
        }
      }
    } catch (_) {
      // ignore and use fallback
    }

    if (!mounted) return;

    final start = (position != null)
        ? LatLng(position.latitude, position.longitude)
        : _defaultPosition.target;

    setState(() {
      _isLoading = false;
      _cameraPosition = start;
      _selectedLocation = start;
    });

    _moveToLocation(start);
    // kick one geocode
    unawaited(_reverseGeocode(start));
  }

  Future<void> _reverseGeocode(LatLng location) async {
    if (!mounted || _isGeocoding) return;

    setState(() {
      _isGeocoding = true;
      _selectedLocation = location;
      _selectedAddress = 'Loading address...';
    });

    try {
      String formatted;

      if (kIsWeb) {
        // Web: use JS Geocoder (no Places radius involved)
        formatted = await jsgeo.reverseGeocodeWithJs(
          location.latitude,
          location.longitude,
        );
      } else {
        // Native platforms: use HTTP Geocoding API (make sure Geocoding API is enabled)
        formatted = await nativegeo.reverseGeocodeNative(
          location.latitude,
          location.longitude,
        );
      }

      // If failed and we have retries left, try again once
      final failed = formatted.contains('failed') ||
          formatted.contains('error') ||
          formatted.contains('timeout') ||
          formatted.contains('not available') ||
          formatted.contains('Network error');

      if (failed && _retryCount < _maxRetries) {
        _retryCount++;
        await Future.delayed(const Duration(milliseconds: 500));
        if (kIsWeb) {
          formatted = await jsgeo.reverseGeocodeWithJs(
            location.latitude,
            location.longitude,
          );
        } else {
          formatted = await nativegeo.reverseGeocodeNative(
            location.latitude,
            location.longitude,
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _selectedAddress = failed ? _generateFallbackAddress(location) : formatted;
        _isGeocoding = false;
        _retryCount = 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _selectedAddress = _generateFallbackAddress(location);
        _isGeocoding = false;
      });
    }
  }

  String _generateFallbackAddress(LatLng location) {
    return 'Location selected\n'
        'Coordinates: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}\n'
        '(Address details unavailable)';
  }

  void _moveToLocation(LatLng location) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(location, 15),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (_selectedLocation != null) {
      _moveToLocation(_selectedLocation!);
    }
  }

  void _onCameraMove(CameraPosition position) {
    _cameraPosition = position.target;
  }

  void _onCameraIdle() {
    // Debounce reverse geocode to avoid spamming while panning
    _idleDebounce?.cancel();
    _idleDebounce = Timer(const Duration(milliseconds: _idleDebounceMs), () {
      unawaited(_reverseGeocode(_cameraPosition));
    });
  }

  Future<void> _onCurrentLocationPressed() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      final newLoc = LatLng(pos.latitude, pos.longitude);
      _moveToLocation(newLoc);
      // Immediately set and geocode
      setState(() {
        _selectedLocation = newLoc;
      });
      unawaited(_reverseGeocode(newLoc));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not get current location. Check permissions.'),
        ),
      );
    }
  }

  void _onConfirm() {
    if (_selectedLocation != null) {
      Navigator.pop(context, {
        'location': _selectedLocation,
        'address': _selectedAddress,
        'coordinates':
            '${_selectedLocation!.latitude}, ${_selectedLocation!.longitude}',
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a location on the map'),
        ),
      );
    }
  }

  Widget _buildAddressSection() {
    final warn = _selectedAddress.contains('unavailable');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Selected Location:', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (_isGeocoding)
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text('Loading address...', style: Theme.of(context).textTheme.bodyMedium),
            ],
          )
        else
          Text(
            _selectedAddress.isEmpty && !_isLoading
                ? 'Drag map to select location'
                : _selectedAddress,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: warn ? Colors.orange : null,
                ),
          ),
        if (warn && !_isGeocoding)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'You can still confirm this location using coordinates',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.orange,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Location'),
        actions: [
          IconButton(
            tooltip: 'Use current location',
            icon: const Icon(Icons.my_location),
            onPressed: _onCurrentLocationPressed,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: _defaultPosition,
            myLocationEnabled: true,
            zoomControlsEnabled: false,
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
          ),
          const IgnorePointer(
            child: Center(
              child: Icon(Icons.location_pin, size: 40, color: Colors.red),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Card(
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildAddressSection(),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_selectedLocation != null && !_isGeocoding)
                            ? _onConfirm
                            : null,
                        child: const Text('Confirm Location'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
