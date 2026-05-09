import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';
import '../models/history_entry.dart';
import 'auth_service.dart';

class HistoryService {
  static final HistoryService _instance = HistoryService._();
  HistoryService._();
  static HistoryService get instance => _instance;

  static const _boxName = 'history';
  static const _maxLocal = 100;
  static const _uuid = Uuid();

  Box<HistoryEntry> get _box => Hive.box<HistoryEntry>(_boxName);

  bool get _useFirestore =>
      kFirebaseEnabled &&
      !AuthService.instance.isAnonymousSession &&
      AuthService.instance.currentUser != null;

  String get _uid => AuthService.instance.currentUser!.uid;

  String newId() => _uuid.v4();

  Future<void> addEntry(HistoryEntry entry) async {
    if (_useFirestore) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('history')
          .doc(entry.id)
          .set({
        'fileName': entry.fileName,
        'action': entry.action,
        'timestamp': Timestamp.fromDate(entry.timestamp),
        'fileSize': entry.fileSize,
        'outputSize': entry.outputSize,
        'pageCount': entry.pageCount,
        'status': entry.status,
      });
    } else {
      await _box.put(entry.id, entry);
      if (_box.length > _maxLocal) {
        final oldest = _box.keys.first;
        await _box.delete(oldest);
      }
    }
  }

  Future<List<HistoryEntry>> getHistory() async {
    if (_useFirestore) {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('history')
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();
      return snap.docs.map((doc) {
        final d = doc.data();
        return HistoryEntry(
          id: doc.id,
          fileName: d['fileName'] as String? ?? '',
          action: d['action'] as String? ?? '',
          timestamp: (d['timestamp'] as Timestamp).toDate(),
          fileSize: d['fileSize'] as int? ?? 0,
          outputSize: d['outputSize'] as int?,
          pageCount: d['pageCount'] as int?,
          status: d['status'] as String? ?? 'success',
        );
      }).toList();
    } else {
      final items = _box.values.toList();
      items.sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
      return items.take(_maxLocal).toList();
    }
  }

  Future<void> deleteEntry(String id) async {
    if (_useFirestore) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('history')
          .doc(id)
          .delete();
    } else {
      await _box.delete(id);
    }
  }

  Future<void> clearHistory() async {
    if (_useFirestore) {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('history')
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } else {
      await _box.clear();
    }
  }

  Future<int> localCount() async => _box.length;
}
