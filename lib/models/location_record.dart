import 'package:hive/hive.dart';

/// A single GPS sample taken every 60 seconds.
///
/// Hand-written TypeAdapter instead of build_runner codegen, so the project
/// builds with zero code-gen step.
class LocationRecord extends HiveObject {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double accuracy; // meters

  LocationRecord({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.accuracy,
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'timestamp': timestamp.toIso8601String(),
    'accuracy': accuracy,
  };
}

class LocationRecordAdapter extends TypeAdapter<LocationRecord> {
  @override
  final int typeId = 0;

  @override
  LocationRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocationRecord(
      latitude: fields[0] as double,
      longitude: fields[1] as double,
      timestamp: fields[2] as DateTime,
      accuracy: fields[3] as double,
    );
  }

  @override
  void write(BinaryWriter writer, LocationRecord obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.latitude)
      ..writeByte(1)
      ..write(obj.longitude)
      ..writeByte(2)
      ..write(obj.timestamp)
      ..writeByte(3)
      ..write(obj.accuracy);
  }
}