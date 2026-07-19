import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import 'database_service.dart';
import '../models/location_record.dart';

@pragma('vm:entry-point')
class LocationTrackingService {
  static const int intervalSeconds = 60;
  static const String notificationChannelId = 'location_tracker_channel';
  static const int notificationId = 888;

  static Future<void> initialize() async {
    // IMPORTANT: flutter_background_service does NOT create its Android
    // notification channel for you. If startForeground() is called against
    // a channel ID that was never registered with NotificationManager,
    // Android throws CannotPostForegroundServiceNotificationException
    // ("Bad notification for startForeground") and kills the process. The
    // channel must be created explicitly, once, before service.configure().
    const androidChannel = AndroidNotificationChannel(
      notificationChannelId,
      'Location Tracker Service',
      description: 'Shows ongoing GPS tracking status.',
      importance: Importance.low, // low = silent, still valid as a foreground-service channel
    );

    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'Location Tracker',
        initialNotificationContent: 'Tracking is idle',
        foregroundServiceNotificationId: notificationId,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  static Future<void> start() async {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      await service.startService();
    }
    service.invoke('startTracking');
    await DatabaseService.setTracking(true);
  }

  static Future<void> stop() async {
    final service = FlutterBackgroundService();
    service.invoke('stopTracking');
    await DatabaseService.setTracking(false);
    service.invoke('stopService');
  }

  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    // Each isolate needs its own Hive initialization.
    await DatabaseService.init();

    Timer? samplingTimer;

    void beginSampling() {
      samplingTimer?.cancel();
      samplingTimer = Timer.periodic(
        const Duration(seconds: intervalSeconds),
            (_) => _captureAndStoreLocation(service),
      );
      _captureAndStoreLocation(service); // immediate first sample
    }

    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }

    service.on('startTracking').listen((_) => beginSampling());

    service.on('stopTracking').listen((_) {
      samplingTimer?.cancel();
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Location Tracker',
          content: 'Tracking stopped',
        );
      }
    });

    service.on('stopService').listen((_) {
      samplingTimer?.cancel();
      service.stopSelf();
    });

    // If the service isolate itself was restarted by the OS while a session
    // was active, resume sampling automatically.
    if (DatabaseService.isTracking) {
      beginSampling();
    }
  }

  static Future<void> _captureAndStoreLocation(ServiceInstance service) async {
    try {
      // 1. Is location even turned on for the device? Common reason for
      // silent "no location ever arrives" on emulators/real devices.
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[LocationTracker] Location services are OFF on the device.');
        return;
      }

      final hasPermission = await _ensurePermission();
      if (!hasPermission) {
        debugPrint('[LocationTracker] Permission not granted in background isolate.');
        return;
      }

      // 2. Cap how long we wait for a fix. Without a timeLimit,
      // getCurrentPosition() can hang indefinitely on a weak/no GPS signal
      // (very common on emulators), silently blocking every future cycle
      // since the next Timer tick can't fire until this Future resolves.
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );

      final record = LocationRecord(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: DateTime.now(),
        accuracy: position.accuracy,
      );
      await DatabaseService.addRecord(record);

      debugPrint(
        '[LocationTracker] Saved -> Lat: ${record.latitude}, '
            'Lng: ${record.longitude}, Accuracy: ${record.accuracy}, '
            'Timestamp: ${record.timestamp}',
      );

      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Location Tracker — Active',
          content:
          'Lat ${record.latitude.toStringAsFixed(5)}, '
              'Lng ${record.longitude.toStringAsFixed(5)} '
              '@ ${record.timestamp.toIso8601String()}',
        );
      }

      service.invoke('locationUpdate', record.toJson());
    } catch (e, st) {
      debugPrint('[LocationTracker] Failed to capture location: $e');
      debugPrint('$st');
    }
  }

  static Future<bool> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  @pragma('vm:entry-point')
  static Future<bool> _onIosBackground(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    return true;
  }
}