// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_shop/main.dart';
import 'package:flutter_shop/orders_page.dart';

void main() {
  testWidgets('shows setup state when Supabase is not configured', (tester) async {
    await tester.pumpWidget(const FlutterShopApp(isSupabaseConfigured: false));

    expect(find.text('尚未設定 Supabase'), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
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
