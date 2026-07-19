import 'package:flutter/services.dart';

class BatteryService {
  static const MethodChannel _channel =
  MethodChannel('com.example.background_location_tracker/battery');

  static Future<int> getBatteryLevel() async {
    try {
      final int level = await _channel.invokeMethod('getBatteryLevel');
      print('BatteryService: $level');
      return level;
    } on PlatformException catch (e) {
      print('Failed to get battery level: ${e.message}');
      return -1;
    }
  }
}