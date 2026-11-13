import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_database.dart';

enum MenuSyncState { loading, offline, syncing, synced, failed }

typedef FetchVisibleMenu = Future<List<Map<String, dynamic>>> Function();

void logMenuSync(String message) {
  if (kDebugMode) debugPrint('[MenuSync] ${DateTime.now().toIso8601String()} $message');
}

String classifyRealtimeError(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('jwt') || message.contains('token')) return 'token';
  if (message.contains('unauthorized') || message.contains('forbidden') || message.contains('permission')) {
    return 'permission';
  }
  if (message.contains('publication')) return 'publication';
  if (message.contains('replication') || message.contains('postgres') || message.contains('cdc')) {
    return 'database_subscription';
  }
  if (message.contains('timeout') || message.contains('timed out')) return 'timeout';
  if (message.contains('socket') || message.contains('network') || message.contains('connection')) return 'connection';
  return 'unclassified';
}

void logRealtimeError(Object error, {bool verbose = const bool.fromEnvironment('MENU_SYNC_VERBOSE_REALTIME_ERRORS')}) {
  if (!kDebugMode || !verbose) return;
  var message = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
  message = message.replaceAll(RegExp(r'https?://[^\s"<>]+', caseSensitive: false), '[redacted-url]');
  message = message.replaceAll(RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b'), '[redacted-jwt]');
  message = message.replaceAll(RegExp(r'\bsb_(?:publishable|secret)_[A-Za-z0-9_-]+\b'), '[redacted-key]');
  message = message.replaceAll(RegExp(r'\bBearer\s+[^\s,;]+', caseSensitive: false), 'Bearer [redacted]');
  message = message.replaceAllMapped(
    RegExp(
      r'''(\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|secret|token)\b["']?\s*[:=]\s*["']?)[^\s,;"'}]+''',
      caseSensitive: false,
    ),
    (match) => '${match[1]}[redacted]',
  );
  if (message.length > 500) message = '${message.substring(0, 500)}...';
  logMenuSync('realtime error_detail=$message');
}

class MenuController extends ChangeNotifier {
  MenuController({required this.store, this.fetchVisibleMenu});

  final LocalDatabase store;
  final FetchVisibleMenu? fetchVisibleMenu;
  List<Map<String, Object?>> items = [];
  MenuSyncState state = MenuSyncState.loading;
  Object? lastError;
  bool _closed = false;
  bool _refreshAgain = false;
  Future<void>? _activeRefresh;

  Future<void> initialize() async {
    items = await store.menuItems();
    logMenuSync('local cache loaded count=${items.length}');
    state = MenuSyncState.offline;
    _notify();
    if (fetchVisibleMenu == null) {
      await _seedIfNeeded();
      _notify();
    } else {
      await refresh(reason: 'startup');
    }
  }

  Future<void> refresh({String reason = 'unspecified'}) {
    if (_closed || fetchVisibleMenu == null) {
      logMenuSync('refresh skipped reason=$reason closed=$_closed configured=${fetchVisibleMenu != null}');
      return Future.value();
    }
    if (_activeRefresh != null) {
      _refreshAgain = true;
      logMenuSync('refresh queued reason=$reason');
      return _activeRefresh!;
    }
    logMenuSync('refresh requested reason=$reason');
    final future = _refreshLoop();
    _activeRefresh = future;
    return future.whenComplete(() => _activeRefresh = null);
  }

  Future<void> _refreshLoop() async {
    do {
      _refreshAgain = false;
      state = MenuSyncState.syncing;
      _notify();
      final stopwatch = Stopwatch()..start();
      try {
        final snapshot = await fetchVisibleMenu!().timeout(const Duration(seconds: 15));
        logMenuSync('snapshot fetched count=${snapshot.length} elapsed_ms=${stopwatch.elapsedMilliseconds}');
        await store.replaceVisibleMenu(snapshot);
        items = await store.menuItems();
        logMenuSync('snapshot applied count=${items.length} elapsed_ms=${stopwatch.elapsedMilliseconds}');
        lastError = null;
        state = MenuSyncState.synced;
      } catch (error) {
        lastError = error;
        final code = error is PostgrestException ? ' code=${error.code}' : '';
        logMenuSync('refresh failed type=${error.runtimeType}$code elapsed_ms=${stopwatch.elapsedMilliseconds}');
        await _seedIfNeeded();
        state = MenuSyncState.failed;
      }
      _notify();
      if (_refreshAgain && !_closed) logMenuSync('running queued refresh');
    } while (_refreshAgain && !_closed);
  }

  Future<void> _seedIfNeeded() async {
    if (items.isEmpty && !await store.hasVisibleMenuSnapshot()) {
      await store.seedMenu(source: SeedMenuSource.offline);
      items = await store.menuItems();
      logMenuSync('offline menu seeded count=${items.length}');
    }
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> close() async {
    _closed = true;
    await _activeRefresh;
    await store.close();
    dispose();
  }
}

Future<List<Map<String, dynamic>>> fetchVisibleMenu(SupabaseClient client) async {
  const pageSize = 200;
  final items = <Map<String, dynamic>>[];
  while (true) {
    final offset = items.length;
    final stopwatch = Stopwatch()..start();
    final page = await client
        .from('menu_items')
        .select('id, legacy_id, sid, item_type, menu_row, name, display_name, price, is_available')
        .order('id')
        .range(items.length, items.length + pageSize - 1);
    logMenuSync('page fetched offset=$offset count=${page.length} elapsed_ms=${stopwatch.elapsedMilliseconds}');
    if (page.isEmpty) return items;
    items.addAll(page);
  }
}
