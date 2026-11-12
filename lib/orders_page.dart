import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key, required this.client});

  final SupabaseClient client;

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  late Stream<List<Map<String, dynamic>>> _ordersStream;

  @override
  void initState() {
    super.initState();
    _createOrdersStream();
  }

  void _createOrdersStream() {
    _ordersStream = widget.client
        .from('orders')
        .stream(primaryKey: const ['id'])
        .order('order_date', ascending: false)
        .limit(100);
  }

  void _retry() {
    setState(_createOrdersStream);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('門市訂單'),
        actions: [
          IconButton(tooltip: '重新連線', onPressed: _retry, icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                Expanded(child: Text('訂單列表', style: Theme.of(context).textTheme.titleLarge)),
                Icon(Icons.sync, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  '即時同步',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
          ),
          Expanded(
            child: OrdersFeed(ordersStream: _ordersStream, onRetry: _retry),
          ),
        ],
      ),
    );
  }
}

class OrdersFeed extends StatelessWidget {
  const OrdersFeed({super.key, required this.ordersStream, required this.onRetry});

  final Stream<List<Map<String, dynamic>>> ordersStream;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ordersStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _FeedMessage(
            icon: Icons.cloud_off_outlined,
            title: '訂單同步失敗',
            message: '請確認網路與 Supabase 權限後重試。',
            action: TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('重試')),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final orders = snapshot.data!;
        if (orders.isEmpty) {
          return const _FeedMessage(icon: Icons.receipt_long_outlined, title: '目前沒有訂單', message: '新訂單會自動顯示在這裡。');
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          itemCount: orders.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _OrderTile(order: orders[index]),
        );
      },
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = order['status']?.toString() ?? 'UNKNOWN';
    final serviceType = order['takeout'] == true ? '外帶' : '內用';
    final serial = order['serial']?.toString() ?? '—';
    final amount = order['total_price']?.toString() ?? '—';
    final source = _sourceLabel(order['order_source']?.toString(), isUber: order['uber'] == true);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '$serviceType  ·  單號 $serial',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      _StatusLabel(status: status),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '$source  ·  ${_formatDateTime(order['order_date'])}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'NT\$ $amount',
              textAlign: TextAlign.end,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (status) {
      'PENDING' => const Color(0xFF9A5A00),
      'PREPARING' => const Color(0xFF176B58),
      'COMPLETED' => const Color(0xFF315D9A),
      'CANCELLED' => theme.colorScheme.error,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    final label = switch (status) {
      'PENDING' => '待處理',
      'PREPARING' => '製作中',
      'COMPLETED' => '已完成',
      'CANCELLED' => '已取消',
      _ => status,
    };

    return DecoratedBox(
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _FeedMessage extends StatelessWidget {
  const _FeedMessage({required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

String _sourceLabel(String? source, {required bool isUber}) {
  if (isUber || source == 'UBER') return 'Uber Eats';
  return switch (source) {
    'POS_APP' => '店員點餐',
    'WEB_QR' => 'QR 點餐',
    'LEGACY' => '舊系統訂單',
    null || '' => '來源未提供',
    _ => source,
  };
}

String _formatDateTime(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return '時間未提供';

  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month/$day $hour:$minute';
}
