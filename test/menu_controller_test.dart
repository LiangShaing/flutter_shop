import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_shop/local_database.dart';
import 'package:flutter_shop/menu_controller.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('classifies realtime errors without returning their content', () {
    expect(classifyRealtimeError(Exception('JWT expired secret-value')), 'token');
    expect(classifyRealtimeError(Exception('permission denied secret-value')), 'permission');
    expect(classifyRealtimeError(Exception('replication failure secret-value')), 'database_subscription');
    expect(classifyRealtimeError(Exception('unrecognized secret-value')), 'unclassified');
  });

  test('verbose realtime diagnostics are opt-in and redact common secrets', () {
    final lines = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => lines.add(message ?? '');
    try {
      final error = Exception(
        'failure https://example.com?token=hidden sb_secret_hidden '
        'eyJabc.def.ghi Bearer bearerSecret password=passSecret',
      );
      logRealtimeError(error, verbose: false);
      expect(lines, isEmpty);
      logRealtimeError(error, verbose: true);
      expect(lines, hasLength(1));
      expect(lines.single, contains('failure'));
      for (final secret in ['example.com', 'sb_secret_hidden', 'eyJabc.def.ghi', 'bearerSecret', 'passSecret']) {
        expect(lines.single, isNot(contains(secret)));
      }
    } finally {
      debugPrint = previousDebugPrint;
    }
  });

  late Directory directory;
  late LocalDatabase store;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('menu_controller_');
    store = await LocalDatabase.open(factory: databaseFactoryFfi, databasePath: path.join(directory.path, 'test.db'));
  });
  tearDown(() async {
    if (store.database.isOpen) await store.close();
    await directory.delete(recursive: true);
  });

  test('shows cached data before a successful remote refresh', () async {
    await store.seedMenu(source: SeedMenuSource.offline);
    final response = Completer<List<Map<String, dynamic>>>();
    final controller = MenuController(store: store, fetchVisibleMenu: () => response.future);
    final started = Completer<void>();
    controller.addListener(() {
      if (controller.state == MenuSyncState.syncing && !started.isCompleted) started.complete();
    });
    final initialization = controller.initialize();
    await started.future;
    expect(controller.items, isNotEmpty);
    expect(controller.items.first['source'], 'BUNDLED_OFFLINE');
    response.complete([remoteItem()]);
    await initialization;
    expect(controller.state, MenuSyncState.synced);
    expect(controller.items.single['name'], '米粉');
    await controller.close();
  });

  test('preserves cache when network fails and retries successfully', () async {
    await store.replaceVisibleMenu([remoteItem()]);
    var failing = true;
    final controller = MenuController(
      store: store,
      fetchVisibleMenu: () async {
        if (failing) throw Exception('offline');
        return [];
      },
    );
    await controller.initialize();
    expect(controller.state, MenuSyncState.failed);
    expect(controller.items.single['name'], '米粉');
    failing = false;
    await controller.refresh();
    expect(controller.state, MenuSyncState.synced);
    expect(controller.items, isEmpty);
    await controller.close();
  });

  test('does not seed defaults after a successful empty cloud snapshot', () async {
    await store.replaceVisibleMenu([]);
    final controller = MenuController(store: store, fetchVisibleMenu: () async => throw Exception('offline'));
    await controller.initialize();
    expect(controller.items, isEmpty);
    expect(controller.state, MenuSyncState.failed);
    await controller.close();
  });

  test('runs another refresh when a change arrives during fetch', () async {
    final first = Completer<List<Map<String, dynamic>>>();
    var calls = 0;
    final controller = MenuController(
      store: store,
      fetchVisibleMenu: () {
        calls++;
        return calls == 1 ? first.future : Future.value([remoteItem()]);
      },
    );
    final started = Completer<void>();
    controller.addListener(() {
      if (controller.state == MenuSyncState.syncing && !started.isCompleted) started.complete();
    });
    final initialization = controller.initialize();
    await started.future;
    controller.refresh();
    first.complete([]);
    await initialization;
    expect(calls, 2);
    expect(controller.items.single['name'], '米粉');
    await controller.close();
  });

  test('logs failure type and code without error details', () async {
    final lines = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => lines.add(message ?? '');
    try {
      final controller = MenuController(
        store: store,
        fetchVisibleMenu: () async =>
            throw const PostgrestException(message: 'private menu data', details: 'private details', code: '42501'),
      );
      await controller.initialize();
      expect(lines.any((line) => line.contains('refresh failed type=PostgrestException code=42501')), isTrue);
      expect(lines.any((line) => line.contains('private')), isFalse);
      await controller.close();
    } finally {
      debugPrint = previousDebugPrint;
    }
  });
}

Map<String, dynamic> remoteItem() => {
  'id': 'cloud-1',
  'legacy_id': 'legacy-1',
  'sid': 43,
  'item_type': 'mainProduct',
  'menu_row': '2',
  'name': '米粉',
  'display_name': '湯',
  'price': 50,
  'is_available': true,
};
