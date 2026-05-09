import 'package:hive_flutter/hive_flutter.dart';

class HistoryEntry extends HiveObject {
  @HiveField(0)
  late String id;
  @HiveField(1)
  late String fileName;
  @HiveField(2)
  late String action;
  @HiveField(3)
  late int timestampMs;
  @HiveField(4)
  late int fileSize;
  @HiveField(5)
  late int? outputSize;
  @HiveField(6)
  late int? pageCount;
  @HiveField(7)
  late String status;

  HistoryEntry({
    required this.id,
    required this.fileName,
    required this.action,
    required DateTime timestamp,
    required this.fileSize,
    this.outputSize,
    this.pageCount,
    required this.status,
  }) : timestampMs = timestamp.millisecondsSinceEpoch;

  HistoryEntry._();

  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(timestampMs);

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  String get sizeFormatted => _fmt(fileSize);
  String get outputSizeFormatted => outputSize != null ? _fmt(outputSize!) : '—';

  static String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class HistoryEntryAdapter extends TypeAdapter<HistoryEntry> {
  @override
  final int typeId = 0;

  @override
  HistoryEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      final key = reader.readByte();
      fields[key] = reader.read();
    }
    return HistoryEntry._()
      ..id = (fields[0] as String)
      ..fileName = (fields[1] as String)
      ..action = (fields[2] as String)
      ..timestampMs = (fields[3] as int)
      ..fileSize = (fields[4] as int)
      ..outputSize = (fields[5] as int?)
      ..pageCount = (fields[6] as int?)
      ..status = (fields[7] as String);
  }

  @override
  void write(BinaryWriter writer, HistoryEntry obj) {
    writer.writeByte(8);
    writer
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.fileName)
      ..writeByte(2)
      ..write(obj.action)
      ..writeByte(3)
      ..write(obj.timestampMs)
      ..writeByte(4)
      ..write(obj.fileSize)
      ..writeByte(5)
      ..write(obj.outputSize)
      ..writeByte(6)
      ..write(obj.pageCount)
      ..writeByte(7)
      ..write(obj.status);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HistoryEntryAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}
