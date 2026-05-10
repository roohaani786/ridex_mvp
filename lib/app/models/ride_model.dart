import 'package:cloud_firestore/cloud_firestore.dart';

class LocationPoint {
  final double lat;
  final double lng;
  final String address;

  LocationPoint({
    required this.lat,
    required this.lng,
    required this.address,
  });

  Map<String, dynamic> toMap() => {
        'lat': lat,
        'lng': lng,
        'address': address,
      };

  factory LocationPoint.fromMap(Map<String, dynamic> map) => LocationPoint(
        lat: (map['lat'] as num).toDouble(),
        lng: (map['lng'] as num).toDouble(),
        address: map['address'] ?? '',
      );
}

enum RideStatus { waiting, active, completed }

class RideModel {
  final String code;
  final String creatorId;
  final LocationPoint startLocation;
  final LocationPoint endLocation;
  final RideStatus status;
  final Map<String, RideMember> members;
  final DateTime createdAt;

  RideModel({
    required this.code,
    required this.creatorId,
    required this.startLocation,
    required this.endLocation,
    required this.status,
    required this.members,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'code': code,
        'creatorId': creatorId,
        'startLocation': startLocation.toMap(),
        'endLocation': endLocation.toMap(),
        'status': status.name,
        'members': members.map((k, v) => MapEntry(k, v.toMap())),
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory RideModel.fromMap(Map<String, dynamic> map) => RideModel(
        code: map['code'] ?? '',
        creatorId: map['creatorId'] ?? '',
        startLocation: LocationPoint.fromMap(
          Map<String, dynamic>.from(map['startLocation'] ?? {}),
        ),
        endLocation: LocationPoint.fromMap(
          Map<String, dynamic>.from(map['endLocation'] ?? {}),
        ),
        status: RideStatus.values.firstWhere(
          (e) => e.name == map['status'],
          orElse: () => RideStatus.waiting,
        ),
        members: (map['members'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, RideMember.fromMap(Map<String, dynamic>.from(v))),
        ),
        createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  RideModel copyWith({
    RideStatus? status,
    Map<String, RideMember>? members,
  }) =>
      RideModel(
        code: code,
        creatorId: creatorId,
        startLocation: startLocation,
        endLocation: endLocation,
        status: status ?? this.status,
        members: members ?? this.members,
        createdAt: createdAt,
      );
}

class RideMember {
  final String userId;
  final String name;
  final DateTime joinedAt;

  RideMember({
    required this.userId,
    required this.name,
    required this.joinedAt,
  });

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'name': name,
        'joinedAt': Timestamp.fromDate(joinedAt),
      };

  factory RideMember.fromMap(Map<String, dynamic> map) => RideMember(
        userId: map['userId'] ?? '',
        name: map['name'] ?? 'Rider',
        joinedAt: (map['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
}

class MemberLocation {
  final String userId;
  final double lat;
  final double lng;
  final double accuracy;
  final double speed;
  final double heading;
  final int timestamp;
  final bool hasReached;

  MemberLocation({
    required this.userId,
    required this.lat,
    required this.lng,
    this.accuracy = 0,
    this.speed = 0,
    this.heading = 0,
    required this.timestamp,
    this.hasReached = false,
  });

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'speed': speed,
        'heading': heading,
        'timestamp': timestamp,
        'hasReached': hasReached,
      };

  factory MemberLocation.fromMap(Map<String, dynamic> map) => MemberLocation(
        userId: map['userId'] ?? '',
        lat: (map['lat'] as num?)?.toDouble() ?? 0,
        lng: (map['lng'] as num?)?.toDouble() ?? 0,
        accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0,
        speed: (map['speed'] as num?)?.toDouble() ?? 0,
        heading: (map['heading'] as num?)?.toDouble() ?? 0,
        timestamp: (map['timestamp'] as num?)?.toInt() ?? 0,
        hasReached: map['hasReached'] as bool? ?? false,
      );
}
