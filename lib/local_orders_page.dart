import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_database.dart';
import 'main.dart' show SupabaseSetupPage;
import 'orders_page.dart';

String localSerialLabel(Map<String, Object?> order) {
  final serial = order['serial'] ?? '未知';
  return switch (order['serial_status']) {
    'PROVISIONAL' => '暫定流水號 $serial',
    'ASSIGNED' => '正式流水號 $serial',
    _ => '流水號 $serial（狀態未知）',
  };
}

String localSyncLabel(Map<String, Object?> order) => switch (order['sync_status']) {
  'PENDING_SYNC' => '待同步',
  'SYNCED' => '已同步',
  'SYNC_FAILED' => '同步失敗',
  _ => '同步狀態未知',
};

class LocalOrdersPage extends StatefulWidget {
  const LocalOrdersPage({super.key, required this.store, this.client});

  final LocalDatabase store;
  final SupabaseClient? client;

  @override
  State<LocalOrdersPage> createState() => _LocalOrdersPageState();
}

class _LocalOrdersPageState extends State<LocalOrdersPage> {
  late Future<List<Map<String, Object?>>> _orders;

  @override
  void initState() {
    super.initState();
    _orders = widget.store.localOrders();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('本機訂單'),
      actions: [
        IconButton(
          tooltip: '重新整理本機訂單',
          onPressed: () => setState(() => _orders = widget.store.localOrders()),
          icon: const Icon(Icons.refresh),
        ),
        if (widget.client != null)
          IconButton(
            tooltip: '雲端訂單',
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OrdersPage(client: widget.client!))),
            icon: const Icon(Icons.cloud_outlined),
          )
        else
          IconButton(
            tooltip: 'Supabase 設定',
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SupabaseSetupPage())),
            icon: const Icon(Icons.settings_outlined),
          ),
      ],
    ),
    body: LocalOrdersView(
      orders: _orders,
      onOpen: (order) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LocalOrderDetailsPage(store: widget.store, order: order),
        ),
      ),
    ),
  );
}

class LocalOrdersView extends StatelessWidget {
  const LocalOrdersView({super.key, required this.orders, required this.onOpen});

  final Future<List<Map<String, Object?>>> orders;
  final ValueChanged<Map<String, Object?>> onOpen;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(
    future: orders,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('無法讀取本機訂單'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final orders = snapshot.data!;
      if (orders.isEmpty) return const Center(child: Text('目前沒有本機訂單'));
      return ListView.separated(
        itemCount: orders.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final order = orders[index];
          return ListTile(
            title: Text(localSerialLabel(order)),
            subtitle: Text(
              '${LocalDatabase.taipeiTimestamp(order['order_date'] as String?) ?? order['business_date'] ?? '日期未知'} · ${localSyncLabel(order)}',
            ),
            trailing: Text('NT\$ ${order['total_price']}'),
            onTap: () => onOpen(order),
          );
        },
      );
    },
  );
}

class LocalOrderDetailsPage extends StatelessWidget {
  const LocalOrderDetailsPage({super.key, required this.store, required this.order});

  final LocalDatabase store;
  final Map<String, Object?> order;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('本機訂單明細')),
    body: LocalOrderDetailsView(order: order, items: store.localOrderItems(order['id'] as String)),
  );
}

class LocalOrderDetailsView extends StatelessWidget {
  const LocalOrderDetailsView({super.key, required this.order, required this.items});

  final Map<String, Object?> order;
  final Future<List<Map<String, Object?>>> items;

  @override
  Widget build(BuildContext context) {
    final service = order['uber'] == 1
        ? 'Uber'
        : order['takeout'] == 1
        ? '外帶'
        : '內用';
    final spice = switch (order['chili_level']) {
      0 => '不辣',
      1 => '小辣',
      2 => '中辣',
      3 => '大辣',
      _ => order['chili'] == 1 ? '加辣（級別未知）' : '不加辣（級別未知）',
    };
    final mark = order['mark'] as String?;
    return FutureBuilder<List<Map<String, Object?>>>(
      future: items,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('無法讀取本機訂單明細'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(localSerialLabel(order), style: Theme.of(context).textTheme.titleLarge),
            Text(
              '${LocalDatabase.taipeiTimestamp(order['order_date'] as String?) ?? order['business_date'] ?? '日期未知'} · ${localSyncLabel(order)}',
            ),
            const SizedBox(height: 12),
            Text('$service · 總額 NT\$ ${order['total_price']} · 實收 NT\$ ${order['get_pay']}'),
            Text('酸菜：${order['sauerkraut'] == 1 ? '加' : '不加'} · 薑絲：${order['ginger'] == 1 ? '加' : '不加'} · $spice'),
            if (mark != null && mark.isNotEmpty) Text('標註：$mark'),
            const Divider(height: 24),
            ...snapshot.data!.map((item) {
              final subName = item['show_name'] as String? ?? '';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${item['name']}${subName.isEmpty ? '' : '-$subName'}'),
                trailing: SizedBox(
                  width: 120,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text('× ${item['quantity'] ?? '未知'}  ·  NT\$ ${item['price']}'),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
