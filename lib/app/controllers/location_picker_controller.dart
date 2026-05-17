import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/ride_model.dart';
import '../services/location_service.dart';
import 'dart:ui' as ui;

// ── Place suggestion model ────────────────────────────────────────────────────
// Holds exactly what Autocomplete returns — no lat/lng yet.
// Coordinates are fetched only when the user actually taps a result.
class PlaceSuggestion {
  final String placeId;
  final String mainText;        // e.g. "Charminar"
  final String secondaryText;   // e.g. "Hyderabad, Telangana, India"
  final String fullText;        // full description for fallback display

  const PlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
    required this.fullText,
  });
}

class LocationPickerController extends GetxController {
  GoogleMapController? mapController;

  bool _mapReady = false;
  bool _isProgrammaticMove = false;

  static const _apiKey = 'AIzaSyAF-9v8atdEyUpdgmcfvK2HEsxo6ffbYEk';

  final mapType           = Rx<MapType>(MapType.normal);
  final selectedPosition  = Rx<LatLng?>(null);
  final selectedAddress   = RxString('');
  final isLoadingAddress  = RxBool(false);
  final isLoadingLocation = RxBool(false);

  final searchController = TextEditingController();
  final searchResults    = RxList<PlaceSuggestion>([]);  // ← changed type
  final isSearching      = RxBool(false);
  final isLoadingPlace   = RxBool(false);               // ← for place details fetch

  // ── Add this with the other observables at the top of the class ───────────
  final poiMarkers = RxMap<String, Marker>();
  Timer? _debounce; // ← move this here if it ended up outside the class

  // ── Add with other observables ─────────────────────────────────────────────
  final isDarkMode = RxBool(true); // ← dark by default

  static const _poiConfig = {
    'gas_station':       {'initial': 'F', 'label': 'Fuel',     'color': 0xFFFFB300},
    'restaurant':        {'initial': 'R', 'label': 'Food',     'color': 0xFFE64A19},
    'cafe':              {'initial': 'C', 'label': 'Café',     'color': 0xFF6D4C41},
    'lodging':           {'initial': 'H', 'label': 'Hotel',    'color': 0xFF1565C0},
    'convenience_store': {'initial': 'S', 'label': 'Store',    'color': 0xFF00897B},
    'meal_takeaway':     {'initial': 'T', 'label': 'Takeaway', 'color': 0xFFEF6C00},
    'pharmacy':          {'initial': 'P', 'label': 'Pharmacy', 'color': 0xFFC62828},
    'atm':               {'initial': 'A', 'label': 'ATM',      'color': 0xFF2E7D32},
  };
  final _markerIconCache = <String, BitmapDescriptor>{};

  @override
  void onInit() {
    super.onInit();
  }


