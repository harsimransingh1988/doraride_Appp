import 'package:flutter/material.dart';
import 'package:google_place/google_place.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String apiKey;
  final ValueChanged<String>? onSelected;

  const LocationField({
    Key? key,
    required this.controller,
    required this.labelText,
    required this.apiKey,
    this.onSelected,
  }) : super(key: key);

  @override
  State<LocationField> createState() => _LocationFieldState();
}

class _LocationFieldState extends State<LocationField> {
  late GooglePlace _googlePlace;
  List<AutocompletePrediction> _predictions = [];
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    _googlePlace = GooglePlace(widget.apiKey);
  }

  /// 📍 Fetch current GPS location and reverse-geocode into an address
  Future<void> _useMyCurrentLocation() async {
    setState(() => _isLoadingLocation = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services.')),
        );
        setState(() => _isLoadingLocation = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
          setState(() => _isLoadingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission permanently denied'),
          ),
        );
        setState(() => _isLoadingLocation = false);
        return;
      }

      // ✅ Get current position
      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // ✅ Convert to human-readable address
      final List<Placemark> placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final String address =
            "${p.locality ?? ''}, ${p.administrativeArea ?? ''}, ${p.country ?? ''}".trim();

        widget.controller.text = address;
        widget.onSelected?.call(address);
      }
    } catch (e) {
      debugPrint("Error getting location: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to get current location')),
      );
    }

    setState(() => _isLoadingLocation = false);
  }

  /// 🔍 Handle typing and show autocomplete predictions
  Future<void> _onSearchChanged(String value) async {
    if (value.isEmpty) {
      setState(() => _predictions = []);
      return;
    }

    final result = await _googlePlace.autocomplete.get(value,
        region: 'ca', // limit to Canada (optional)
        language: 'en');

    if (result != null && result.predictions != null) {
      setState(() => _predictions = result.predictions!);
    } else {
      setState(() => _predictions = []);
    }
  }

  void _onPredictionTap(AutocompletePrediction prediction) {
    final description = prediction.description ?? '';
    widget.controller.text = description;
    widget.onSelected?.call(description);
    setState(() => _predictions = []);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          decoration: InputDecoration(
            labelText: widget.labelText,
            prefixIcon: const Icon(Icons.location_on_outlined),
            suffixIcon: _isLoadingLocation
                ? const Padding(
                    padding: EdgeInsets.all(10.0),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.my_location_rounded),
                    onPressed: _useMyCurrentLocation,
                    tooltip: "Use my current location",
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          onChanged: _onSearchChanged,
        ),
        if (_predictions.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 6,
                ),
              ],
            ),
            margin: const EdgeInsets.only(top: 4),
            child: ListView.builder(
              itemCount: _predictions.length,
              shrinkWrap: true,
              itemBuilder: (context, index) {
                final p = _predictions[index];
                return ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(p.description ?? ''),
                  onTap: () => _onPredictionTap(p),
                );
              },
            ),
          ),
      ],
    );
  }
}
