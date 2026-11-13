import 'dart:async';

import 'package:flutter/material.dart' hide MenuController;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_database.dart';
import 'main.dart' show SupabaseSetupPage;
import 'menu_controller.dart';
import 'orders_page.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key, required this.client});

  final SupabaseClient? client;

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> with WidgetsBindingObserver {
  MenuController? _controller;
  RealtimeChannel? _channel;
  Timer? _timer;
  late Future<void> _startup;
  Object? _error;
  RealtimeSubscribeStatus? _realtimeStatus;
  DateTime? _lastRealtimeEvent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startup = _start();
  }

  Future<void> _start() async {
    try {
      final store = await LocalDatabase.open();
      logMenuSync('local database opened');
      if (!mounted) {
        await store.close();
        return;
      }
      final client = widget.client;
      final controller = MenuController(
        store: store,
        fetchVisibleMenu: client == null ? null : () => fetchVisibleMenu(client),
      );
      _controller = controller;
      setState(() {});
      await controller.initialize();
      if (!mounted || client == null) return;
      logMenuSync('subscribing to realtime tables=menu_items,categories');
      _channel = client
          .channel('visible-menu')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'menu_items',
            callback: (payload) => _onRealtimeEvent(controller, 'menu_items', payload.eventType),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'categories',
            callback: (payload) => _onRealtimeEvent(controller, 'categories', payload.eventType),
          )
          .subscribe((status, error) {
            logMenuSync(
              'realtime status=${status.name}'
              '${error == null ? '' : ' error_type=${error.runtimeType} error_category=${classifyRealtimeError(error)}'}',
            );
            if (error != null) logRealtimeError(error);
            if (mounted) setState(() => _realtimeStatus = status);
            if (status == RealtimeSubscribeStatus.subscribed) unawaited(controller.refresh(reason: 'subscribed'));
          });
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(controller.refresh(reason: 'periodic')));
    } catch (error) {
      logMenuSync('startup failed type=${error.runtimeType}');
      if (mounted) setState(() => _error = error);
    }
  }

  void _onRealtimeEvent(MenuController controller, String table, PostgresChangeEvent event) {
    logMenuSync('realtime event table=$table event=${event.name}');
    if (mounted) setState(() => _lastRealtimeEvent = DateTime.now());
    unawaited(controller.refresh(reason: 'realtime:$table'));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_controller?.refresh(reason: 'resume'));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    final channel = _channel;
    if (channel != null) unawaited(widget.client!.removeChannel(channel));
    unawaited(_startup.whenComplete(() => _controller?.close()));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('菜單'),
        actions: [
          if (widget.client != null)
            IconButton(
              tooltip: '訂單',
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => OrdersPage(client: widget.client!))),
              icon: const Icon(Icons.receipt_long_outlined),
            )
          else
            IconButton(
              tooltip: 'Supabase 設定',
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SupabaseSetupPage())),
              icon: const Icon(Icons.settings_outlined),
            ),
          IconButton(
            tooltip: '重新整理菜單',
            onPressed: widget.client == null || controller == null
                ? null
                : () => unawaited(controller.refresh(reason: 'manual')),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _error != null
          ? const Center(child: Text('無法開啟本機菜單'))
          : controller == null
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: controller,
              builder: (context, _) => MenuView(
                items: controller.items,
                state: controller.state,
                realtimeStatus: _realtimeStatus,
                realtimeConfigured: widget.client != null,
                lastRealtimeEvent: _lastRealtimeEvent,
              ),
            ),
    );
  }
}

class MenuView extends StatelessWidget {
  const MenuView({
    super.key,
    required this.items,
    required this.state,
    this.realtimeStatus,
    this.realtimeConfigured = false,
    this.lastRealtimeEvent,
  });

  final List<Map<String, Object?>> items;
  final MenuSyncState state;
  final RealtimeSubscribeStatus? realtimeStatus;
  final bool realtimeConfigured;
  final DateTime? lastRealtimeEvent;

  @override
  Widget build(BuildContext context) {
    final status = switch (state) {
      MenuSyncState.loading => '載入中',
      MenuSyncState.offline => items.any((item) => item['source'] == 'BUNDLED_OFFLINE') ? '本機預設菜單' : '本機快取',
      MenuSyncState.syncing => '同步中',
      MenuSyncState.synced => '雲端可見菜單已更新',
      MenuSyncState.failed =>
        items.any((item) => item['source'] == 'BUNDLED_OFFLINE') ? '同步失敗，顯示本機預設菜單' : '同步失敗，顯示本機快取',
    };
    final realtimeLabel = !realtimeConfigured
        ? '即時連線未設定'
        : realtimeStatus == RealtimeSubscribeStatus.subscribed
        ? '即時連線已建立'
        : realtimeStatus == null
        ? '即時連線中'
        : '即時連線中斷，使用定期更新';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Icon(state == MenuSyncState.failed ? Icons.cloud_off_outlined : Icons.cloud_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(status),
                    Text(realtimeLabel, style: Theme.of(context).textTheme.bodySmall),
                    if (lastRealtimeEvent != null)
                      Text(
                        '最近即時事件 ${TimeOfDay.fromDateTime(lastRealtimeEvent!).format(context)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(state == MenuSyncState.loading ? '載入中' : '目前沒有可顯示的菜單'))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final subName = item['sub_name'] as String;
                    final row = item['menu_row'] as String;
                    final previousRow = index == 0 ? null : items[index - 1]['menu_row'];
                    final available = item['is_available'] == 1;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (row != previousRow)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                            child: Text('第 $row 列', style: Theme.of(context).textTheme.titleMedium),
                          ),
                        ListTile(
                          enabled: available,
                          title: Text('${item['name']}${subName.isEmpty ? '' : '-$subName'}'),
                          subtitle: available ? null : const Text('停售'),
                          trailing: Text('NT\$ ${item['price']}'),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}
