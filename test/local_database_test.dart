import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_shop/cart_controller.dart';
import 'package:flutter_shop/local_database.dart';
import 'package:flutter_shop/order_draft.dart';
import 'package:flutter_shop/order_options.dart';
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
    await expectLater(store.createOrder(order: order(), items: [item(quantity: 0)], operationId: 'operation-1'), throwsA(isA<DatabaseException>()));
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
    await expectLater(store.database.insert('order_items', {...item(), 'order_id': 'missing'}), throwsA(isA<DatabaseException>()));
  });

  test('uses the Taipei calendar day independently of device timezone', () {
    expect(LocalDatabase.businessDate(DateTime.utc(2026, 11, 12, 15, 59, 59)), '2026-11-12');
    expect(LocalDatabase.businessDate(DateTime.utc(2026, 11, 12, 16)), '2026-11-13');
    expect(LocalDatabase.taipeiTimestamp('2026-11-12T16:00:00Z'), '2026-11-13 00:00:00');
    expect(LocalDatabase.taipeiTimestamp('2026-11-12T16:00:00'), isNull);
  });

  test('upgrades version 1 without inventing legacy spice levels or serial status', () async {
    final oldPath = path.join(directory.path, 'version1.db');
    final oldDatabase = await databaseFactoryFfi.openDatabase(
      oldPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute('CREATE TABLE orders (id TEXT PRIMARY KEY, order_date TEXT NOT NULL, chili INTEGER NOT NULL, serial INTEGER NOT NULL)');
          await database.execute('CREATE TABLE order_items (id TEXT PRIMARY KEY)');
          await database.insert('orders', {'id': 'legacy', 'order_date': '2026-11-12T16:00:00Z', 'chili': 1, 'serial': 10});
          await database.insert('orders', {'id': 'ambiguous', 'order_date': '2026-11-12T16:00:00', 'chili': 0, 'serial': 11});
        },
      ),
    );
    await oldDatabase.close();
    final upgraded = await LocalDatabase.open(factory: databaseFactoryFfi, databasePath: oldPath);
    try {
      final legacy = (await upgraded.database.query('orders', where: 'id = ?', whereArgs: ['legacy'])).single;
      expect(legacy['business_date'], '2026-11-13');
      expect(legacy['chili'], 1);
      expect(legacy['chili_level'], isNull);
      expect(legacy['serial_status'], 'UNKNOWN');
      final ambiguous = (await upgraded.database.query('orders', where: 'id = ?', whereArgs: ['ambiguous'])).single;
      expect(ambiguous['business_date'], isNull);
    } finally {
      await upgraded.close();
    }
  });

  test('upgrades version 2 without guessing old menu identities', () async {
    final oldPath = path.join(directory.path, 'version2.db');
    final oldDatabase = await databaseFactoryFfi.openDatabase(
      oldPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (database, version) async {
          await database.execute('CREATE TABLE order_items (id TEXT PRIMARY KEY, name TEXT NOT NULL)');
          await database.execute('CREATE TABLE orders (id TEXT PRIMARY KEY, serial INTEGER NOT NULL, serial_status TEXT NOT NULL, business_date TEXT)');
          await database.insert('order_items', {'id': 'old-item', 'name': '米粉'});
        },
      ),
    );
    await oldDatabase.close();
    final upgraded = await LocalDatabase.open(factory: databaseFactoryFfi, databasePath: oldPath);
    try {
      final item = (await upgraded.database.query('order_items')).single;
      expect(item['name'], '米粉');
      expect(item['menu_item_id'], isNull);
      expect(item['menu_legacy_id'], isNull);
    } finally {
      await upgraded.close();
    }
  });

  test('upgrades version 3 and preserves only known provisional serials', () async {
    final oldPath = path.join(directory.path, 'version3.db');
    final oldDatabase = await databaseFactoryFfi.openDatabase(
      oldPath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (database, version) async {
          await database.execute('CREATE TABLE orders (id TEXT PRIMARY KEY, serial INTEGER NOT NULL, serial_status TEXT NOT NULL, business_date TEXT)');
          await database.insert('orders', {'id': 'pending', 'serial': 10, 'serial_status': 'PROVISIONAL', 'business_date': '2026-11-13'});
          await database.insert('orders', {'id': 'legacy', 'serial': 11, 'serial_status': 'UNKNOWN', 'business_date': '2026-11-13'});
        },
      ),
    );
    await oldDatabase.close();
    final upgraded = await LocalDatabase.open(factory: databaseFactoryFfi, databasePath: oldPath);
    try {
      final pending = (await upgraded.database.query('orders', where: 'id = ?', whereArgs: ['pending'])).single;
      final legacy = (await upgraded.database.query('orders', where: 'id = ?', whereArgs: ['legacy'])).single;
      expect(pending['provisional_serial'], 10);
      expect(legacy['provisional_serial'], isNull);
      expect((await upgraded.database.query('daily_serial_counters')).single, {'business_date': '2026-11-13', 'last_serial': 11});
    } finally {
      await upgraded.close();
    }
  });

  test('saves an offline selection after cloud identity changes using legacy identity', () async {
    final seed = jsonEncode([
      {
        '_id': {'\$oid': 'legacy-1'},
        'sid': {'\$numberInt': '43'},
        'type': 'mainProduct',
        'row': '2',
        'name': '米粉',
        'subName': '湯',
        'price': {'\$numberInt': '50'},
        'disabled': false,
      },
    ]);
    await store.seedMenu(source: SeedMenuSource.offline, json: seed);
    final draft = await draftFor(store, DateTime.utc(2026, 11, 13));
    final offlineId = draft.items.single.menuId;
    await store.replaceVisibleMenu([remoteMenuItem()]);
    final result = await store.savePendingOrder(draft);
    final detail = (await store.localOrderItems(result.id)).single;
    expect(detail['menu_item_id'], offlineId);
    expect(detail['menu_legacy_id'], 'legacy-1');
  });

  test('saves local official serials, four-level spice, snapshots, and outbox atomically', () async {
    await store.replaceVisibleMenu([remoteMenuItem()]);
    final previousDay = await draftFor(store, DateTime.utc(2026, 11, 12, 15, 59, 59));
    final first = await store.savePendingOrder(previousDay);
    expect(first.serial, 10);
    expect(first.businessDate, '2026-11-12');

    final firstToday = await draftFor(store, DateTime.utc(2026, 11, 12, 16));
    final secondToday = await draftFor(store, DateTime.utc(2026, 11, 12, 16, 1));
    final saved = await Future.wait([store.savePendingOrder(firstToday), store.savePendingOrder(secondToday)]);
    expect(saved.map((order) => order.serial).toSet(), {10, 11});
    expect(saved.every((order) => order.businessDate == '2026-11-13'), isTrue);
    final retried = await store.savePendingOrder(firstToday);
    expect(retried.serial, saved.first.serial);
    expect(await store.database.query('orders'), hasLength(3));
    expect(await store.database.query('order_items'), hasLength(3));
    expect(await store.database.query('sync_outbox'), isEmpty);

    await store.close();
    store = await LocalDatabase.open(factory: databaseFactoryFfi, databasePath: databasePath);
    expect(await store.localOrders(), hasLength(3));
    expect((await store.localOrder(firstToday.id))?['id'], firstToday.id);
    expect(await store.localOrder('missing'), isNull);
    final order = (await store.database.query('orders', where: 'id = ?', whereArgs: [firstToday.id])).single;
    expect(order['sync_status'], 'LOCAL_ONLY');
    expect(order['serial_status'], 'ASSIGNED');
    expect(order['provisional_serial'], isNull);
    expect(order['business_date'], '2026-11-13');
    expect(order['chili'], 1);
    expect(order['chili_level'], 3);
    expect(order['uber'], 1);
    expect(order['takeout'], 0);
    expect(order['sauerkraut'], 0);
    expect(order['get_pay'], 100);
    final detail = (await store.database.query('order_items', where: 'order_id = ?', whereArgs: [firstToday.id])).single;
    expect(detail['show_name'], '湯');
    expect(detail['menu_item_id'], 'cloud-1');
    expect(detail['menu_legacy_id'], 'legacy-1');
    expect(await store.localOrderItems(firstToday.id), hasLength(1));
    expect(detail['price'], 50);
    expect(detail['quantity'], 2);
    expect(await store.pendingOrderOperations(), isEmpty);
    expect(await store.database.query('sync_outbox'), isEmpty);
  });

  test('does not reuse a daily serial after deleting the highest-numbered order', () async {
    await store.replaceVisibleMenu([remoteMenuItem()]);
    final first = await draftFor(store, DateTime.utc(2026, 11, 13));
    final second = await draftFor(store, DateTime.utc(2026, 11, 13, 1));
    expect((await store.savePendingOrder(first)).serial, 10);
    expect((await store.savePendingOrder(second)).serial, 11);
    await store.database.delete('orders', where: 'id = ?', whereArgs: [second.id]);
    final third = await draftFor(store, DateTime.utc(2026, 11, 13, 2));
    expect((await store.savePendingOrder(third)).serial, 12);
    expect((await store.database.query('daily_serial_counters')).single['last_serial'], 12);
  });

  test('rejects changed menu snapshots without creating an order', () async {
    await store.replaceVisibleMenu([remoteMenuItem()]);
    final draft = await draftFor(store, DateTime.utc(2026, 11, 13));
    await store.replaceVisibleMenu([
      {...remoteMenuItem(), 'price': 60},
    ]);
    await expectLater(store.savePendingOrder(draft), throwsA(isA<OrderMenuChangedException>()));
    expect(await store.database.query('orders'), isEmpty);
    expect(await store.database.query('order_items'), isEmpty);
    expect(await store.database.query('sync_outbox'), isEmpty);
  });

  test('preserves a failed operation and commits official serial with outbox removal', () async {
    await store.replaceVisibleMenu([remoteMenuItem()]);
    final draft = await draftFor(store, DateTime.utc(2026, 11, 13));
    final saved = await store.savePendingOrder(draft);
    await promoteToPendingSync(store, draft);
    final before = (await store.pendingOrderOperations()).single;
    await store.recordOrderSyncFailure(draft.operationId, 'NETWORK');
    final pending = (await store.pendingOrderOperations()).single;
    expect(pending['retry_count'], 1);
    expect(pending['last_error'], 'NETWORK');
    expect(pending['payload'], before['payload']);
    expect((await store.localOrders()).single['sync_status'], 'SYNC_FAILED');
    await store.completeOrderSync(operationId: draft.operationId, orderId: draft.id, serial: 14, businessDate: saved.businessDate);
    final order = (await store.localOrders()).single;
    expect(order['serial'], 14);
    expect(order['provisional_serial'], saved.serial);
    expect(order['serial_status'], 'ASSIGNED');
    expect(order['sync_status'], 'SYNCED');
    expect(await store.pendingOrderOperations(), isEmpty);
  });

  test('rejects inconsistent acknowledgements without deleting the pending operation', () async {
    await store.replaceVisibleMenu([remoteMenuItem()]);
    final draft = await draftFor(store, DateTime.utc(2026, 11, 13));
    await store.savePendingOrder(draft);
    await promoteToPendingSync(store, draft);
    for (final (orderId, serial, businessDate) in [('wrong-order', 10, '2026-11-13'), (draft.id, 9, '2026-11-13'), (draft.id, 10, '2026-11-14')]) {
      await expectLater(store.completeOrderSync(operationId: draft.operationId, orderId: orderId, serial: serial, businessDate: businessDate), throwsStateError);
      expect(await store.pendingOrderOperations(), hasLength(1));
      expect((await store.localOrders()).single['serial_status'], 'PROVISIONAL');
    }
  });

  test('rolls back official serial if removing the acknowledged outbox fails', () async {
    await store.replaceVisibleMenu([remoteMenuItem()]);
    final draft = await draftFor(store, DateTime.utc(2026, 11, 13));
    final saved = await store.savePendingOrder(draft);
    await promoteToPendingSync(store, draft);
    await store.database.execute("CREATE TRIGGER reject_outbox_delete BEFORE DELETE ON sync_outbox BEGIN SELECT RAISE(FAIL, 'test'); END");
    await expectLater(store.completeOrderSync(operationId: draft.operationId, orderId: draft.id, serial: 14, businessDate: saved.businessDate), throwsA(isA<DatabaseException>()));
    final order = (await store.localOrders()).single;
    expect(order['serial'], saved.serial);
    expect(order['serial_status'], 'PROVISIONAL');
    expect(order['sync_status'], 'PENDING_SYNC');
    expect(await store.pendingOrderOperations(), hasLength(1));
  });

  test('rolls back the daily counter and order when the order insert fails', () async {
    await store.replaceVisibleMenu([remoteMenuItem()]);
    final draft = await draftFor(store, DateTime.utc(2026, 11, 13));
    await store.database.execute("CREATE TRIGGER reject_order BEFORE INSERT ON orders BEGIN SELECT RAISE(FAIL, 'test'); END");
    await expectLater(store.savePendingOrder(draft), throwsA(isA<DatabaseException>()));
    expect(await store.database.query('orders'), isEmpty);
    expect(await store.database.query('order_items'), isEmpty);
    expect(await store.database.query('sync_outbox'), isEmpty);
    expect(await store.database.query('daily_serial_counters'), isEmpty);
    await store.database.execute('DROP TRIGGER reject_order');
    expect((await store.savePendingOrder(draft)).serial, 10);
  });

  test('does not allocate a number when existing order dates have unknown timezone', () async {
    await store.replaceVisibleMenu([remoteMenuItem()]);
    await store.database.insert('orders', {...order(), 'sync_status': 'PENDING_SYNC'});
    final draft = await draftFor(store, DateTime.utc(2026, 11, 13));
    await expectLater(store.savePendingOrder(draft), throwsA(isA<UnknownOrderDateException>()));
    expect(await store.database.query('orders'), hasLength(1));
    expect(await store.database.query('sync_outbox'), isEmpty);
  });

  test('sorts local orders by their actual instants across UTC offsets', () async {
    await store.createOrder(order: {...order(), 'id': 'earlier', 'order_date': '2026-11-13T10:00:00+08:00'}, items: [item()], operationId: 'earlier-operation');
    await store.createOrder(
      order: {...order(), 'id': 'later', 'order_date': '2026-11-13T03:00:00Z'},
      items: [
        {...item(), 'id': 'later-item'},
      ],
      operationId: 'later-operation',
    );
    expect((await store.localOrders()).map((order) => order['id']), ['later', 'earlier']);
  });
}

