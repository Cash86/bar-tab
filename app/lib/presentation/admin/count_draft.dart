import 'dart:convert';

import '../../data/repositories/server_config_repository_impl.dart';

enum CountMode { settlement, opening }

/// Keeps the counts entered so far in the local config store, so they survive
/// the idle logout and an app restart.
class CountDraftStore {
  CountDraftStore(this._store);

  final ConfigStore _store;

  static String _key(CountMode mode) => 'count_draft_${mode.name}';

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

  Future<void> clear(CountMode mode) => _store.delete(_key(mode));
}
