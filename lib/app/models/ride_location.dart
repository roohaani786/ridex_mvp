import 'package:google_maps_flutter/google_maps_flutter.dart';

class RideLocation {
  final String address;
  final double lat;
  final double lng;

  const RideLocation({
    required this.address,
    required this.lat,
    required this.lng,
  });

  factory RideLocation.fromMap(Map<String, dynamic> map) {
    return RideLocation(
      address: (map['address'] ?? '') as String,
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'address': address,
      'lat': lat,
      'lng': lng,
    };
  }

  LatLng toLatLng() => LatLng(lat, lng);

  RideLocation copyWith({
    String? address,
    double? lat,
    double? lng,
  }) {
    return RideLocation(
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
    );
  }

  @override
  String toString() {
    return 'RideLocation(address: $address, lat: $lat, lng: $lng)';
  }
}