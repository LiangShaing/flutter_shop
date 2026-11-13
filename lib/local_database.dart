import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;
import 'package:uuid/uuid.dart';

import 'order_draft.dart';
import 'order_options.dart';

enum SeedMenuSource { cloudConfirmedEmpty, offline }

class OrderMenuChangedException implements Exception {}

class UnknownOrderDateException implements Exception {}

class SavedOrder {
  const SavedOrder({required this.id, required this.serial, required this.businessDate});

  final String id;
  final int serial;
  final String businessDate;
}

class LocalDatabase {
  LocalDatabase._(this.database);

  final Database database;
  static const _uuid = Uuid();
  static final timezone.Location _taipei = () {
    timezone_data.initializeTimeZones();
    return timezone.getLocation('Asia/Taipei');
  }();

  static String businessDate(DateTime instant) {
    final date = timezone.TZDateTime.from(instant, _taipei);
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static String? taipeiTimestamp(String? rawDate) {
    if (rawDate == null || !RegExp(r'(Z|[+-]\d{2}:\d{2})$', caseSensitive: false).hasMatch(rawDate)) return null;
    final instant = DateTime.tryParse(rawDate);
    if (instant == null) return null;
    final date = timezone.TZDateTime.from(instant, _taipei);
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${businessDate(instant)} ${twoDigits(date.hour)}:${twoDigits(date.minute)}:${twoDigits(date.second)}';
  }

  static Future<LocalDatabase> open({DatabaseFactory? factory, String? databasePath}) async {
    final selectedFactory = factory ?? databaseFactory;
    final filePath = databasePath ?? path.join(await selectedFactory.getDatabasesPath(), 'flutter_shop.db');
    final database = await selectedFactory.openDatabase(
      filePath,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (database, version) async {
          await _createSchema(database, version);
          await _migrateToVersion2(database);
          await _migrateToVersion3(database);
          await _migrateToVersion4(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) await _migrateToVersion2(database);
          if (oldVersion < 3) await _migrateToVersion3(database);
          if (oldVersion < 4) await _migrateToVersion4(database);
        },
      ),
    );
    return LocalDatabase._(database);
  }

  static Future<void> _migrateToVersion2(Database database) async {
    await database.execute('ALTER TABLE orders ADD COLUMN chili_level INTEGER CHECK (chili_level BETWEEN 0 AND 3)');
    await database.execute('ALTER TABLE orders ADD COLUMN business_date TEXT');
    await database.execute(
      "ALTER TABLE orders ADD COLUMN serial_status TEXT NOT NULL DEFAULT 'UNKNOWN' "
      "CHECK (serial_status IN ('UNKNOWN', 'PROVISIONAL', 'ASSIGNED'))",
    );
    final orders = await database.query('orders', columns: ['id', 'order_date']);
    for (final order in orders) {
      final rawDate = order['order_date'] as String;
      if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$', caseSensitive: false).hasMatch(rawDate)) continue;
      final instant = DateTime.tryParse(rawDate);
      if (instant == null) continue;
      await database.update(
        'orders',
        {'business_date': businessDate(instant)},
        where: 'id = ?',
        whereArgs: [order['id']],
      );
    }
    await database.execute('CREATE INDEX orders_business_date_serial_idx ON orders(business_date, serial)');
  }

  static Future<void> _migrateToVersion3(Database database) async {
    await database.execute('ALTER TABLE order_items ADD COLUMN menu_item_id TEXT');
    await database.execute('ALTER TABLE order_items ADD COLUMN menu_legacy_id TEXT');
  }

  static Future<void> _migrateToVersion4(Database database) async {
    await database.execute('ALTER TABLE orders ADD COLUMN provisional_serial INTEGER');
    await database.execute("UPDATE orders SET provisional_serial = serial WHERE serial_status = 'PROVISIONAL'");
  }

