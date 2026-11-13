// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_shop/main.dart';
import 'package:flutter_shop/menu_controller.dart';
import 'package:flutter_shop/menu_page.dart';
import 'package:flutter_shop/orders_page.dart';

void main() {
  testWidgets('shows setup state when Supabase is not configured', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SupabaseSetupPage()));

    expect(find.text('尚未設定 Supabase'), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
  });

  testWidgets('shows menu rows, legacy subtitles, and the offline source', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuView(
            state: MenuSyncState.failed,
            items: const [
              {
                'menu_row': '2',
                'name': '米粉',
                'sub_name': '湯',
                'price': 50,
                'is_available': 1,
                'source': 'BUNDLED_OFFLINE',
              },
            ],
          ),
        ),
      ),
    );
    expect(find.text('同步失敗，顯示本機預設菜單'), findsOneWidget);
    expect(find.text('第 2 列'), findsOneWidget);
    expect(find.text('米粉-湯'), findsOneWidget);
    expect(find.text('NT\$ 50'), findsOneWidget);
  });

  testWidgets('distinguishes snapshot success from realtime failure', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MenuView(
            state: MenuSyncState.synced,
            items: [],
            realtimeConfigured: true,
            realtimeStatus: RealtimeSubscribeStatus.channelError,
          ),
        ),
      ),
    );
    expect(find.text('雲端可見菜單已更新'), findsOneWidget);
    expect(find.text('即時連線中斷，使用定期更新'), findsOneWidget);
  });

  testWidgets('shows when a realtime event was received', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuView(
            state: MenuSyncState.synced,
            items: const [],
            realtimeConfigured: true,
            realtimeStatus: RealtimeSubscribeStatus.subscribed,
            lastRealtimeEvent: DateTime(2026, 11, 13, 10, 30),
          ),
        ),
      ),
    );
    expect(find.text('即時連線已建立'), findsOneWidget);
    expect(find.textContaining('最近即時事件'), findsOneWidget);
  });

  testWidgets('updates the visible order when the stream emits changes', (tester) async {
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();

    await tester.pumpWidget(
      MaterialApp(
        home: OrdersFeed(ordersStream: controller.stream, onRetry: () {}),
      ),
    );

    controller.add([
      {
        'id': 'order-1',
        'serial': 12,
        'takeout': false,
        'order_source': 'POS_APP',
        'uber': false,
        'status': 'PENDING',
        'total_price': 180,
        'order_date': '2026-11-12T10:00:00Z',
      },
    ]);
    await tester.pump();

    expect(find.text('內用  ·  單號 12'), findsOneWidget);
    expect(find.text('待處理'), findsOneWidget);
    expect(find.text('NT\$ 180'), findsOneWidget);

    controller.add([
      {
        'id': 'order-1',
        'serial': 12,
        'takeout': false,
        'order_source': 'POS_APP',
        'uber': false,
        'status': 'PREPARING',
        'total_price': 180,
        'order_date': '2026-11-12T10:00:00Z',
      },
    ]);
    await tester.pump();

    expect(find.text('製作中'), findsOneWidget);
    expect(find.text('待處理'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await controller.close();
  });
}
