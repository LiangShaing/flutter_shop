import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_database.dart';

enum OrderSyncState { loading, idle, syncing, authRequired, failed, needsReview }

typedef SubmitOrder = Future<Map<String, dynamic>> Function(String operationId, Map<String, dynamic> payload);

class OrderSyncController extends ChangeNotifier {
  OrderSyncController({required this.store, required this.hasSession, required this.submitOrder});

  final LocalDatabase store;
  final bool Function() hasSession;
  final SubmitOrder submitOrder;
  OrderSyncState state = OrderSyncState.loading;
  int pendingCount = 0;
  String? lastErrorCode;
  Future<void>? _running;
  bool _requested = false;
  bool _manualRequested = false;
  bool _authorizationChanged = false;
  bool _closed = false;

  Future<void> sync({bool manual = false, bool authorizationChanged = false}) {
    if (_closed) return Future.value();
    _requested = true;
    _manualRequested |= manual;
    _authorizationChanged |= authorizationChanged;
    final running = _running;
    if (running != null) return running;
    final future = _drain();
    _running = future;
    return future.whenComplete(() => _running = null);
  }

  Future<void> _drain() async {
    try {
      syncLoop:
      do {
        _requested = false;
        final manual = _manualRequested;
        _manualRequested = false;
        final authorizationChanged = _authorizationChanged;
        _authorizationChanged = false;
        final operations = await store.pendingOrderOperations();
        pendingCount = operations.length;
        if (operations.isEmpty) {
          state = OrderSyncState.idle;
          lastErrorCode = null;
          _notify();
          continue;
        }
        if (!hasSession()) {
          state = OrderSyncState.authRequired;
          _notify();
          return;
        }
        state = OrderSyncState.syncing;
        _notify();
        for (final operation in operations) {
          if (_closed) return;
          if (!hasSession()) {
            state = OrderSyncState.authRequired;
            _notify();
            return;
          }
          final previousError = operation['last_error'] as String?;
          if (!manual && !authorizationChanged && previousError == 'AUTHORIZATION') {
            lastErrorCode = previousError;
            state = OrderSyncState.authRequired;
            _notify();
            return;
          }
          if (!manual && _needsReview(previousError)) {
            lastErrorCode = previousError;
            state = OrderSyncState.needsReview;
            _notify();
            return;
          }
          final operationId = operation['operation_id'] as String;
          final orderId = operation['order_id'] as String;
          try {
            final decoded = jsonDecode(operation['payload'] as String);
            if (decoded is! Map<String, dynamic> || decoded['order'] is! Map<String, dynamic>) {
              throw const FormatException('Invalid local payload');
            }
            final businessDate = (decoded['order'] as Map<String, dynamic>)['business_date'];
            final result = await submitOrder(operationId, decoded).timeout(const Duration(seconds: 15));
            if (result['operation_id'] != operationId ||
                result['order_id'] != orderId ||
                result['serial'] is! int ||
                result['business_date'] != businessDate ||
                businessDate is! String) {
              throw const FormatException('Invalid server acknowledgement');
            }
            await store.completeOrderSync(
              operationId: operationId,
              orderId: orderId,
              serial: result['serial'] as int,
              businessDate: businessDate,
            );
            pendingCount--;
            lastErrorCode = null;
            _notify();
          } catch (error) {
            final code = _errorCode(error);
            await store.recordOrderSyncFailure(operationId, code);
            lastErrorCode = code;
            state = code == 'AUTHORIZATION'
                ? OrderSyncState.authRequired
                : _needsReview(code)
                ? OrderSyncState.needsReview
                : OrderSyncState.failed;
            _notify();
            if ((_manualRequested || _authorizationChanged) && !_closed) continue syncLoop;
            _requested = false;
            _manualRequested = false;
            _authorizationChanged = false;
            return;
          }
        }
        state = OrderSyncState.idle;
        _notify();
      } while (_requested && !_closed);
    } catch (error) {
      lastErrorCode = 'LOCAL_STORAGE';
      state = OrderSyncState.failed;
      _notify();
    }
  }

  bool _needsReview(String? code) =>
      code == 'MENU_CONFLICT' || code == 'INVALID_ORDER' || code == 'INVALID_RESPONSE' || code == 'CONFIGURATION';

  String _errorCode(Object error) {
    if (error is FormatException || error is StateError || error is TypeError) return 'INVALID_RESPONSE';
    if (error is PostgrestException) {
      if (error.message == 'MENU_CONFLICT') return 'MENU_CONFLICT';
      if (error.message == 'SERVER_ORDER_CHANGED') return 'INVALID_ORDER';
      if (error.code == '42501' ||
          error.code == '401' ||
          error.code == '403' ||
          error.code == 'PGRST301' ||
          error.code == 'PGRST303') {
        return 'AUTHORIZATION';
      }
      if (error.code == 'PGRST202') return 'CONFIGURATION';
      if (error.code == '22023' || error.code == '22P02' || error.code == '22003' || error.code == '23505') {
        return 'INVALID_ORDER';
      }
    }
    return 'RETRYABLE';
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> close() async {
    _closed = true;
    await _running;
    dispose();
  }
}

Future<Map<String, dynamic>> submitMerchantOrder(
  SupabaseClient client,
  String operationId,
  Map<String, dynamic> payload,
) async {
  final response = await client.rpc(
    'submit_merchant_order',
    params: {'p_operation_id': operationId, 'p_payload': payload},
  );
  if (response is! Map) throw const FormatException('Invalid server acknowledgement');
  return Map<String, dynamic>.from(response);
}
