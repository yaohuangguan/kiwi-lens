class SafetyCamera {
  const SafetyCamera({
    required this.id,
    required this.name,
    required this.region,
    required this.suburb,
    required this.location,
    required this.type,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String name;
  final String region;
  final String suburb;
  final String location;
  final String type;
  final double latitude;
  final double longitude;

  factory SafetyCamera.fromJson(Map<String, dynamic> json) {
    return SafetyCamera(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      region: json['region'] as String? ?? '',
      suburb: json['suburb'] as String? ?? '',
      location: json['location'] as String? ?? '',
      type: json['type'] as String? ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}