  static Future<void> _createSchema(Database database, int version) async {
    await database.execute('''
      CREATE TABLE menu_items (
        id TEXT PRIMARY KEY, legacy_id TEXT, sid INTEGER NOT NULL,
        item_type TEXT NOT NULL, menu_row TEXT NOT NULL, name TEXT NOT NULL,
        sub_name TEXT NOT NULL, price INTEGER NOT NULL CHECK (price >= 0),
        is_available INTEGER NOT NULL CHECK (is_available IN (0, 1)),
        source TEXT NOT NULL, remote_updated_at TEXT
      )
    ''');
    await database.execute('''
      CREATE TABLE orders (
        id TEXT PRIMARY KEY, legacy_id TEXT, takeout INTEGER NOT NULL,
        serial INTEGER NOT NULL, total_price INTEGER NOT NULL,
        get_pay INTEGER NOT NULL, sauerkraut INTEGER NOT NULL,
        ginger INTEGER NOT NULL, chili INTEGER NOT NULL,
        order_date TEXT NOT NULL, uber INTEGER NOT NULL, mark TEXT,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE order_items (
        id TEXT PRIMARY KEY, legacy_id TEXT,
        order_id TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        sid INTEGER NOT NULL, item_type TEXT NOT NULL, name TEXT NOT NULL,
        show_name TEXT NOT NULL, price INTEGER NOT NULL,
        quantity INTEGER CHECK (quantity IS NULL OR quantity > 0)
      )
    ''');
    await database.execute('''
      CREATE TABLE sync_outbox (
        operation_id TEXT PRIMARY KEY, order_id TEXT NOT NULL,
        operation TEXT NOT NULL, payload TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0, last_error TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE sync_metadata (
        collection TEXT PRIMARY KEY, last_synced_at TEXT, version TEXT
      )
    ''');
    await database.execute('CREATE INDEX menu_order_idx ON menu_items(menu_row, sid)');
    await database.execute('CREATE INDEX order_items_order_idx ON order_items(order_id)');
    await database.execute('CREATE INDEX orders_date_idx ON orders(order_date)');
    await database.execute('CREATE INDEX outbox_created_idx ON sync_outbox(created_at)');
  }

  Future<bool> seedMenu({required SeedMenuSource source, String? json}) async {
    final contents = json ?? await rootBundle.loadString('assets/data/shopMenuItem.json');
    final entries = jsonDecode(contents) as List<dynamic>;
    final items = entries.map((entry) {
      final item = entry as Map<String, dynamic>;
      final legacyId = (item['_id'] as Map<String, dynamic>)['\$oid'] as String;
      int number(String key) => int.parse((item[key] as Map<String, dynamic>)['\$numberInt'] as String);
      return <String, Object?>{
        'id': _uuid.v5(Namespace.url.value, 'flutter-shop:menu:$legacyId'),
        'legacy_id': legacyId,
        'sid': number('sid'),
        'item_type': item['type'] as String,
        'menu_row': item['row'] as String,
        'name': item['name'] as String,
        'sub_name': item['subName'] as String,
        'price': number('price'),
        'is_available': (item['disabled'] as bool) ? 0 : 1,
        'source': source == SeedMenuSource.offline ? 'BUNDLED_OFFLINE' : 'BUNDLED',
      };
    }).toList();

    return database.transaction((transaction) async {
      final count = Sqflite.firstIntValue(await transaction.rawQuery('SELECT COUNT(*) FROM menu_items'));
      if (count != 0) return false;
      for (final item in items) {
        await transaction.insert('menu_items', item);
      }
      return true;
    });
  }

  Future<List<Map<String, Object?>>> menuItems() => database.query('menu_items', orderBy: 'menu_row ASC, sid ASC');

