import 'package:hive_flutter/hive_flutter.dart';
import '../models/location_record.dart';

/// Thin wrapper around the Hive box so both the UI isolate and the
/// background-service isolate talk to storage the exact same way.
class DatabaseService {
  static const String boxName = 'location_records';
  static const String sessionBoxName = 'tracking_session';

  static Box<LocationRecord>? _box;
  static Box? _sessionBox;

  /// Must be called once per isolate (main isolate AND background isolate)
  /// before Hive.openBox is used, because each isolate has its own Hive
  /// runtime.
  static Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(LocationRecordAdapter());
    }
    _box = await Hive.openBox<LocationRecord>(boxName);
    _sessionBox = await Hive.openBox(sessionBoxName);
  }

  static Box<LocationRecord> get box {
    if (_box == null || !_box!.isOpen) {
      throw StateError('DatabaseService.init() must be called first');
    }
    return _box!;
  }

  static Box get sessionBox {
    if (_sessionBox == null || !_sessionBox!.isOpen) {
      throw StateError('DatabaseService.init() must be called first');
    }
    return _sessionBox!;
  }

  static Future<void> addRecord(LocationRecord record) async {
    await box.add(record);
    // Force an immediate disk write. Hive normally batches/delays flushes;
    // without this, a record added right before the process is killed
    // (e.g. force-stop) can be lost even though addRecord() "succeeded".
    await box.flush();
  }

  static Future<void> reload() async {
    if (_box != null && _box!.isOpen) {
      await _box!.close();
    }
    _box = await Hive.openBox<LocationRecord>(boxName);
  }

  static List<LocationRecord> getAllRecords() {
    return box.values.toList().reversed.toList(); // newest first
  }

  static Future<void> clearAll() async {
    await box.clear();
  }

  static bool get isTracking =>
      sessionBox.get('isTracking', defaultValue: false) as bool;

  static Future<void> setTracking(bool value) async {
    await sessionBox.put('isTracking', value);
  }
}