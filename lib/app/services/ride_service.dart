import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../models/ride_location.dart';
import '../models/ride_model.dart';
import 'user_service.dart';

class RideService extends GetxService {
  static RideService get to => Get.find();

  final _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
    'https://ridex-mvp-default-rtdb.asia-southeast1.firebasedatabase.app',
  );

  CollectionReference<Map<String, dynamic>> get _rides =>
      _firestore.collection('rides');

  StreamSubscription<Position>? _positionSub;

  // ─── Ride Creation ───────────────────────────────────────────────────────

  Future<RideModel?> createRide({
    required String startAddress,
    required double startLat,
    required double startLng,
    required String endAddress,
    required double endLat,
    required double endLng,
  }) async {
    try {
      final user = UserService.to;
      final myUserId = _generateUserId(); // Anonymous user ID
      final rideCode = _generate4DigitCode();

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final creator = RideMember(
        userId: myUserId,
        name: user.userName,
        joinedAt: DateTime.now(),
      );

      final ride = RideModel(
        code: rideCode,
        creatorId: myUserId,
        status: RideStatus.waiting,
        createdAt: DateTime.now(),
        startLocation: LocationPoint(  // Fixed: Use RideLocation
          address: startAddress,
          lat: startLat,
          lng: startLng,
        ),
        endLocation: LocationPoint(
          address: endAddress,
          lat: endLat,
          lng: endLng,
        ),
        members: {
          myUserId: creator,
        },
      );

      await _rides.doc(rideCode).set(ride.toMap());

      await _rtdb.ref('locations/$rideCode/$myUserId').set({
        'userId': myUserId,
        'lat': position.latitude,
        'lng': position.longitude,
        'speed': position.speed ?? 0.0,
        'accuracy': position.accuracy,
        'heading': position.heading ?? 0.0,
        'hasReached': false,
        'timestamp': ServerValue.timestamp,
      });

      // await startLocationStream(rideCode, myUserId);

      return ride;
    } catch (e) {
      Get.snackbar('Error', 'Failed to create ride: $e');
      return null;
    }
  }

  // ─── Location Stream ─────────────────────────────────────────────────────

  Future<void> startLocationStream(String rideCode, String userId) async {
    await _positionSub?.cancel();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) async {
      await updateMyLocation(
        rideCode,
        MemberLocation(
          userId: userId,
          lat: position.latitude,
          lng: position.longitude,
          speed: position.speed ?? 0.0,
          accuracy: position.accuracy,
          heading: position.heading ?? 0.0,
          hasReached: false,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
  }

  Future<void> stopLocationStream() async {
    await _positionSub?.cancel();
    _positionSub = null;
  }

  // ─── Join Ride ────────────────────────────────────────────────────────────

  Future<RideModel?> joinRide(String code) async {
    try {
      final user = UserService.to;
      final myUserId = _generateUserId();

      final doc = await _rides.doc(code).get();

      if (!doc.exists) {
        Get.snackbar('Invalid Ride', 'Ride not found.');
        return null;
      }

      final ride = RideModel.fromMap(doc.data()!);

      // Prevent joining completed ride
      if (ride.status == RideStatus.completed) {
        Get.snackbar(
          'Ride Ended',
          'This ride has already been completed.',
        );
        return null;
      }

      // Prevent over-capacity
      if (ride.members.length >= 2 &&
          !ride.members.containsKey(myUserId)) {
        Get.snackbar(
          'Ride Full',
          'This ride already has 2 participants.',
        );
        return null;
      }

      // Copy existing members
      final updatedMembers =
      Map<String, dynamic>.from(
        ride.toMap()['members'] as Map,
      );

      // Add current user
      updatedMembers[myUserId] = RideMember(
        userId: myUserId,
        name: user.userName,
        joinedAt: DateTime.now(),
      ).toMap();

      // Update ride status
      final newStatus = updatedMembers.length >= 2
          ? RideStatus.active
          : RideStatus.waiting;

      // Save updated ride
      await _rides.doc(code).set({
        'members': updatedMembers,
        'status': newStatus.name,
      }, SetOptions(merge: true));

      // Save initial location immediately
      await saveInitialLocation(code, myUserId);

      // Start continuous tracking
      await startLocationStream(code, myUserId);

      // Return updated ride
      return RideModel.fromMap({
        ...doc.data()!,
        'members': updatedMembers,
        'status': newStatus.name,
      });
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to join ride: $e',
      );
      return null;
    }
  }

  Future<void> saveInitialLocation(
      String rideCode,
      String userId,
      ) async {
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    await _rtdb.ref('locations/$rideCode/$userId').set({
      'userId': userId,
      'lat': position.latitude,
      'lng': position.longitude,
      'speed': position.speed,
      'accuracy': position.accuracy,
      'heading': position.heading,
      'hasReached': false,
      'timestamp': ServerValue.timestamp,
    });
  }

  // ─── Ride Stream ─────────────────────────────────────────────────────────

  Stream<RideModel?> watchRide(String code) {
    return _rides.doc(code).snapshots().map((snap) {
      if (!snap.exists) return null;
      return RideModel.fromMap(snap.data()!);
    });
  }

  // ─── Real-Time Location (RTDB) ───────────────────────────────────────────

  Future<void> updateMyLocation(String rideCode, MemberLocation location) async {
    try {
      await _rtdb
          .ref('locations/$rideCode/${location.userId}')
          .set(location.toMap());
    } catch (_) {}
  }

  Stream<Map<String, MemberLocation>> watchLocations(String code) {
    print("249");
    return _rtdb.ref('locations/$code').onValue.map((event) {
      print("251 $event");
      final raw = event.snapshot.value;

      if (raw == null) {
        print("255");
        return <String, MemberLocation>{};
      }

      final rawMap = Map<dynamic, dynamic>.from(raw as Map);
      final parsed = <String, MemberLocation>{};

      rawMap.forEach((key, value) {
        print("263");
        if (value == null) return;

        parsed[key.toString()] = MemberLocation.fromMap(
          Map<String, dynamic>.from(
            Map<dynamic, dynamic>.from(value),
          ),
        );
      });

      return parsed;
    });
  }

  // ─── Mark Reached ────────────────────────────────────────────────────────

  Future<void> markReached(String rideCode, String userId) async {
    try {
      await _rtdb.ref('locations/$rideCode/$userId').update({
        'hasReached': true,
        'timestamp': ServerValue.timestamp,
      });

      final snapshot = await _rtdb.ref('locations/$rideCode').get();

      if (snapshot.value != null) {
        final locs = Map<dynamic, dynamic>.from(snapshot.value as Map);

        final allReached = locs.values.every((v) {
          final map = Map<dynamic, dynamic>.from(v as Map);
          return map['hasReached'] == true;
        });

        if (allReached) {
          await _rides.doc(rideCode).update({
            'status': RideStatus.completed.name,
          });
        }
      }
    } catch (_) {}
  }

  // ─── End Ride ────────────────────────────────────────────────────────────

  Future<void> endRide(String rideCode) async {
    try {
      await stopLocationStream();
      await _rides.doc(rideCode).update({
        'status': RideStatus.completed.name,
      });
      await _rtdb.ref('locations/$rideCode').remove();
    } catch (_) {}
  }

  // ─── Cleanup ─────────────────────────────────────────────────────────────

  @override
  void onClose() {
    _positionSub?.cancel();
    super.onClose();
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  String _generate4DigitCode() {
    return (1000 + Random().nextInt(9000)).toString();
  }

  final _uuid = const Uuid();

  String _generateUserId() {
    return _uuid.v4();
  }
}