Future<OrderDraft> draftFor(LocalDatabase store, DateTime date) async {
  final cart = CartController();
  try {
    cart.setQuantity((await store.menuItems()).single, 2);
    cart.options.setServiceType(ServiceType.uber);
    cart.options.setExcludeSauerkraut(true);
    cart.options.setSpiceLevel(3);
    cart.options.setPaymentInput('100');
    cart.options.setMark('少湯');
    return OrderDraft.fromCart(cart, now: date);
  } finally {
    cart.dispose();
  }
}

Future<void> promoteToPendingSync(LocalDatabase store, OrderDraft draft) => store.database.transaction((transaction) async {
  final order = (await transaction.query('orders', where: 'id = ?', whereArgs: [draft.id])).single;
  final syncOrder = {...order, 'provisional_serial': order['serial'], 'serial_status': 'PROVISIONAL', 'sync_status': 'PENDING_SYNC'};
  await transaction.update('orders', syncOrder, where: 'id = ?', whereArgs: [draft.id]);
  final items = await transaction.query('order_items', where: 'order_id = ?', whereArgs: [draft.id]);
  await transaction.insert('sync_outbox', {
    'operation_id': draft.operationId,
    'order_id': draft.id,
    'operation': 'CREATE',
    'payload': jsonEncode({'order': syncOrder, 'items': items}),
    'created_at': syncOrder['created_at'],
  });
});

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

Map<String, Object?> item({int quantity = 1}) => {'id': 'item-1', 'sid': 2, 'item_type': 'product', 'name': 'A', 'show_name': 'A B', 'price': 35, 'quantity': quantity};

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
