import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_shop/local_database.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LocalDatabase store;
  late String databasePath;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('flutter_shop_test_');
    databasePath = path.join(directory.path, 'test.db');
    store = await LocalDatabase.open(factory: databaseFactoryFfi, databasePath: databasePath);
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('imports legacy menu without overwriting existing items', () async {
    final json = jsonEncode([
      {
        '_id': {'\$oid': 'one'},
        'sid': {'\$numberInt': '2'},
        'type': 'product',
        'row': '1',
        'name': 'A',
        'subName': 'B',
        'price': {'\$numberInt': '35'},
        'disabled': true,
      },
      {
        '_id': {'\$oid': 'two'},
        'sid': {'\$numberInt': '1'},
        'type': 'other',
        'row': '1',
        'name': 'C',
        'subName': '',
        'price': {'\$numberInt': '10'},
        'disabled': false,
      },
    ]);
    expect(await store.seedMenu(source: SeedMenuSource.offline, json: json), isTrue);
    expect(await store.seedMenu(source: SeedMenuSource.cloudConfirmedEmpty, json: json), isFalse);
    final items = await store.menuItems();
    expect(items.map((item) => item['sid']), [1, 2]);
    expect(items.last['legacy_id'], 'one');
    expect(items.last['sub_name'], 'B');
    expect(items.last['price'], 35);
    expect(items.last['is_available'], 0);
    expect(items.last['source'], 'BUNDLED_OFFLINE');
  });

  test('loads the bundled legacy menu', () async {
    expect(await store.seedMenu(source: SeedMenuSource.offline), isTrue);
    final items = await store.menuItems();
    expect(items, isNotEmpty);
    expect(items.every((item) => item['legacy_id'] != null), isTrue);
  });

  test('replaces cached menu with the cloud visible snapshot', () async {
    await store.seedMenu(source: SeedMenuSource.offline);
    await store.replaceVisibleMenu([remoteMenuItem()]);
    final items = await store.menuItems();
    expect(items, hasLength(1));
    expect(items.single['id'], 'cloud-1');
    expect(items.single['sub_name'], '湯');
    expect(items.single['is_available'], 1);
    expect(items.single['source'], 'CLOUD_VISIBLE');
    await store.replaceVisibleMenu([]);
    expect(await store.menuItems(), isEmpty);
    expect(await store.hasVisibleMenuSnapshot(), isTrue);
  });

  test('preserves the prior menu when a snapshot cannot be stored', () async {
    await store.replaceVisibleMenu([remoteMenuItem()]);
    await expectLater(
      store.replaceVisibleMenu([
        remoteMenuItem(),
        {...remoteMenuItem(), 'id': 'cloud-2', 'price': -1},
      ]),
      throwsA(isA<DatabaseException>()),
    );
    expect((await store.menuItems()).single['id'], 'cloud-1');
  });

  test('persists order, snapshots and outbox after reopening', () async {
    await store.createOrder(order: order(), items: [item()], operationId: 'operation-1');
    await store.close();
    store = await LocalDatabase.open(factory: databaseFactoryFfi, databasePath: databasePath);
    expect((await store.database.query('orders')).single['sync_status'], 'PENDING_SYNC');
    expect((await store.database.query('order_items')).single['price'], 35);
    final outbox = (await store.database.query('sync_outbox')).single;
    expect(outbox['operation_id'], 'operation-1');
    expect((jsonDecode(outbox['payload'] as String)['items'] as List).single['name'], 'A');
  });

  test('rolls back order and outbox when an item is invalid', () async {
    await expectLater(
      store.createOrder(order: order(), items: [item(quantity: 0)], operationId: 'operation-1'),
      throwsA(isA<DatabaseException>()),
    );
    expect(await store.database.query('orders'), isEmpty);
    expect(await store.database.query('order_items'), isEmpty);
    expect(await store.database.query('sync_outbox'), isEmpty);
  });

  test('rolls back the order when the outbox insert fails', () async {
    await store.createOrder(order: order(), items: [item()], operationId: 'operation-1');
    await expectLater(
      store.createOrder(
        order: {...order(), 'id': 'order-2'},
        items: [
          {...item(), 'id': 'item-2'},
        ],
        operationId: 'operation-1',
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect(await store.database.query('orders'), hasLength(1));
    expect(await store.database.query('order_items'), hasLength(1));
    expect(await store.database.query('sync_outbox'), hasLength(1));
  });

  test('enforces foreign keys', () async {
    await expectLater(
      store.database.insert('order_items', {...item(), 'order_id': 'missing'}),
      throwsA(isA<DatabaseException>()),
    );
  });
}

Map<String, Object?> order() => {
  'id': 'order-1',
  'takeout': 0,
  'serial': 10,
  'total_price': 35,
  'get_pay': 0,
  'sauerkraut': 0,
  'ginger': 0,
  'chili': 0,
  'order_date': '2026-11-13T10:00:00Z',
  'uber': 0,
  'created_at': '2026-11-13T10:00:00Z',
  'updated_at': '2026-11-13T10:00:00Z',
};

Map<String, Object?> item({int quantity = 1}) => {
  'id': 'item-1',
  'sid': 2,
  'item_type': 'product',
  'name': 'A',
  'show_name': 'A B',
  'price': 35,
  'quantity': quantity,
};

Map<String, dynamic> remoteMenuItem() => {
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
