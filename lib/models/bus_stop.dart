import 'package:google_maps_flutter/google_maps_flutter.dart';

class BusStop {
  final String? id;
  final String name;
  final double latitude;
  final double longitude;
  final String? keyLandmark;

  BusStop({
    this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.keyLandmark,
  });

  factory BusStop.fromJson(Map<String, dynamic> json) {
    return BusStop(
      id: json['_id']?.toString(),
      name: json['name'] ?? json['stopName'] ?? '',
      latitude: (json['latitude'] ?? json['lat'] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? json['lng'] ?? 0).toDouble(),
      keyLandmark: json['keyLandmark'] ?? json['landmark'],
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    if (keyLandmark != null) 'keyLandmark': keyLandmark,
  };

  LatLng get location => LatLng(latitude, longitude);
}