  static const _darkMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#1a1a2e"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#e0e0e0"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1a1a2e"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#ffffff"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#2d2d44"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#3d3d5c"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road","elementType":"labels.text.stroke","stylers":[{"color":"#1a1a2e"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#373755"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#4a4a7a"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.highway.controlled_access","elementType":"geometry","stylers":[{"color":"#5a5a8a"}]},
  {"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#cccccc"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0d1b2a"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#515c6d"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels.text","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.medical","elementType":"geometry","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.medical","elementType":"labels","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.medical","elementType":"labels.text.fill","stylers":[{"color":"#e05252"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#0d2137","visibility":"on"}]},
  {"featureType":"poi.park","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]}
]''';

  static const _lightMapStyle = '''[
  {"featureType":"poi","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels.text","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.medical","elementType":"geometry","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.medical","elementType":"labels","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.medical","elementType":"labels.text.fill","stylers":[{"color":"#cc0000"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"visibility":"on"}]},
  {"featureType":"poi.park","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]}
]''';

  // ── Rider POI types — what the Places Nearby Search will fetch ────────────
  static const _riderPoiTypes = [
    'gas_station',
    'restaurant',
    'cafe',
    'lodging',
    'convenience_store',
    'meal_takeaway',
    'pharmacy',            // useful on long rides
    'atm',                 // cash on the road
  ];

  Future<void> loadRiderPois(LatLng origin) async {
    poiMarkers.clear();
    try {
      for (final type in _riderPoiTypes) {
        final uri = Uri.parse(
          'https://places.googleapis.com/v1/places:searchNearby',
        );

        final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'X-Goog-Api-Key': _apiKey,
            'X-Goog-FieldMask': 'places.displayName,places.location,places.types',
          },
          body: jsonEncode({
            'includedTypes': [type],
            'maxResultCount': 10,
            'locationRestriction': {
              'circle': {
                'center': {
                  'latitude': origin.latitude,
                  'longitude': origin.longitude,
                },
                'radius': 2000.0,   // 2km radius around current position
              },
            },
          }),
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode != 200) continue;

        final data   = jsonDecode(response.body) as Map<String, dynamic>;
        final places = (data['places'] as List? ?? []).cast<Map<String, dynamic>>();

        for (final place in places) {
          final loc = place['location'] as Map<String, dynamic>?;
          if (loc == null) continue;
          final name = (place['displayName'] as Map?)?['text'] as String? ?? type;
          final latLng = LatLng(
            (loc['latitude']  as num).toDouble(),
            (loc['longitude'] as num).toDouble(),
          );
          await _addRiderPoiMarker(latLng, name, type); // ← await now
        }
      }
    } catch (e) {
      debugPrint('Rider POI load error: $e');
    }
  }

  Future<LocationPoint?> buildLocationPoint() async {
    try {
      final pos = selectedPosition.value;

      if (pos == null) return null;

      return LocationPoint(
        lat: pos.latitude,
        lng: pos.longitude,
        address: selectedAddress.value,
      );
    } catch (e) {
      debugPrint('buildLocationPoint error: $e');
      return null;
    }
  }

  Future<BitmapDescriptor> _buildPillMarker({
    required String label,
    required String initial,   // single letter instead of emoji
    required Color bgColor,
  }) async {
    const double scale  = 3.0;
    const double padH   = 8  * scale;
    const double padV   = 5  * scale;
    const double circleR = 8 * scale;
    const double textSz = 9  * scale;
    const double gap    = 4  * scale;
    const double radius = 10 * scale;
    const double tipH   = 7  * scale;
    const double tipW   = 8  * scale;

    // Measure label text
    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(               // ← Flutter TextStyle, NOT ui.TextStyle
          fontSize:   textSz,
          fontWeight: FontWeight.w800,  // ← FontWeight, NOT ui.FontWeight
          color:      Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final double pillW  = padH + (circleR * 2) + gap + labelPainter.width + padH;
    final double pillH  = padV + (circleR * 2) + padV;
    final double totalH = pillH + tipH;

    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder, Rect.fromLTWH(0, 0, pillW, totalH));

    // ── Drop shadow ───────────────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(scale, scale, pillW - scale, pillH - scale),
        Radius.circular(radius),
      ),
      Paint()
        ..color = Colors.black.withOpacity(0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3 * scale),
    );

    // ── Pill ──────────────────────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, pillW, pillH),
        Radius.circular(radius),
      ),
      Paint()..color = bgColor,
    );

    // ── Tip ───────────────────────────────────────────────────────────────────
    canvas.drawPath(
      Path()
        ..moveTo(pillW / 2 - tipW / 2, pillH)
        ..lineTo(pillW / 2,            pillH + tipH)
        ..lineTo(pillW / 2 + tipW / 2, pillH)
        ..close(),
      Paint()..color = bgColor,
    );

    // ── Circle badge (replaces emoji) ─────────────────────────────────────────
    final circleX = padH + circleR;
    final circleY = pillH / 2;

    canvas.drawCircle(
      Offset(circleX, circleY),
      circleR,
      Paint()..color = Colors.white.withOpacity(0.25),
    );

    // Initial letter inside circle
    final initPainter = TextPainter(
      text: TextSpan(
        text: initial,
        style: TextStyle(
          fontSize:   circleR * 1.1,
          fontWeight: FontWeight.w900,
          color:      Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    initPainter.paint(
      canvas,
      Offset(circleX - initPainter.width / 2, circleY - initPainter.height / 2),
    );

    // ── Label ─────────────────────────────────────────────────────────────────
    labelPainter.paint(
      canvas,
      Offset(padH + circleR * 2 + gap, (pillH - labelPainter.height) / 2),
    );

    // ── Rasterise ─────────────────────────────────────────────────────────────
    final picture = recorder.endRecording();
    final image   = await picture.toImage(pillW.ceil(), totalH.ceil());
    final bytes   = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return BitmapDescriptor.defaultMarker;

    return BitmapDescriptor.fromBytes(bytes.buffer.asUint8List());
    // ↑ No size param — works on all google_maps_flutter versions
  }

  // ── Fix _addRiderPoiMarker — remove the _poiIcon call, use only _poiHue ──
  Future<void> _addRiderPoiMarker(LatLng latLng, String name, String type) async {
    final markerId = 'poi_${latLng.latitude}_${latLng.longitude}';

    BitmapDescriptor icon;
    if (_markerIconCache.containsKey(type)) {
      icon = _markerIconCache[type]!;
    } else {
      final config = _poiConfig[type] ?? {
        'initial': '?',
        'label': type,
        'color': 0xFF607D8B,
      };
      icon = await _buildPillMarker(
        label:   config['label']   as String,
        initial: config['initial'] as String,
        bgColor: Color(config['color'] as int),
      );
      _markerIconCache[type] = icon;
    }

    poiMarkers[markerId] = Marker(
      markerId: MarkerId(markerId),
      position: latLng,
      icon:     icon,
      anchor:   const Offset(0.5, 1.0),
      infoWindow: InfoWindow(title: name),
      zIndex: 1,
    );
  }



  double _poiHue(String type) {
    switch (type) {
      case 'gas_station':      return BitmapDescriptor.hueYellow;
      case 'restaurant':
      case 'meal_takeaway':    return BitmapDescriptor.hueOrange;
      case 'cafe':             return BitmapDescriptor.hueRose;
      case 'lodging':          return BitmapDescriptor.hueBlue;
      case 'pharmacy':         return BitmapDescriptor.hueRed;
      case 'atm':              return BitmapDescriptor.hueGreen;
      case 'convenience_store':return BitmapDescriptor.hueCyan;
      default:                 return BitmapDescriptor.hueViolet;
    }
  }


  // ── Add method ─────────────────────────────────────────────────────────────
  void toggleMapTheme() {
    isDarkMode.value = !isDarkMode.value;
    _applyMapTheme();
  }

  void _applyMapTheme() async {
    try {
      await mapController?.setMapStyle(
        isDarkMode.value ? _darkMapStyle : _lightMapStyle,
      );
    } catch (e) {
      // Silently ignore — style partially applied or unsupported feature type
      debugPrint('Map style warning: $e');
    }
  }

  void onMapCreated(GoogleMapController controller) async {
    mapController = controller;
    _mapReady = true;

    _applyMapTheme();

    // Give map + permission flow time to settle
    Future.delayed(const Duration(milliseconds: 700), () async {
      await _goToCurrentLocation();
    });
  }

  void zoomIn()  => mapController?.animateCamera(CameraUpdate.zoomIn());
  void zoomOut() => mapController?.animateCamera(CameraUpdate.zoomOut());

  void toggleMapType() {
    mapType.value = mapType.value == MapType.normal
        ? MapType.satellite
        : MapType.normal;

    // Re-apply theme when switching back to normal — satellite ignores styles
    if (mapType.value == MapType.normal) _applyMapTheme();
  }

  // ─── GPS init ─────────────────────────────────────────────────────────────

  Future<void> _goToCurrentLocation() async {
    try {

      isLoadingLocation.value = true;
      final granted = await LocationService.to.ensurePermissions();
      if (!granted) return;

      Position? pos;
      for (final timeout in [5, 10, 15]) {
        try {
          final candidate = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: timeout),
          );
          if (candidate.accuracy <= 30.0) { pos = candidate; break; }
        } catch (_) {}
      }
      pos ??= await LocationService.to.getCurrentPosition();
      if (pos == null) return;

      final latLng = LatLng(pos.latitude, pos.longitude);
      _isProgrammaticMove = true;
      selectedPosition.value = latLng;

      if (!_mapReady || mapController == null) return;
      await mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: latLng,
            zoom: 17,
          ),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 300));
      _isProgrammaticMove = false;
      await _reverseGeocode(latLng);
      loadRiderPois(latLng);
    } catch (e) {
      debugPrint('Current location failed: $e');
    } finally {
      isLoadingLocation.value = false;
      _isProgrammaticMove = false;
    }
  }

  void onCameraMove(CameraPosition position) {
    if (_isProgrammaticMove) return;
    selectedPosition.value = position.target;
  }

  void onCameraIdle() {
    if (_isProgrammaticMove) return;
    if (selectedPosition.value != null) _reverseGeocode(selectedPosition.value!);
  }

  // ─── Reverse geocode (pin → address) ──────────────────────────────────────

  Future<void> _reverseGeocode(LatLng latLng) async {
    isLoadingAddress.value = true;
    try {
      final placemarks = await placemarkFromCoordinates(
        latLng.latitude, latLng.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [p.name, p.subLocality, p.locality]
            .where((s) => s != null && s.isNotEmpty)
            .toList();
        selectedAddress.value = parts.join(', ');
      }
    } catch (_) {
      selectedAddress.value =
      '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
    } finally {
      isLoadingAddress.value = false;
    }
  }

  // ─── Search: Places Autocomplete API ──────────────────────────────────────
  // Replaces locationFromAddress — returns real place names + disambiguation.
  // Debounced at 400ms so we don't hammer the API on every keystroke.

  void searchLocation(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      searchResults.clear();
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 400), () async {
      await _fetchAutocompleteSuggestions(query.trim());
    });
  }

  // ─── Search: New Places API v1 Autocomplete ───────────────────────────────
  Future<void> _fetchAutocompleteSuggestions(String query) async {
    isSearching.value = true;
    try {
      final uri = Uri.parse(
        'https://places.googleapis.com/v1/places:autocomplete',
      );

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _apiKey,          // ← key goes in header, not URL
        },
        body: jsonEncode({
          'input': query,
          'languageCode': 'en',
          'includedRegionCodes': ['in'],       // scope to India; remove if international
        }),
      ).timeout(const Duration(seconds: 8));

      debugPrint('Places v1 status: ${response.statusCode}');
      debugPrint('Places v1 body: ${response.body}');

      if (response.statusCode != 200) {
        await _fallbackSearch(query);
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final suggestions = (data['suggestions'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      if (suggestions.isEmpty) {
        searchResults.clear();
        return;
      }

      searchResults.assignAll(suggestions.map((s) {
        // New API nests everything under 'placePrediction'
        final pred       = s['placePrediction'] as Map<String, dynamic>? ?? {};
        final structured = pred['structuredFormat'] as Map<String, dynamic>? ?? {};
        final mainText   = (structured['mainText'] as Map?)?['text'] as String? ?? '';
        final secText    = (structured['secondaryText'] as Map?)?['text'] as String? ?? '';
        final fullText   = (pred['text'] as Map?)?['text'] as String? ?? mainText;

        // New API returns 'places/PLACE_ID' — strip the prefix
        final placeResource = pred['place'] as String? ?? '';
        final placeId = placeResource.replaceFirst('places/', '');

        return PlaceSuggestion(
          placeId:       placeId,
          mainText:      mainText,
          secondaryText: secText,
          fullText:      fullText,
        );
      }));

    } catch (e) {
      debugPrint('Autocomplete v1 error: $e');
      await _fallbackSearch(query);
    } finally {
      isSearching.value = false;
    }
  }

// ─── Select result: New Places API v1 Place Details ───────────────────────
  Future<void> selectSearchResult(PlaceSuggestion suggestion) async {
    searchResults.clear();
    searchController.clear();
    FocusManager.instance.primaryFocus?.unfocus();

    if (suggestion.placeId.isEmpty) {
      await _fallbackSelect(suggestion.mainText);
      return;
    }

    isLoadingPlace.value = true;
    selectedAddress.value = suggestion.fullText;

    try {
      // New API: GET /v1/places/{place_id} with field mask in header
      final uri = Uri.parse(
        'https://places.googleapis.com/v1/places/${suggestion.placeId}',
      );

      final response = await http.get(
        uri,
        headers: {
          'X-Goog-Api-Key': _apiKey,
          'X-Goog-FieldMask': 'location,formattedAddress', // ← only fetch what we need
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return;

      final data    = jsonDecode(response.body) as Map<String, dynamic>;

      // New API response shape is flat — no nested 'result' wrapper
      final location = data['location'] as Map<String, dynamic>?;
      if (location == null) return;

      final latLng = LatLng(
        (location['latitude']  as num).toDouble(),
        (location['longitude'] as num).toDouble(),
      );
      final address = data['formattedAddress'] as String? ?? suggestion.fullText;

      selectedAddress.value  = address;
      selectedPosition.value = latLng;

      _isProgrammaticMove = true;
      await mapController?.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: latLng, zoom: 17)),
      );
      Future.delayed(
        const Duration(milliseconds: 800),
            () => _isProgrammaticMove = false,
      );
      loadRiderPois(latLng);
    } catch (e) {
      debugPrint('Place details v1 error: $e');
    } finally {
      isLoadingPlace.value = false;
    }
  }

// ─── Fallback helpers (if API key still has issues) ───────────────────────
  Future<void> _fallbackSearch(String query) async {
    try {
      final locations = await locationFromAddress(query)
          .timeout(const Duration(seconds: 6));
      searchResults.assignAll(locations.map((loc) => PlaceSuggestion(
        placeId:       '',
        mainText:      query,
        secondaryText: '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}',
        fullText:      query,
      )));
    } catch (_) {
      searchResults.clear();
    }
  }

  Future<void> _fallbackSelect(String query) async {
    try {
      final locations = await locationFromAddress(query);
      if (locations.isEmpty) return;
      final latLng = LatLng(locations.first.latitude, locations.first.longitude);
      selectedAddress.value  = query;
      selectedPosition.value = latLng;
      _isProgrammaticMove = true;
      await mapController?.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: latLng, zoom: 17)),
      );
      Future.delayed(
        const Duration(milliseconds: 800),
            () => _isProgrammaticMove = false,
      );
      loadRiderPois(latLng);
    } catch (e) {
      debugPrint('Fallback select error: $e');
    }
  }
  // ─── Select result: Place Details API ─────────────────────────────────────
  // Only fetches coordinates when user taps — not on every suggestion.

  void goToMyLocation() => _goToCurrentLocation();

  void confirmLocation() {
    if (selectedPosition.value == null) return;
    Get.back(result: LocationPoint(
      lat:     selectedPosition.value!.latitude,
      lng:     selectedPosition.value!.longitude,
      address: selectedAddress.value,
    ));
  }

  @override
  void onClose() {
    _markerIconCache.clear();
    _debounce?.cancel();
    mapController?.dispose();
    searchController.dispose();
    super.onClose();
  }
}