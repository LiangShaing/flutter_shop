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
import 'package:flutter_shop/cart_controller.dart';
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
          appBar: AppBar(
            title: const Text('千囍蔬食堂'),
            actions: [
              const SizedBox(
                width: 180,
                height: kToolbarHeight,
                child: MenuSyncStatus(
                  state: MenuSyncState.failed,
                  items: [
                    {'source': 'BUNDLED_OFFLINE'},
                  ],
                  realtimeConfigured: false,
                ),
              ),
            ],
          ),
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
    expect(find.ancestor(of: find.text('同步失敗，顯示本機預設菜單'), matching: find.byType(AppBar)), findsOneWidget);
    expect(find.text('米粉-湯'), findsOneWidget);
    expect(find.text('50'), findsOneWidget);
  });

  testWidgets('distinguishes snapshot success from realtime failure', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('千囍蔬食堂'),
            actions: [
              const SizedBox(
                width: 180,
                height: kToolbarHeight,
                child: MenuSyncStatus(
                  state: MenuSyncState.synced,
                  items: [],
                  realtimeConfigured: true,
                  realtimeStatus: RealtimeSubscribeStatus.channelError,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('雲端可見菜單已更新'), findsOneWidget);
    expect(find.text('即時連線中斷，使用定期更新'), findsOneWidget);
    expect(find.ancestor(of: find.text('雲端可見菜單已更新'), matching: find.byType(AppBar)), findsOneWidget);
  });

  testWidgets('shows when a realtime event was received', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('千囍蔬食堂'),
            actions: [
              SizedBox(
                width: 180,
                height: kToolbarHeight,
                child: MenuSyncStatus(
                  state: MenuSyncState.synced,
                  items: const [],
                  realtimeConfigured: true,
                  realtimeStatus: RealtimeSubscribeStatus.subscribed,
                  lastRealtimeEvent: DateTime(2026, 11, 13, 10, 30),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('即時連線已建立'), findsOneWidget);
    expect(find.textContaining('最近即時事件'), findsOneWidget);
  });

  testWidgets('app bar status fits beside actions on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('千囍蔬食堂'),
            actions: [
              SizedBox(
                width: 100,
                height: kToolbarHeight,
                child: MenuSyncStatus(
                  state: MenuSyncState.failed,
                  items: const [
                    {'source': 'BUNDLED_OFFLINE'},
                  ],
                  realtimeConfigured: true,
                  realtimeStatus: RealtimeSubscribeStatus.channelError,
                  lastRealtimeEvent: DateTime(2026, 11, 13, 10, 30),
                ),
              ),
              IconButton(onPressed: () {}, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
      ),
    );
    final titleRect = tester.getRect(find.byType(MenuSyncStatus));
    final buttonRect = tester.getRect(find.byIcon(Icons.refresh));
    expect(titleRect.right, lessThanOrEqualTo(buttonRect.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('right-side status updates without increasing app bar height', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final syncState = ValueNotifier(MenuSyncState.syncing);
    addTearDown(syncState.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(
            titleSpacing: 12,
            title: const FittedBox(fit: BoxFit.scaleDown, child: Text('千囍蔬食堂')),
            actions: [
              SizedBox(
                width: 100,
                height: kToolbarHeight,
                child: ValueListenableBuilder<MenuSyncState>(
                  valueListenable: syncState,
                  builder: (context, state, _) => MenuSyncStatus(
                    state: state,
                    items: const [],
                    realtimeConfigured: true,
                    realtimeStatus: RealtimeSubscribeStatus.subscribed,
                    lastRealtimeEvent: DateTime(2026, 11, 13, 10, 30),
                  ),
                ),
              ),
              IconButton(onPressed: () {}, icon: const Icon(Icons.receipt_long)),
              IconButton(onPressed: () {}, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
      ),
    );
    expect(find.text('同步中'), findsOneWidget);
    syncState.value = MenuSyncState.synced;
    await tester.pump();
    expect(find.text('雲端可見菜單已更新'), findsOneWidget);
    final statusRect = tester.getRect(find.byType(MenuSyncStatus));
    expect(tester.getRect(find.text('千囍蔬食堂')).right, lessThanOrEqualTo(statusRect.left));
    expect(statusRect.right, lessThanOrEqualTo(tester.getRect(find.byIcon(Icons.receipt_long)).left));
    expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cart fits in app bar while menu fills the screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cart = CartController();
    addTearDown(cart.dispose);
    final items = [menuItem(id: '1', name: '米粉', price: 50)];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2), padding: const EdgeInsets.only(bottom: 24)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(
            titleSpacing: 12,
            title: const FittedBox(fit: BoxFit.scaleDown, child: Text('千囍蔬食堂')),
            actions: [
              const SizedBox(
                width: 72,
                height: kToolbarHeight,
                child: MenuSyncStatus(state: MenuSyncState.synced, items: [], realtimeConfigured: true),
              ),
              MenuCartAction(cart: cart, currentMenu: () => items),
              IconButton(onPressed: () {}, icon: const Icon(Icons.receipt_long)),
              IconButton(onPressed: () {}, icon: const Icon(Icons.refresh)),
            ],
          ),
          body: MenuView(state: MenuSyncState.synced, items: items, cart: cart),
        ),
      ),
    );
    final statusRect = tester.getRect(find.byType(MenuSyncStatus));
    final cartRect = tester.getRect(find.byType(MenuCartAction));
    expect(tester.getRect(find.text('千囍蔬食堂')).right, lessThanOrEqualTo(statusRect.left));
    expect(statusRect.right, lessThanOrEqualTo(cartRect.left));
    expect(cartRect.right, lessThanOrEqualTo(tester.getRect(find.byIcon(Icons.receipt_long)).left));
    expect(tester.getRect(find.byType(MenuView)).bottom, 640);
    final scrollViews = tester.widgetList<SingleChildScrollView>(
      find.descendant(of: find.byType(MenuView), matching: find.byType(SingleChildScrollView)),
    );
    expect(
      scrollViews.any(
        (view) => view.scrollDirection == Axis.vertical && view.padding == const EdgeInsets.only(bottom: 24),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows three legacy menu columns side by side on a tablet', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuView(
            state: MenuSyncState.synced,
            items: [
              {...menuItem(id: '1', name: '海帶', price: 15), 'menu_row': '1'},
              {...menuItem(id: '2', name: '米粉', subName: '乾', price: 50), 'menu_row': '2', 'item_type': 'mainProduct'},
              {...menuItem(id: '3', name: '非常長的品項名稱', price: 40), 'menu_row': '3'},
            ],
          ),
        ),
      ),
    );
    final first = tester.getTopLeft(find.byKey(const ValueKey('quantity:id:1')));
    final second = tester.getTopLeft(find.byKey(const ValueKey('quantity:id:2')));
    final third = tester.getTopLeft(find.byKey(const ValueKey('quantity:id:3')));
    expect(first.dy, second.dy);
    expect(second.dy, third.dy);
    expect(first.dx, lessThan(second.dx));
    expect(second.dx, lessThan(third.dx));
    expect(
      find.byWidgetPredicate((widget) => widget is Container && widget.color == Colors.amberAccent),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone can scroll to third column and enter quantity', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cart = CartController();
    addTearDown(cart.dispose);
    await tester.pumpWidget(
      cartScreen(
        cart: cart,
        items: [
          {...menuItem(id: '3', name: '紅茶', price: 25), 'menu_row': '3'},
        ],
      ),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('quantity:id:3')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('quantity:id:3')), '12');
    await tester.pump();
    expect(cart.quantity, 12);
    expect(find.text('NT\$ 300'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selects quantities and calculates the total', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cart = CartController();
    addTearDown(cart.dispose);
    await tester.pumpWidget(
      cartScreen(
        cart: cart,
        items: [
          menuItem(id: '1', name: '米粉', subName: '湯', price: 50),
          menuItem(id: '2', name: '海帶', price: 15),
        ],
      ),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('quantity:id:1')));
    await tester.enterText(find.byKey(const ValueKey('quantity:id:1')), '2');
    await tester.enterText(find.byKey(const ValueKey('quantity:id:2')), '1');
    await tester.pump();
    expect(cart.quantity, 3);
    expect(find.text('NT\$ 115'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('quantity:id:1')), '1');
    await tester.pump();
    expect(cart.quantity, 2);
    expect(find.text('NT\$ 65'), findsOneWidget);
    await tester.tap(find.byTooltip('查看已選'));
    await tester.pumpAndSettle();
    expect(find.text('已選品項'), findsOneWidget);
    expect(find.text('單價 NT\$ 50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('warns when a selected price changes without changing the total', (tester) async {
    final cart = CartController();
    addTearDown(cart.dispose);
    Widget screen(int price) => cartScreen(
      cart: cart,
      items: [menuItem(id: '1', name: '米粉', subName: '湯', price: price)],
    );
    await tester.pumpWidget(screen(50));
    await tester.enterText(find.byKey(const ValueKey('quantity:id:1')), '1');
    await tester.pumpWidget(screen(60));
    expect(cart.quantity, 1);
    expect(find.text('NT\$ 50'), findsOneWidget);
    expect(find.text('需確認'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('quantity:id:1'))).enabled, isFalse);
    await tester.tap(find.byTooltip('查看已選：菜單有變更，請檢查已選品項'));
    await tester.pumpAndSettle();
    expect(find.text('菜單已變更或停售，請移除後重新選擇'), findsOneWidget);
    await tester.tap(find.byTooltip('移除 米粉-湯'));
    await tester.pump();
    expect(find.text('尚未選餐'), findsOneWidget);
  });

  testWidgets('keeps removed menu items visible in the open cart', (tester) async {
    final menu = ValueNotifier<List<Map<String, Object?>>>([menuItem(id: '1', name: '米粉', price: 50)]);
    final cart = CartController();
    addTearDown(menu.dispose);
    addTearDown(cart.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<List<Map<String, Object?>>>(
          valueListenable: menu,
          builder: (context, items, _) => Scaffold(
            appBar: AppBar(
              actions: [MenuCartAction(cart: cart, menuUpdates: menu, currentMenu: () => menu.value)],
            ),
            body: MenuView(state: MenuSyncState.synced, items: items, cart: cart),
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('quantity:id:1')), '1');
    await tester.pump();
    await tester.tap(find.byTooltip('查看已選'));
    await tester.pumpAndSettle();
    menu.value = [];
    await tester.pump();
    expect(find.text('需確認'), findsOneWidget);
    expect(find.text('菜單已變更或停售，請移除後重新選擇'), findsOneWidget);
    expect(find.text('NT\$ 50'), findsNWidgets(2));
    await tester.tap(find.byTooltip('移除 米粉'));
    await tester.pump();
    expect(find.text('尚未選餐'), findsOneWidget);
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

Widget cartScreen({required CartController cart, required List<Map<String, Object?>> items}) => MaterialApp(
  home: Scaffold(
    appBar: AppBar(
      actions: [MenuCartAction(cart: cart, currentMenu: () => items)],
    ),
    body: MenuView(state: MenuSyncState.synced, items: items, cart: cart),
  ),
);

Map<String, Object?> menuItem({required String id, required String name, String subName = '', required int price}) => {
  'id': id,
  'menu_row': '2',
  'name': name,
  'sub_name': subName,
  'price': price,
  'is_available': 1,
  'source': 'CLOUD_VISIBLE',
};
