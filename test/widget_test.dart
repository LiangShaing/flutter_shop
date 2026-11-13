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
import 'package:flutter_shop/local_database.dart';
import 'package:flutter_shop/local_orders_page.dart';
import 'package:flutter_shop/menu_controller.dart';
import 'package:flutter_shop/menu_page.dart';
import 'package:flutter_shop/order_draft.dart';
import 'package:flutter_shop/order_options.dart';
import 'package:flutter_shop/order_sync_controller.dart';
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
              {'menu_row': '2', 'name': '米粉', 'sub_name': '湯', 'price': 50, 'is_available': 1, 'source': 'BUNDLED_OFFLINE'},
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
                child: MenuSyncStatus(state: MenuSyncState.synced, items: [], realtimeConfigured: true, realtimeStatus: RealtimeSubscribeStatus.channelError),
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
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2), padding: const EdgeInsets.only(bottom: 24)),
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
    final scrollViews = tester.widgetList<SingleChildScrollView>(find.descendant(of: find.byType(MenuView), matching: find.byType(SingleChildScrollView)));
    expect(scrollViews.any((view) => view.scrollDirection == Axis.vertical && view.padding == const EdgeInsets.only(bottom: 24)), isTrue);
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
    expect(find.byWidgetPredicate((widget) => widget is Container && widget.color == Colors.amberAccent), findsOneWidget);
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

  testWidgets('sets legacy ingredient and spice options in the third column', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
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
    expect(tester.widget<Checkbox>(find.byKey(const ValueKey('option:不加酸菜'))).value, isFalse);
    expect(tester.widget<Checkbox>(find.byKey(const ValueKey('option:不加薑絲'))).value, isFalse);
    expect(tester.widget<Checkbox>(find.byKey(const ValueKey('option:不辣'))).value, isTrue);
    await tester.tap(find.byKey(const ValueKey('option:不加酸菜')));
    await tester.tap(find.byKey(const ValueKey('option:不加薑絲')));
    await tester.tap(find.byKey(const ValueKey('option:中辣')));
    await tester.pump();
    expect(cart.options.sauerkraut, isFalse);
    expect(cart.options.ginger, isFalse);
    expect(cart.options.spiceLevel, 2);
    expect(tester.widget<Checkbox>(find.byKey(const ValueKey('option:不辣'))).value, isFalse);
    expect(tester.widget<Checkbox>(find.byKey(const ValueKey('option:中辣'))).value, isTrue);
    await tester.tap(find.byKey(const ValueKey('option:中辣')));
    await tester.pump();
    expect(cart.options.spiceLevel, 2);
  });

  testWidgets('retains service type and mark after closing the selected-items sheet', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final cart = CartController();
    addTearDown(cart.dispose);
    final item = menuItem(id: '1', name: '米粉', price: 50);
    cart.add(item);
    await tester.pumpWidget(cartScreen(cart: cart, items: [item]));
    await tester.tap(find.byTooltip('查看已選'));
    await tester.pumpAndSettle();
    expect(cart.options.serviceType, isNull);
    await tester.tap(find.text('外帶'));
    await tester.pump();
    expect(cart.options.serviceType, ServiceType.takeout);
    await tester.tap(find.text('Uber'));
    await tester.pump();
    expect(cart.options.serviceType, ServiceType.uber);
    await tester.enterText(find.byKey(const ValueKey('order-mark')), '少湯');
    await tester.pump();
    expect(cart.options.mark, '少湯');
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('已選品項'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('查看已選'));
    await tester.pumpAndSettle();
    expect(find.text('少湯'), findsOneWidget);
    expect(cart.options.serviceType, ServiceType.uber);
  });

  testWidgets('shows first-phase orders as official and local-only', (tester) async {
    final order = {...localOrder(), 'serial_status': 'ASSIGNED', 'sync_status': 'LOCAL_ONLY'};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalOrdersView(orders: Future.value([order]), onOpen: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('正式流水號 10'), findsOneWidget);
    expect(find.text('2026-11-13 10:00:00 · 本機存單，第一階段不上傳'), findsOneWidget);
  });

  testWidgets('order options remain usable with a keyboard and enlarged text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final cart = CartController();
    addTearDown(cart.dispose);
    final item = menuItem(id: '1', name: '米粉', price: 50);
    cart.add(item);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              MenuCartAction(cart: cart, currentMenu: () => [item]),
            ],
          ),
          body: MenuView(state: MenuSyncState.synced, items: [item], cart: cart),
        ),
      ),
    );
    await tester.tap(find.byTooltip('查看已選'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('order-payment')),
      100,
      scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first,
    );
    await tester.enterText(find.byKey(const ValueKey('order-payment')), '150');
    await tester.pump();
    expect(cart.options.receivedAmount, 150);
    expect(cart.options.changeFor(cart.total), 100);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('order-mark')),
      100,
      scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first,
    );
    await tester.enterText(find.byKey(const ValueKey('order-mark')), '備註');
    await tester.pump();
    expect(cart.options.mark, '備註');
    expect(tester.takeException(), isNull);
  });

  testWidgets('calculates change and keeps received amount across service changes and reopening', (tester) async {
    final cart = CartController();
    addTearDown(cart.dispose);
    final item = menuItem(id: '1', name: '米粉', price: 50);
    cart.setQuantity(item, 2);
    await tester.pumpWidget(cartScreen(cart: cart, items: [item]));
    await tester.tap(find.byTooltip('查看已選'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uber'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('order-payment')),
      100,
      scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first,
    );
    await tester.enterText(find.byKey(const ValueKey('order-payment')), '150');
    await tester.pump();
    expect(cart.options.receivedAmount, 150);
    expect(cart.options.serviceType, ServiceType.uber);
    expect(find.text('找零：NT\$ 50'), findsOneWidget);
    cart.setQuantity(item, 3);
    await tester.pump();
    expect(find.text('找零：NT\$ 0'), findsOneWidget);
    Navigator.of(tester.element(find.byKey(const ValueKey('order-payment')))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('查看已選'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('order-payment')),
      100,
      scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first,
    );
    expect(find.text('150'), findsOneWidget);
    expect(find.text('找零：NT\$ 0'), findsOneWidget);
  });

  testWidgets('clearing and oversized received amounts do not leave a stale change', (tester) async {
    final cart = CartController();
    addTearDown(cart.dispose);
    final item = menuItem(id: '1', name: '米粉', price: 50);
    cart.add(item);
    await tester.pumpWidget(cartScreen(cart: cart, items: [item]));
    await tester.tap(find.byTooltip('查看已選'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('order-payment')),
      100,
      scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first,
    );
    await tester.enterText(find.byKey(const ValueKey('order-payment')), '100');
    await tester.pump();
    expect(find.text('找零：NT\$ 50'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('order-payment')), '999999999999999999999999999999');
    await tester.pump();
    expect(find.text('金額過大，請重新輸入'), findsOneWidget);
    expect(find.text('找零：--'), findsOneWidget);
    expect(cart.options.receivedAmount, isNull);
    await tester.enterText(find.byKey(const ValueKey('order-payment')), '');
    await tester.pump();
    expect(find.text('金額過大，請重新輸入'), findsNothing);
    expect(find.text('找零：NT\$ 0'), findsOneWidget);
    expect(cart.options.receivedAmount, 0);
  });

  testWidgets('saves a local-only official order and resets the cart only after success', (tester) async {
    final item = menuItem(id: 'menu-1', name: '米粉', subName: '湯', price: 50);
    final cart = CartController();
    addTearDown(cart.dispose);
    final drafts = <OrderDraft>[];
    Future<SavedOrder> save(OrderDraft draft) async {
      drafts.add(draft);
      return SavedOrder(id: draft.id, serial: 10, businessDate: '2026-11-13');
    }

    cart.setQuantity(item, 2);
    cart.options.setServiceType(ServiceType.uber);
    cart.options.setSpiceLevel(2);
    cart.options.setPaymentInput('100');
    await tester.pumpWidget(cartScreen(cart: cart, items: [item], saveOrder: save));
    await tester.tap(find.byTooltip('查看已選'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, '存入本機'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('存入本機'));
    await tester.pumpAndSettle();
    expect(find.text('已存入本機'), findsOneWidget);
    expect(find.textContaining('正式流水號 10'), findsOneWidget);
    expect(find.textContaining('第一階段只存於本機，不會上傳；尚未列印。'), findsOneWidget);
    expect(cart.items, isEmpty);
    expect(cart.options.serviceType, isNull);
    expect(drafts.single.serviceType, ServiceType.uber);
    expect(drafts.single.spiceLevel, 2);
    expect(drafts.single.total, 100);
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();
  });

  testWidgets('keeps the cart and stable draft when local saving fails', (tester) async {
    final cart = CartController();
    addTearDown(cart.dispose);
    final item = menuItem(id: '1', name: '米粉', price: 50);
    cart.add(item);
    cart.options.setServiceType(ServiceType.dineIn);
    final attempts = <OrderDraft>[];
    final pending = Completer<SavedOrder>();
    Future<SavedOrder> save(OrderDraft draft) {
      attempts.add(draft);
      if (attempts.length == 1) return pending.future;
      return Future.value(const SavedOrder(id: 'saved', serial: 10, businessDate: '2026-11-13'));
    }

    await tester.pumpWidget(cartScreen(cart: cart, items: [item], saveOrder: save));
    await tester.tap(find.byTooltip('查看已選'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('存入本機'),
      100,
      scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first,
    );
    await tester.tap(find.text('存入本機'));
    await tester.pump();
    expect(find.text('儲存中'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(attempts, hasLength(1));
    pending.completeError(StateError('test'));
    await tester.pumpAndSettle();
    expect(find.text('存單失敗，已保留選餐，請重試'), findsOneWidget);
    expect(cart.quantity, 1);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '存入本機'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('存入本機'));
    await tester.pumpAndSettle();
    expect(attempts, hasLength(2));
    expect(attempts[1].id, attempts[0].id);
    expect(attempts[1].operationId, attempts[0].operationId);
    expect(find.text('已存入本機'), findsOneWidget);
  });

  testWidgets('requires a service type before saving without clearing the cart', (tester) async {
    final cart = CartController();
    addTearDown(cart.dispose);
    final item = menuItem(id: '1', name: '米粉', price: 50);
    cart.add(item);
    var saveCalls = 0;
    await tester.pumpWidget(
      cartScreen(
        cart: cart,
        items: [item],
        saveOrder: (draft) async {
          saveCalls++;
          return const SavedOrder(id: 'saved', serial: 10, businessDate: '2026-11-13');
        },
      ),
    );
    await tester.tap(find.byTooltip('查看已選'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('存入本機'),
      100,
      scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first,
    );
    await tester.tap(find.text('存入本機'));
    await tester.pumpAndSettle();
    expect(find.text('請選擇內用、外帶或 Uber'), findsOneWidget);
    expect(saveCalls, 0);
    expect(cart.quantity, 1);
  });

  testWidgets('keeps selection when malformed menu data cannot form a draft', (tester) async {
    final cart = CartController();
    addTearDown(cart.dispose);
    final item = {...menuItem(id: '1', name: '米粉', price: 50)}..remove('sid');
    cart.add(item);
    cart.options.setServiceType(ServiceType.dineIn);
    var saveCalls = 0;
    await tester.pumpWidget(
      cartScreen(
        cart: cart,
        items: [item],
        saveOrder: (draft) async {
          saveCalls++;
          return const SavedOrder(id: 'saved', serial: 10, businessDate: '2026-11-13');
        },
      ),
    );
    await tester.tap(find.byTooltip('查看已選'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('存入本機'),
      100,
      scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first,
    );
    await tester.tap(find.text('存入本機'));
    await tester.pumpAndSettle();
    expect(find.text('無法建立訂單，請檢查選餐資料'), findsOneWidget);
    expect(saveCalls, 0);
    expect(cart.quantity, 1);
  });

  testWidgets('shows pending provisional local orders and their snapshots', (tester) async {
    final order = localOrder();
    Map<String, Object?>? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalOrdersView(orders: Future.value([order]), onOpen: (value) => opened = value),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暫定流水號 10'), findsOneWidget);
    expect(find.text('2026-11-13 10:00:00 · 第二階段待同步'), findsOneWidget);
    await tester.tap(find.text('暫定流水號 10'));
    expect(opened, same(order));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalOrderDetailsView(
            order: order,
            items: Future.value([
              {'name': '米粉', 'show_name': '湯', 'price': 50, 'quantity': 2},
            ]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暫定流水號 10'), findsOneWidget);
    expect(find.text('2026-11-13 10:00:00 · 第二階段待同步'), findsOneWidget);
    expect(find.text('Uber · 總額 NT\$ 100 · 實收 NT\$ 80'), findsOneWidget);
    expect(find.text('酸菜：不加 · 薑絲：加 · 大辣'), findsOneWidget);
    expect(find.text('標註：少湯'), findsOneWidget);
    expect(find.text('米粉-湯'), findsOneWidget);
    expect(find.text('× 2  ·  NT\$ 50'), findsOneWidget);
  });

  testWidgets('updates the order list and open details when an official serial arrives', (tester) async {
    final store = FakeLocalOrdersStore(localOrder());
    final sync = TestOrderSync(store);
    sync.state = OrderSyncState.authRequired;
    sync.pendingCount = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalOrdersPage(store: store, orderSync: sync),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('需要店家登入或授權 · 待同步 1 筆'), findsOneWidget);
    await tester.tap(find.text('暫定流水號 10'));
    await tester.pumpAndSettle();
    store.order = {...store.order, 'serial': 13, 'provisional_serial': 10, 'serial_status': 'ASSIGNED', 'sync_status': 'SYNCED'};
    sync.emit(OrderSyncState.idle, 0);
    await tester.pumpAndSettle();
    expect(find.text('正式流水號 13'), findsOneWidget);
    expect(find.text('原暫定流水號 10'), findsOneWidget);
    expect(find.text('2026-11-13 10:00:00 · 已同步'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('正式流水號 13'), findsOneWidget);
    expect(find.text('沒有待同步訂單'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await sync.close();
  });

  testWidgets('does not claim the outbox is empty before it has loaded', (tester) async {
    final sync = TestOrderSync(FakeLocalOrdersStore(localOrder()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OrderSyncStatus(sync: sync)),
      ),
    );
    expect(find.text('載入本機同步佇列'), findsOneWidget);
    expect(find.text('沒有待同步訂單'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await sync.close();
  });

  testWidgets('shows empty and error states for local order queries', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalOrdersView(orders: Future.value([]), onOpen: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('目前沒有本機訂單'), findsOneWidget);
    final failed = Completer<List<Map<String, Object?>>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalOrdersView(orders: failed.future, onOpen: (_) {}),
        ),
      ),
    );
    failed.completeError(StateError('database unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('無法讀取本機訂單'), findsOneWidget);
  });

  testWidgets('does not invent a serial state or spice level for legacy records', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalOrderDetailsView(order: {...localOrder(), 'serial_status': 'UNKNOWN', 'chili_level': null, 'chili': 1}, items: Future.value([])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('流水號 10（狀態未知）'), findsOneWidget);
    expect(find.textContaining('加辣（級別未知）'), findsOneWidget);
  });

  testWidgets('local order details fit long values on a phone with enlarged text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: LocalOrderDetailsView(
            order: localOrder(),
            items: Future.value([
              {'name': '非常長的餐點名稱需要完整顯示', 'show_name': '湯', 'price': 999999999, 'quantity': 999999},
            ]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('非常長的餐點名稱需要完整顯示-湯'),
      100,
      scrollable: find.descendant(of: find.byType(LocalOrderDetailsView), matching: find.byType(Scrollable)).first,
    );
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
      {'id': 'order-1', 'serial': 12, 'takeout': false, 'order_source': 'POS_APP', 'uber': false, 'status': 'PENDING', 'total_price': 180, 'order_date': '2026-11-12T10:00:00Z'},
    ]);
    await tester.pump();

    expect(find.text('內用  ·  單號 12'), findsOneWidget);
    expect(find.text('待處理'), findsOneWidget);
    expect(find.text('NT\$ 180'), findsOneWidget);

    controller.add([
      {'id': 'order-1', 'serial': 12, 'takeout': false, 'order_source': 'POS_APP', 'uber': false, 'status': 'PREPARING', 'total_price': 180, 'order_date': '2026-11-12T10:00:00Z'},
    ]);
    await tester.pump();

    expect(find.text('製作中'), findsOneWidget);
    expect(find.text('待處理'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await controller.close();
  });
}

Widget cartScreen({required CartController cart, required List<Map<String, Object?>> items, Future<SavedOrder> Function(OrderDraft)? saveOrder}) => MaterialApp(
  home: Scaffold(
    appBar: AppBar(
      actions: [MenuCartAction(cart: cart, currentMenu: () => items, saveOrder: saveOrder)],
    ),
    body: MenuView(state: MenuSyncState.synced, items: items, cart: cart),
  ),
);

class FakeLocalOrdersStore extends Fake implements LocalDatabase {
  FakeLocalOrdersStore(this.order);

  Map<String, Object?> order;

  @override
  Future<List<Map<String, Object?>>> localOrders() async => [order];

  @override
  Future<Map<String, Object?>?> localOrder(String orderId) async => order['id'] == orderId ? order : null;

  @override
  Future<List<Map<String, Object?>>> localOrderItems(String orderId) async => [
    {'name': '米粉', 'show_name': '湯', 'price': 50, 'quantity': 2},
  ];
}

class TestOrderSync extends OrderSyncController {
  TestOrderSync(LocalDatabase store) : super(store: store, hasSession: () => false, submitOrder: (_, _) async => {});

  void emit(OrderSyncState value, int count) {
    state = value;
    pendingCount = count;
    notifyListeners();
  }
}

Map<String, Object?> localOrder() => {
  'id': 'order-1',
  'serial': 10,
  'serial_status': 'PROVISIONAL',
  'business_date': '2026-11-13',
  'sync_status': 'PENDING_SYNC',
  'order_date': '2026-11-13T02:00:00Z',
  'total_price': 100,
  'get_pay': 80,
  'uber': 1,
  'takeout': 0,
  'sauerkraut': 0,
  'ginger': 1,
  'chili': 1,
  'chili_level': 3,
  'mark': '少湯',
};

Map<String, Object?> menuItem({required String id, required String name, String subName = '', required int price}) => {
  'id': id,
  'sid': 43,
  'item_type': 'product',
  'menu_row': '2',
  'name': name,
  'sub_name': subName,
  'price': price,
  'is_available': 1,
  'source': 'CLOUD_VISIBLE',
};