  Future<void> replaceVisibleMenu(List<Map<String, dynamic>> remoteItems) async {
    final items = remoteItems
        .map(
          (item) => <String, Object?>{
            'id': item['id'] as String,
            'legacy_id': item['legacy_id'] as String?,
            'sid': item['sid'] as int,
            'item_type': item['item_type'] as String,
            'menu_row': item['menu_row'] as String,
            'name': item['name'] as String,
            'sub_name': item['display_name'] as String,
            'price': item['price'] as int,
            'is_available': (item['is_available'] as bool) ? 1 : 0,
            'source': 'CLOUD_VISIBLE',
          },
        )
        .toList();
    await database.transaction((transaction) async {
      await transaction.delete('menu_items');
      for (final item in items) {
        await transaction.insert('menu_items', item);
      }
      await transaction.insert('sync_metadata', {
        'collection': 'visible_menu',
        'last_synced_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<bool> hasVisibleMenuSnapshot() async =>
      (await database.query('sync_metadata', where: 'collection = ?', whereArgs: ['visible_menu'])).isNotEmpty;

  Future<List<Map<String, Object?>>> localOrders() =>
      database.query('orders', orderBy: 'datetime(order_date) DESC, rowid DESC');

  Future<Map<String, Object?>?> localOrder(String orderId) async {
    final orders = await database.query('orders', where: 'id = ?', whereArgs: [orderId], limit: 1);
    return orders.isEmpty ? null : orders.single;
  }

  Future<List<Map<String, Object?>>> localOrderItems(String orderId) =>
      database.query('order_items', where: 'order_id = ?', whereArgs: [orderId], orderBy: 'rowid ASC');

  Future<List<Map<String, Object?>>> pendingOrderOperations() => database.query(
    'sync_outbox',
    where: 'operation = ?',
    whereArgs: ['CREATE'],
    orderBy: 'created_at ASC, rowid ASC',
  );

  Future<void> recordOrderSyncFailure(String operationId, String errorCode) =>
      database.transaction((transaction) async {
        final operations = await transaction.query('sync_outbox', where: 'operation_id = ?', whereArgs: [operationId]);
        if (operations.length != 1) throw StateError('Pending operation not found');
        final operation = operations.single;
        await transaction.update(
          'sync_outbox',
          {'retry_count': (operation['retry_count'] as int) + 1, 'last_error': errorCode},
          where: 'operation_id = ?',
          whereArgs: [operationId],
        );
        final changed = await transaction.update(
          'orders',
          {'sync_status': 'SYNC_FAILED'},
          where: 'id = ? AND sync_status IN (?, ?)',
          whereArgs: [operation['order_id'], 'PENDING_SYNC', 'SYNC_FAILED'],
        );
        if (changed != 1) throw StateError('Pending order not found');
      });

  Future<void> completeOrderSync({
    required String operationId,
    required String orderId,
    required int serial,
    required String businessDate,
  }) => database.transaction((transaction) async {
    if (serial < 10) throw StateError('Invalid official serial');
    final operations = await transaction.query('sync_outbox', where: 'operation_id = ?', whereArgs: [operationId]);
    if (operations.length != 1 ||
        operations.single['order_id'] != orderId ||
        operations.single['operation'] != 'CREATE') {
      throw StateError('Pending operation mismatch');
    }
    final updated = await transaction.update(
      'orders',
      {'serial': serial, 'serial_status': 'ASSIGNED', 'sync_status': 'SYNCED'},
      where: 'id = ? AND business_date = ? AND serial_status = ? AND sync_status IN (?, ?)',
      whereArgs: [orderId, businessDate, 'PROVISIONAL', 'PENDING_SYNC', 'SYNC_FAILED'],
    );
    if (updated != 1) throw StateError('Pending order or business date mismatch');
    final deleted = await transaction.delete('sync_outbox', where: 'operation_id = ?', whereArgs: [operationId]);
    if (deleted != 1) throw StateError('Pending operation could not be removed');
  });

  Future<SavedOrder> savePendingOrder(OrderDraft draft) => database.transaction((transaction) async {
    final existing = await transaction.query('sync_outbox', where: 'operation_id = ?', whereArgs: [draft.operationId]);
    if (existing.isNotEmpty) {
      if (existing.single['order_id'] != draft.id) throw StateError('Operation belongs to another order');
      final orders = await transaction.query('orders', where: 'id = ?', whereArgs: [draft.id]);
      if (orders.length != 1) throw StateError('Outbox order is missing');
      final order = orders.single;
      return SavedOrder(id: draft.id, serial: order['serial'] as int, businessDate: order['business_date'] as String);
    }

    final unknownDates = Sqflite.firstIntValue(
      await transaction.rawQuery('SELECT COUNT(*) FROM orders WHERE business_date IS NULL'),
    );
    if (unknownDates != 0) throw UnknownOrderDateException();

    for (final item in draft.items) {
      final menuItems = await transaction.query(
        'menu_items',
        where: item.menuLegacyId == null ? 'id = ?' : 'legacy_id = ?',
        whereArgs: [item.menuLegacyId ?? item.menuId],
      );
      if (menuItems.length != 1) throw OrderMenuChangedException();
      final current = menuItems.single;
      if (current['is_available'] != 1 ||
          current['sid'] != item.sid ||
          current['item_type'] != item.itemType ||
          current['name'] != item.name ||
          current['sub_name'] != item.subName ||
          current['price'] != item.price) {
        throw OrderMenuChangedException();
      }
    }

    final day = businessDate(draft.orderDate);
    final maximum = Sqflite.firstIntValue(
      await transaction.rawQuery('SELECT MAX(serial) FROM orders WHERE business_date = ?', [day]),
    );
    if (maximum == 0x7fffffffffffffff) throw StateError('Serial number limit reached');
    final serial = maximum == null || maximum < 10 ? 10 : maximum + 1;
    final timestamp = draft.orderDate.toIso8601String();
    final order = <String, Object?>{
      'id': draft.id,
      'takeout': draft.serviceType == ServiceType.takeout ? 1 : 0,
      'uber': draft.serviceType == ServiceType.uber ? 1 : 0,
      'serial': serial,
      'provisional_serial': serial,
      'serial_status': 'PROVISIONAL',
      'business_date': day,
      'total_price': draft.total,
      'get_pay': draft.receivedAmount,
      'sauerkraut': draft.sauerkraut ? 1 : 0,
      'ginger': draft.ginger ? 1 : 0,
      'chili': draft.spiceLevel > 0 ? 1 : 0,
      'chili_level': draft.spiceLevel,
      'order_date': timestamp,
      'mark': draft.mark,
      'created_at': timestamp,
      'updated_at': timestamp,
      'sync_status': 'PENDING_SYNC',
    };
    final items = draft.items
        .map(
          (item) => <String, Object?>{
            'id': item.id,
            'order_id': draft.id,
            'menu_item_id': item.menuId,
            'menu_legacy_id': item.menuLegacyId,
            'sid': item.sid,
            'item_type': item.itemType,
            'name': item.name,
            'show_name': item.subName,
            'price': item.price,
            'quantity': item.quantity,
          },
        )
        .toList();
    await transaction.insert('orders', order);
    for (final item in items) {
      await transaction.insert('order_items', item);
    }
    await transaction.insert('sync_outbox', {
      'operation_id': draft.operationId,
      'order_id': draft.id,
      'operation': 'CREATE',
      'payload': jsonEncode({'order': order, 'items': items}),
      'created_at': timestamp,
    });
    return SavedOrder(id: draft.id, serial: serial, businessDate: day);
  });

  Future<void> createOrder({
    required Map<String, Object?> order,
    required List<Map<String, Object?>> items,
    required String operationId,
  }) async {
    final orderId = order['id'] as String;
    final createdAt = order['created_at'] as String;
    final pendingOrder = {...order, 'sync_status': 'PENDING_SYNC'};
    final snapshots = items.map((item) => {...item, 'order_id': orderId}).toList();
    await database.transaction((transaction) async {
      await transaction.insert('orders', pendingOrder);
      for (final item in snapshots) {
        await transaction.insert('order_items', item);
      }
      await transaction.insert('sync_outbox', {
        'operation_id': operationId,
        'order_id': orderId,
        'operation': 'CREATE',
        'payload': jsonEncode({'order': pendingOrder, 'items': snapshots}),
        'created_at': createdAt,
      });
    });
  }

  Future<void> close() => database.close();
}
