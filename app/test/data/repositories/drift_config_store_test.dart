import 'package:bar_tab/data/db/database.dart';
import 'package:bar_tab/data/repositories/drift_config_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriftConfigStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftConfigStore(db);
  });

  tearDown(() => db.close());

  test('read returns null for an unknown key', () async {
    expect(await store.read('a'), isNull);
  });

  test('write then read round-trips and overwrites', () async {
    await store.write('a', '1');
    expect(await store.read('a'), '1');
    await store.write('a', '2');
    expect(await store.read('a'), '2');
    expect(await store.read('b'), isNull);
  });

  test('delete removes the key', () async {
    await store.write('a', '1');
    await store.delete('a');
    expect(await store.read('a'), isNull);
  });
}
