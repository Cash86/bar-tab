import 'dart:convert';

import '../../data/repositories/server_config_repository_impl.dart';

enum CountMode { settlement, opening }

/// Keeps the counts entered so far in the local config store, so they survive
/// the idle logout and an app restart.
class CountDraftStore {
  CountDraftStore(this._store);

  final ConfigStore _store;

  static String _key(CountMode mode) => 'count_draft_${mode.name}';
  static String _periodKey(CountMode mode) => '${_key(mode)}_period';

  /// The saved draft, or null when there is none or it is unreadable.
  Future<Map<String, dynamic>?> load(CountMode mode) async {
    final raw = await _store.read(_key(mode));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> save(CountMode mode, Map<String, dynamic> lines) =>
      _store.write(_key(mode), jsonEncode(lines));

  /// The open period the draft was counted in (null: none was open); a
  /// draft of another period is stale.
  Future<({String? periodId})?> loadPeriod(CountMode mode) async {
    final raw = await _store.read(_periodKey(mode));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final id = decoded['period_id'];
      return id is String? ? (periodId: id) : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> savePeriod(CountMode mode, String? periodId) =>
      _store.write(_periodKey(mode), jsonEncode({'period_id': periodId}));

  Future<void> clear(CountMode mode) async {
    await _store.delete(_key(mode));
    await _store.delete(_periodKey(mode));
  }
}
