import 'dart:async';

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/network/api_exception.dart';

enum PrayerLocationPermission { denied, deniedForever, granted, unavailable }

class PrayerDevicePosition {
  const PrayerDevicePosition({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class PrayerDeviceLocation {
  const PrayerDeviceLocation({
    required this.latitude,
    required this.longitude,
    required this.timezone,
  });

  final double latitude;
  final double longitude;
  final String timezone;
}

abstract interface class PrayerLocationGateway {
  Future<bool> isServiceEnabled();

  Future<PrayerLocationPermission> checkPermission();

  Future<PrayerLocationPermission> requestPermission();

  Future<PrayerDevicePosition> currentPosition();

  Future<String> currentTimezone();
}

class DevicePrayerLocationGateway implements PrayerLocationGateway {
  const DevicePrayerLocationGateway();

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<PrayerLocationPermission> checkPermission() async =>
      _mapPermission(await Geolocator.checkPermission());

  @override
  Future<PrayerLocationPermission> requestPermission() async =>
      _mapPermission(await Geolocator.requestPermission());

  @override
  Future<PrayerDevicePosition> currentPosition() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return PrayerDevicePosition(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  @override
  Future<String> currentTimezone() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;

  PrayerLocationPermission _mapPermission(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.whileInUse ||
        LocationPermission.always => PrayerLocationPermission.granted,
        LocationPermission.denied => PrayerLocationPermission.denied,
        LocationPermission.deniedForever =>
          PrayerLocationPermission.deniedForever,
        LocationPermission.unableToDetermine =>
          PrayerLocationPermission.unavailable,
      };
}

Future<PrayerDeviceLocation> acquirePrayerDeviceLocation(
  PrayerLocationGateway gateway,
) async {
  final enabled = await gateway.isServiceEnabled();
  if (!enabled) {
    throw const ApiException(
      message: 'Location services are disabled',
      code: 'location_disabled',
    );
  }

  var permission = await gateway.checkPermission();
  if (permission == PrayerLocationPermission.denied) {
    permission = await gateway.requestPermission();
  }
  if (permission == PrayerLocationPermission.denied) {
    throw const ApiException(
      message: 'Location permission was denied',
      code: 'location_denied',
    );
  }
  if (permission == PrayerLocationPermission.deniedForever) {
    throw const ApiException(
      message: 'Location permission was permanently denied',
      code: 'location_denied_forever',
    );
  }
  if (permission != PrayerLocationPermission.granted) {
    throw const ApiException(
      message: 'Location permission could not be determined',
      code: 'location_unavailable',
    );
  }

  try {
    final position = await gateway.currentPosition();
    final timezone = await gateway.currentTimezone();
    if (!position.latitude.isFinite ||
        !position.longitude.isFinite ||
        position.latitude < -90 ||
        position.latitude > 90 ||
        position.longitude < -180 ||
        position.longitude > 180 ||
        timezone.trim().isEmpty) {
      throw const FormatException('Invalid device location');
    }
    return PrayerDeviceLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      timezone: timezone,
    );
  } on TimeoutException {
    throw const ApiException(
      message: 'Location request timed out',
      code: 'location_timeout',
    );
  } on Object {
    throw const ApiException(
      message: 'Location is unavailable',
      code: 'location_unavailable',
    );
  }
}
