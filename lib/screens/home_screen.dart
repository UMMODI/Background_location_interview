import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/battery_service.dart';
import '../services/database_service.dart';
import '../services/location_tracking_service.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver{
  bool _isTracking = false;
  int _batteryLevel = -1;
  Timer? _batteryPoll;
  int _recordCount = 0;

  static const int _intervalSeconds = LocationTrackingService.intervalSeconds;
  int _secondsRemaining = _intervalSeconds;
  Timer? _countdownTimer;
  StreamSubscription? _locationUpdateSub;

  double? _lastLat;
  double? _lastLng;
  double? _lastAccuracy;
  DateTime? _lastTimestamp;
  final _dateFormat = DateFormat('MMM d, yyyy • HH:mm:ss');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isTracking = DatabaseService.isTracking;
    _recordCount = DatabaseService.getAllRecords().length;
    _loadLastKnownRecord();
    _refreshBattery();
    _batteryPoll = Timer.periodic(const Duration(seconds: 30), (_) => _refreshBattery());

    _locationUpdateSub = FlutterBackgroundService().on('locationUpdate').listen((event) {
      if (event == null) return;
      final lat = (event['latitude'] as num).toDouble();
      final lng = (event['longitude'] as num).toDouble();
      final accuracy = (event['accuracy'] as num).toDouble();
      final timestamp = DateTime.parse(event['timestamp'] as String);

      debugPrint(
        'LOCATION UPDATE -> Lat: $lat, Long: $lng, '
            'Accuracy: ${accuracy.toStringAsFixed(1)}m, '
            'Timestamp: ${timestamp.toIso8601String()}',
      );

      if (!mounted) return;
      setState(() {
        _secondsRemaining = _intervalSeconds;
        _recordCount = DatabaseService.getAllRecords().length;
        _lastLat = lat;
        _lastLng = lng;
        _lastAccuracy = accuracy;
        _lastTimestamp = timestamp;
      });
    });

    if (_isTracking) _startCountdown();
  }

  Future<void> _requestBatteryOptimizationExemption() async {
    final before = await Permission.ignoreBatteryOptimizations.status;
    print("Battery optimization status BEFORE request: $before");

    if (!before.isGranted) {
      final result = await Permission.ignoreBatteryOptimizations.request();
      print("Battery optimization status AFTER request: $result");
    }
  }

  // Future<void> _requestBatteryOptimizationExemption() async {
  //   final status = await Permission.ignoreBatteryOptimizations.status;
  //   if (status.isGranted) return;
  //
  //   final result = await Permission.ignoreBatteryOptimizations.request();
  //   if (result.isGranted) return;
  //   if (mounted) {
  //     final goToSettings = await showDialog<bool>(
  //       context: context,
  //       builder: (ctx) => AlertDialog(
  //         title: const Text('Allow unrestricted background activity'),
  //         content: const Text(
  //           'For the most reliable tracking, please open your app\'s '
  //               'Battery settings and choose "No restrictions" / "Unrestricted".',
  //         ),
  //         actions: [
  //           TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Skip')),
  //           FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open Settings')),
  //         ],
  //       ),
  //     );
  //     if (goToSettings == true) await openAppSettings();
  //   }
  // }

  void _loadLastKnownRecord() {
    final records = DatabaseService.getAllRecords();
    if (records.isNotEmpty) {
      final r = records.first;
      _lastLat = r.latitude;
      _lastLng = r.longitude;
      _lastAccuracy = r.accuracy;
      _lastTimestamp = r.timestamp;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _batteryPoll?.cancel();
    _countdownTimer?.cancel();
    _locationUpdateSub?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _secondsRemaining = _intervalSeconds;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsRemaining--;
        if (_secondsRemaining <= 0) _secondsRemaining = _intervalSeconds;
      });
    });
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    setState(() => _secondsRemaining = _intervalSeconds);
  }

  Future<void> _refreshBattery() async {
    final level = await BatteryService.getBatteryLevel();
    if (mounted) setState(() => _batteryLevel = level);
  }

  /// Checks the device-level Location toggle (separate from app
  /// permissions). If it's off, prompts the user and takes them straight
  /// to system Location settings to turn it on.
  Future<bool> _ensureLocationServiceEnabled() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (enabled) return true;

    if (!mounted) return false;
    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Location is turned off'),
        content: const Text(
          'This device\'s Location service is disabled. Please enable it to start tracking.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enable Location')),
        ],
      ),
    );

    if (shouldOpenSettings == true) {
      await Geolocator.openLocationSettings();
      // The user may or may not have actually enabled it — re-check after
      // they return from Settings instead of assuming.
      return await Geolocator.isLocationServiceEnabled();
    }
    return false;
  }

  Future<bool> _requestPermissions() async {
    final whileInUse = await Permission.locationWhenInUse.request();
    if (!whileInUse.isGranted) {
      return false;
    }

    if (Theme.of(context).platform == TargetPlatform.android) {
      await Permission.notification.request();
    }

    final always = await Permission.locationAlways.request();

    if (always.isPermanentlyDenied) {
      if (mounted) {
        final goToSettings = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Background location needed'),
            content: const Text(
              'To track while the app is backgrounded or locked, open '
                  'Settings > Permissions > Location and select "Allow all the time".',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open Settings')),
            ],
          ),
        );
        if (goToSettings == true) await openAppSettings();
      }
      return false;
    }

    return always.isGranted;
  }

  Future<void> _toggleTracking() async {
    if (_isTracking) {
      await LocationTrackingService.stop();
      _stopCountdown();
      setState(() {
        _isTracking = false;
        _recordCount = DatabaseService.getAllRecords().length;
      });
    } else {
      // 1. Device-level Location toggle first — no point asking for app
      // permissions if Location itself is off system-wide.
      final locationOn = await _ensureLocationServiceEnabled();
      if (!locationOn) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location must be enabled to start tracking.')),
          );
        }
        return;
      }

      // 2. App-level permissions.
      final granted = await _requestPermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Background location permission is required to track in the background.',
              ),
            ),
          );
        }
        return;
      }
      await _requestBatteryOptimizationExemption();
      await LocationTrackingService.start();
      _startCountdown();
      setState(() => _isTracking = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Background Location Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'View history',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _BatteryCard(level: _batteryLevel, onRefresh: _refreshBattery),
            const SizedBox(height: 16),
            _LastLocationCard(
              lat: _lastLat,
              lng: _lastLng,
              accuracy: _lastAccuracy,
              timestamp: _lastTimestamp,
              dateFormat: _dateFormat,
            ),
            const SizedBox(height: 32),
            Icon(
              _isTracking ? Icons.gps_fixed : Icons.gps_off,
              size: 72,
              color: _isTracking ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              _isTracking ? 'Tracking active' : 'Tracking stopped',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_isTracking) ...[
              const SizedBox(height: 8),
              Text(
                'Next location in: ${_secondsRemaining}s',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: 1 - (_secondsRemaining / _intervalSeconds),
                minHeight: 6,
              ),
            ],
            const SizedBox(height: 16),
            Text('$_recordCount points recorded this session'),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isTracking ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: _toggleTracking,
                child: Text(
                  _isTracking ? 'STOP' : 'START',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatteryCard extends StatelessWidget {
  final int level;
  final VoidCallback onRefresh;

  const _BatteryCard({required this.level, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final display = level < 0 ? '—' : '$level%';
    return Card(
      child: ListTile(
        leading: Icon(
          level < 20 && level >= 0 ? Icons.battery_alert : Icons.battery_full,
          color: level < 20 && level >= 0 ? Colors.red : Colors.blueGrey,
        ),
        title: const Text('Battery (native platform channel)'),
        subtitle: Text(display, style: const TextStyle(fontSize: 20)),
        trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: onRefresh),
      ),
    );
  }
}

class _LastLocationCard extends StatelessWidget {
  final double? lat;
  final double? lng;
  final double? accuracy;
  final DateTime? timestamp;
  final DateFormat dateFormat;

  const _LastLocationCard({
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.timestamp,
    required this.dateFormat,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = lat != null && lng != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.location_on_outlined, color: Colors.indigo),
                SizedBox(width: 8),
                Text('Latest Location', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (!hasData)
              const Text('No location captured yet.')
            else ...[
              _InfoRow(label: 'Latitude', value: lat!.toStringAsFixed(6)),
              _InfoRow(label: 'Longitude', value: lng!.toStringAsFixed(6)),
              _InfoRow(label: 'Accuracy', value: '±${accuracy!.toStringAsFixed(1)} m'),
              _InfoRow(label: 'Timestamp', value: dateFormat.format(timestamp!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}