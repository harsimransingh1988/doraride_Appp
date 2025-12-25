// lib/features/home/pages/trip_route_map_page.dart

import 'package:flutter/material.dart';
import 'dart:async'; // FIX: Required for Completer
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class TripRouteMapPage extends StatefulWidget {
  final String originName;
  final String destinationName;
  final GeoPoint originGeo;
  final GeoPoint destinationGeo;
  // Note: We would ideally pass all stops and fetch the route/polyline from a routing service (like Google Directions API)

  const TripRouteMapPage({
    super.key,
    required this.originName,
    required this.destinationName,
    required this.originGeo,
    required this.destinationGeo,
  });

  @override
  State<TripRouteMapPage> createState() => _TripRouteMapPageState();
}

class _TripRouteMapPageState extends State<TripRouteMapPage> {
  // FIX: Completer is now defined
  final Completer<GoogleMapController> _controller = Completer();
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  
  // Convert GeoPoint to LatLng
  LatLng get _originLatLng => LatLng(widget.originGeo.latitude, widget.originGeo.longitude);
  LatLng get _destinationLatLng => LatLng(widget.destinationGeo.latitude, widget.destinationGeo.longitude);

  @override
  void initState() {
    super.initState();
    _setMarkersAndRoute();
  }

  void _setMarkersAndRoute() {
    // 1. Add Markers for Origin (A) and Destination (B)
    _markers.add(
      Marker(
        markerId: const MarkerId('origin'),
        position: _originLatLng,
        infoWindow: InfoWindow(title: widget.originName, snippet: 'Origin'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    );
    _markers.add(
      Marker(
        markerId: const MarkerId('destination'),
        position: _destinationLatLng,
        infoWindow: InfoWindow(title: widget.destinationName, snippet: 'Destination'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    );

    // 2. Draw a placeholder Polyline (straight line)
    // NOTE: In a production app, you would use Google Directions API here to get the actual road-following points.
    _polylines.add(
      Polyline(
        polylineId: const PolylineId('route'),
        points: [_originLatLng, _destinationLatLng], // Straight line path
        color: _kThemeBlue,
        width: 5,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    );
    
    // Trigger map repaint
    if (mounted) setState(() {});
  }
  
  void _onMapCreated(GoogleMapController controller) {
    _controller.complete(controller);
    
    // Determine the bounds to fit both markers on screen
    LatLngBounds bounds = _boundsFromLocations([_originLatLng, _destinationLatLng]);
    
    // Animate camera to show the entire route
    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50)); 
  }
  
  // Helper to calculate LatLngBounds from a list of coordinates
  LatLngBounds _boundsFromLocations(List<LatLng> locations) {
    double minLat = locations[0].latitude, maxLat = locations[0].latitude;
    double minLon = locations[0].longitude, maxLon = locations[0].longitude;

    for (var location in locations) {
      if (location.latitude < minLat) minLat = location.latitude;
      if (location.latitude > maxLat) maxLat = location.latitude;
      if (location.longitude < minLon) minLon = location.longitude;
      if (location.longitude > maxLon) maxLon = location.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLon),
      northeast: LatLng(maxLat, maxLon),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Route Map'),
        backgroundColor: _kThemeBlue,
      ),
      body: GoogleMap(
        mapType: MapType.normal,
        initialCameraPosition: CameraPosition(
          target: _originLatLng,
          zoom: 10,
        ),
        onMapCreated: _onMapCreated,
        markers: _markers,
        polylines: _polylines,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: true,
      ),
    );
  }
}