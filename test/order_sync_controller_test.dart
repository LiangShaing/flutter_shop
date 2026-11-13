import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_shop/cart_controller.dart';
import 'package:flutter_shop/local_database.dart';
import 'package:flutter_shop/order_draft.dart';
import 'package:flutter_shop/order_options.dart';
import 'package:flutter_shop/order_sync_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late LocalDatabase store;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('order_sync_test_');
    store = await LocalDatabase.open(factory: databaseFactoryFfi, databasePath: path.join(directory.path, 'test.db'));
    await store.replaceVisibleMenu([
      {
        'id': '22222222-2222-4222-8222-222222222222',
        'legacy_id': 'legacy-1',
        'sid': 43,
        'item_type': 'mainProduct',
        'menu_row': '2',
        'name': '米粉',
        'display_name': '湯',
        'price': 50,
        'is_available': true,
      },
    ]);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('does not upload or mark failure without a merchant session', () async {
    await createPending(store);
    var calls = 0;
    final sync = OrderSyncController(
      store: store,
      hasSession: () => false,
      submitOrder: (id, payload) async {
        calls++;
        return acknowledgement(id, payload, 10);
      },
    );
    await sync.sync();
    expect(sync.state, OrderSyncState.authRequired);
    expect(sync.pendingCount, 1);
    expect(calls, 0);
    expect((await store.localOrders()).single['sync_status'], 'PENDING_SYNC');
    expect((await store.pendingOrderOperations()).single['retry_count'], 0);
    await sync.close();
  });

  test('resumes pending uploads after a session becomes available', () async {
    await createPending(store);
    var signedIn = false;
    var calls = 0;
    final sync = OrderSyncController(
      store: store,
      hasSession: () => signedIn,
      submitOrder: (id, payload) async {
        calls++;
        return acknowledgement(id, payload, 10);
      },
    );
    await sync.sync();
    expect(sync.state, OrderSyncState.authRequired);
    signedIn = true;
    await sync.sync(authorizationChanged: true);
    expect(calls, 1);
    expect(sync.state, OrderSyncState.idle);
    expect(await store.pendingOrderOperations(), isEmpty);
    await sync.close();
  });

  test('does not repeatedly retry a rejected merchant until explicitly retried', () async {
    await createPending(store);
    var authorized = false;
    var calls = 0;
    final sync = OrderSyncController(
      store: store,
      hasSession: () => true,
      submitOrder: (id, payload) async {
        calls++;
        if (!authorized) throw const PostgrestException(message: 'MERCHANT_AUTH_REQUIRED', code: '42501');
        return acknowledgement(id, payload, 10);
      },
    );
    await sync.sync();
    expect(sync.state, OrderSyncState.authRequired);
    expect((await store.pendingOrderOperations()).single['last_error'], 'AUTHORIZATION');
    await sync.sync();
    expect(calls, 1);
    authorized = true;
    await sync.sync(authorizationChanged: true);
    expect(calls, 2);
    expect(await store.pendingOrderOperations(), isEmpty);
    await sync.close();
  });

  test('uploads in order and applies confirmed serials', () async {
    final first = await createPending(store, minute: 0);
    final second = await createPending(store, minute: 1);
    final received = <String>[];
    final sync = OrderSyncController(
      store: store,
      hasSession: () => true,
      submitOrder: (id, payload) async {
        received.add(id);
        return acknowledgement(id, payload, 20 + received.length);
      },
    );
    await sync.sync();
    expect(received, [first.operationId, second.operationId]);
    expect(sync.state, OrderSyncState.idle);
    expect(sync.pendingCount, 0);
    expect(await store.pendingOrderOperations(), isEmpty);
    final orders = await store.localOrders();
    expect(orders.every((order) => order['sync_status'] == 'SYNCED' && order['serial_status'] == 'ASSIGNED'), isTrue);
    expect(orders.map((order) => order['serial']).toSet(), {21, 22});
    await sync.close();
  });

  test('retains the original operation after timeout and safely retries it', () async {
    final first = await createPending(store, minute: 0);
    await createPending(store, minute: 1);
    final attempts = <String>[];
    var fail = true;
    final sync = OrderSyncController(
      store: store,
      hasSession: () => true,
      submitOrder: (id, payload) async {
        attempts.add('$id:${jsonEncode(payload)}');
        if (fail) throw TimeoutException('network');
        return acknowledgement(id, payload, attempts.length + 9);
      },
    );
    final original = (await store.pendingOrderOperations()).first;
    await sync.sync();
    expect(sync.state, OrderSyncState.failed);
    expect(attempts, hasLength(1));
    final pending = await store.pendingOrderOperations();
    expect(pending, hasLength(2));
    expect(pending.first['operation_id'], first.operationId);
    expect(pending.first['retry_count'], 1);
    expect(pending.first['payload'], original['payload']);
    fail = false;
    await sync.sync();
    expect(attempts[1], attempts[0]);
    expect(await store.pendingOrderOperations(), isEmpty);
    expect(sync.state, OrderSyncState.idle);
    await sync.close();
  });

  test('recovers the same official serial when a committed server response is lost', () async {
    final draft = await createPending(store);
    final committed = <String, Map<String, dynamic>>{};
    var loseResponse = true;
    final sync = OrderSyncController(
      store: store,
      hasSession: () => true,
      submitOrder: (id, payload) async {
        final result = committed.putIfAbsent(id, () => acknowledgement(id, payload, 17));
        if (loseResponse) {
          loseResponse = false;
          throw TimeoutException('response lost after commit');
        }
        return result;
      },
    );
    await sync.sync();
    expect(committed.keys, [draft.operationId]);
    expect((await store.localOrders()).single['serial_status'], 'PROVISIONAL');
    expect(await store.pendingOrderOperations(), hasLength(1));
    await sync.sync();
    expect(committed, hasLength(1));
    final order = (await store.localOrders()).single;
    expect(order['serial'], 17);
    expect(order['provisional_serial'], 10);
    expect(order['sync_status'], 'SYNCED');
    expect(await store.pendingOrderOperations(), isEmpty);
    await sync.close();
  });

  test('holds conflicts for review without automatically retrying or dropping later orders', () async {
    await createPending(store, minute: 0);
    await createPending(store, minute: 1);
    var calls = 0;
    var conflict = true;
    final sync = OrderSyncController(
      store: store,
      hasSession: () => true,
      submitOrder: (id, payload) async {
        calls++;
        if (conflict) throw const PostgrestException(message: 'MENU_CONFLICT', code: 'P0001');
        return acknowledgement(id, payload, calls + 9);
      },
    );
    await sync.sync();
    expect(sync.state, OrderSyncState.needsReview);
    expect(sync.lastErrorCode, 'MENU_CONFLICT');
    expect((await store.pendingOrderOperations()).first['last_error'], 'MENU_CONFLICT');
    await sync.sync();
    expect(calls, 1);
    expect(await store.pendingOrderOperations(), hasLength(2));
    await sync.sync(authorizationChanged: true);
    expect(calls, 1);
    conflict = false;
    await sync.sync(manual: true);
    expect(calls, 3);
    expect(await store.pendingOrderOperations(), isEmpty);
    await sync.close();
  });

  test('rejects mismatched acknowledgements and preserves provisional order', () async {
    await createPending(store);
    final sync = OrderSyncController(
      store: store,
      hasSession: () => true,
      submitOrder: (id, payload) async => {...acknowledgement(id, payload, 10), 'business_date': '2026-11-14'},
    );
    await sync.sync();
    expect(sync.state, OrderSyncState.needsReview);
    expect(sync.lastErrorCode, 'INVALID_RESPONSE');
    expect(await store.pendingOrderOperations(), hasLength(1));
    expect((await store.localOrders()).single['serial_status'], 'PROVISIONAL');
    await sync.close();
  });

  test('holds externally changed cloud orders for review', () async {
    await createPending(store);
    var calls = 0;
    final sync = OrderSyncController(
      store: store,
      hasSession: () => true,
      submitOrder: (id, payload) async {
        calls++;
        throw const PostgrestException(message: 'SERVER_ORDER_CHANGED', code: 'P0001');
      },
    );
    await sync.sync();
    expect(sync.state, OrderSyncState.needsReview);
    expect(sync.lastErrorCode, 'INVALID_ORDER');
    await sync.sync();
    expect(calls, 1);
    expect(await store.pendingOrderOperations(), hasLength(1));
    expect((await store.localOrders()).single['serial_status'], 'PROVISIONAL');
    await sync.close();
  });

  test('coalesces overlapping sync requests', () async {
    await createPending(store);
    final entered = Completer<void>();
    final response = Completer<Map<String, dynamic>>();
    var calls = 0;
    late String operationId;
    late Map<String, dynamic> payload;
    final sync = OrderSyncController(
      store: store,
      hasSession: () => true,
      submitOrder: (id, body) {
        calls++;
        operationId = id;
        payload = body;
        entered.complete();
        return response.future;
      },
    );
    final first = sync.sync();
    await entered.future;
    final second = sync.sync();
    response.complete(acknowledgement(operationId, payload, 10));
    await Future.wait([first, second]);
    expect(calls, 1);
    expect(await store.pendingOrderOperations(), isEmpty);
    await sync.close();
  });

  test('syncs an order saved while an earlier operation is in flight', () async {
    final firstDraft = await createPending(store);
    final entered = Completer<void>();
    final response = Completer<Map<String, dynamic>>();
    late Map<String, dynamic> firstPayload;
    final operationIds = <String>[];
    final sync = OrderSyncController(
      store: store,
      hasSession: () => true,
      submitOrder: (id, body) {
        operationIds.add(id);
        if (operationIds.length == 1) {
          firstPayload = body;
          entered.complete();
          return response.future;
        }
        return Future.value(acknowledgement(id, body, 11));
      },
    );
    final firstRequest = sync.sync();
    await entered.future;
    final secondDraft = await createPending(store, minute: 1);
    final secondRequest = sync.sync();
    response.complete(acknowledgement(firstDraft.operationId, firstPayload, 10));
    await Future.wait([firstRequest, secondRequest]);
    expect(operationIds, [firstDraft.operationId, secondDraft.operationId]);
    expect(await store.pendingOrderOperations(), isEmpty);
    await sync.close();
  });

  test('honors one explicit retry requested while an earlier upload is failing', () async {
    await createPending(store);
    final entered = Completer<void>();
    final firstResponse = Completer<Map<String, dynamic>>();
    var calls = 0;
    final sync = OrderSyncController(
      store: store,
      hasSession: () => true,
      submitOrder: (id, body) {
        calls++;
        if (calls == 1) {
          entered.complete();
          return firstResponse.future;
        }
        return Future.value(acknowledgement(id, body, 10));
      },
    );
    final first = sync.sync();
    await entered.future;
    final retry = sync.sync(manual: true);
    firstResponse.completeError(const PostgrestException(message: 'MENU_CONFLICT', code: 'P0001'));
    await Future.wait([first, retry]);
    expect(calls, 2);
    expect(sync.state, OrderSyncState.idle);
    expect(await store.pendingOrderOperations(), isEmpty);
    await sync.close();
  });

  test('sends the stable operation and payload through the Supabase RPC client', () async {
    final draft = await createPending(store);
    final operation = (await store.pendingOrderOperations()).single;
    final payload = jsonDecode(operation['payload'] as String) as Map<String, dynamic>;
    http.Request? captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(acknowledgement(draft.operationId, payload, 10)),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    });
    final client = SupabaseClient(
      'https://example.test',
      'test-publishable-key',
      httpClient: mock,
      accessToken: () async => 'test-session-token',
    );
    addTearDown(() async {
      await client.dispose();
      mock.close();
    });
    final result = await submitMerchantOrder(client, draft.operationId, payload);
    expect(captured?.method, 'POST');
    expect(captured?.url.path, '/rest/v1/rpc/submit_merchant_order');
    expect(captured?.headers['authorization'], 'Bearer test-session-token');
    expect(jsonDecode(captured!.body), {'p_operation_id': draft.operationId, 'p_payload': payload});
    expect(result, acknowledgement(draft.operationId, payload, 10));
  });
}

Future<OrderDraft> createPending(LocalDatabase store, {int minute = 0}) async {
  final cart = CartController();
  try {
    cart.add((await store.menuItems()).single);
    cart.options.setServiceType(ServiceType.dineIn);
    final draft = OrderDraft.fromCart(cart, now: DateTime.utc(2026, 11, 13, 1, minute));
    await store.savePendingOrder(draft);
    return draft;
  } finally {
    cart.dispose();
  }
}

Map<String, dynamic> acknowledgement(String operationId, Map<String, dynamic> payload, int serial) => {
  'operation_id': operationId,
  'order_id': (payload['order'] as Map<String, dynamic>)['id'],
  'business_date': (payload['order'] as Map<String, dynamic>)['business_date'],
  'serial': serial,
};
