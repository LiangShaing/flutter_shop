import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

enum SeedMenuSource { cloudConfirmedEmpty, offline }

class LocalDatabase {
  LocalDatabase._(this.database);

  final Database database;
  static const _uuid = Uuid();

  static Future<LocalDatabase> open({DatabaseFactory? factory, String? databasePath}) async {
    final selectedFactory = factory ?? databaseFactory;
    final filePath = databasePath ?? path.join(await selectedFactory.getDatabasesPath(), 'flutter_shop.db');
    final database = await selectedFactory.openDatabase(
      filePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createSchema,
      ),
    );
    return LocalDatabase._(database);
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
