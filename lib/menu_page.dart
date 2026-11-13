import 'dart:async';

import 'package:flutter/material.dart' hide MenuController;
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cart_controller.dart';
import 'local_database.dart';
import 'local_orders_page.dart';
import 'menu_controller.dart';
import 'order_draft.dart';
import 'order_options.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key, required this.client});

  final SupabaseClient? client;

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> with WidgetsBindingObserver {
  final CartController _cart = CartController();
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
    _cart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromRGBO(201, 113, 23, 1),
        foregroundColor: Colors.white,
        titleSpacing: 12,
        title: const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('千囍蔬食堂')),
        actions: [
          SizedBox(
            width: MediaQuery.sizeOf(context).width < 400 ? 72 : 180,
            height: kToolbarHeight,
            child: controller == null
                ? MenuSyncStatus(
                    state: MenuSyncState.loading,
                    items: const [],
                    realtimeConfigured: widget.client != null,
                  )
                : ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => MenuSyncStatus(
                      state: controller.state,
                      items: controller.items,
                      realtimeConfigured: widget.client != null,
                      realtimeStatus: _realtimeStatus,
                      lastRealtimeEvent: _lastRealtimeEvent,
                    ),
                  ),
          ),
          MenuCartAction(
            cart: _cart,
            menuUpdates: controller,
            currentMenu: () => controller?.items ?? const [],
            saveOrder: controller?.store.savePendingOrder,
          ),
          IconButton(
            tooltip: '訂單',
            onPressed: controller == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LocalOrdersPage(store: controller.store, client: widget.client),
                    ),
                  ),
            icon: const Icon(Icons.receipt_long_outlined),
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
              builder: (context, _) => MenuView(items: controller.items, state: controller.state, cart: _cart),
            ),
    );
  }
}

class MenuSyncStatus extends StatelessWidget {
  const MenuSyncStatus({
    super.key,
    required this.state,
    required this.items,
    required this.realtimeConfigured,
    this.realtimeStatus,
    this.lastRealtimeEvent,
  });

  final MenuSyncState state;
  final List<Map<String, Object?>> items;
  final bool realtimeConfigured;
  final RealtimeSubscribeStatus? realtimeStatus;
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
    final eventLabel = lastRealtimeEvent == null
        ? null
        : '最近即時事件 ${TimeOfDay.fromDateTime(lastRealtimeEvent!).format(context)}';
    return Tooltip(
      message: [status, realtimeLabel, ?eventLabel].join('\n'),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(status, style: const TextStyle(fontSize: 11, color: Colors.white)),
            Text(realtimeLabel, style: const TextStyle(fontSize: 11, color: Colors.white)),
            if (eventLabel != null) Text(eventLabel, style: const TextStyle(fontSize: 11, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class MenuCartAction extends StatelessWidget {
  const MenuCartAction({super.key, required this.cart, required this.currentMenu, this.menuUpdates, this.saveOrder});

  final CartController cart;
  final List<Map<String, Object?>> Function() currentMenu;
  final Listenable? menuUpdates;
  final Future<SavedOrder> Function(OrderDraft)? saveOrder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([cart, ?menuUpdates]),
    builder: (context, _) {
      final conflict = cart.items.values.any((item) => cart.hasConflict(item, currentMenu()));
      return Tooltip(
        message: conflict ? '查看已選：菜單有變更，請檢查已選品項' : '查看已選',
        child: Semantics(
          label: '已選 ${cart.quantity} 項，總額 ${cart.total} 元${conflict ? '，菜單有變更' : ''}',
          button: true,
          enabled: cart.quantity > 0,
          child: InkWell(
            onTap: cart.quantity == 0
                ? null
                : () => _showSelectedItems(context, cart, currentMenu, menuUpdates, saveOrder),
            child: SizedBox(
              width: 60,
              height: kToolbarHeight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: 60,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Badge(
                        isLabelVisible: cart.quantity > 0,
                        label: Text(cart.quantity > 99 ? '99+' : '${cart.quantity}'),
                        child: Icon(conflict ? Icons.warning_amber_outlined : Icons.shopping_basket_outlined, size: 22),
                      ),
                      Text('NT\$ ${cart.total}', style: const TextStyle(fontSize: 10, color: Colors.white)),
                      if (conflict) const Text('需確認', style: TextStyle(fontSize: 10, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

void _showSelectedItems(
  BuildContext context,
  CartController cart,
  List<Map<String, Object?>> Function() currentMenu,
  Listenable? menuUpdates,
  Future<SavedOrder> Function(OrderDraft)? saveOrder,
) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _SelectedItemsSheet(
      parentContext: context,
      cart: cart,
      currentMenu: currentMenu,
      menuUpdates: menuUpdates,
      saveOrder: saveOrder,
    ),
  );
}

class _SelectedItemsSheet extends StatefulWidget {
  const _SelectedItemsSheet({
    required this.parentContext,
    required this.cart,
    required this.currentMenu,
    this.menuUpdates,
    this.saveOrder,
  });

  final BuildContext parentContext;
  final CartController cart;
  final List<Map<String, Object?>> Function() currentMenu;
  final Listenable? menuUpdates;
  final Future<SavedOrder> Function(OrderDraft)? saveOrder;

  @override
  State<_SelectedItemsSheet> createState() => _SelectedItemsSheetState();
}

class _SelectedItemsSheetState extends State<_SelectedItemsSheet> {
  bool _saving = false;
  String? _saveError;
  OrderDraft? _draft;

  @override
  void initState() {
    super.initState();
    widget.cart.addListener(_clearDraft);
    widget.cart.options.addListener(_clearDraft);
  }

  void _clearDraft() {
    if (!_saving) _draft = null;
  }

  @override
  void dispose() {
    widget.cart.removeListener(_clearDraft);
    widget.cart.options.removeListener(_clearDraft);
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || widget.saveOrder == null) return;
    final cart = widget.cart;
    try {
      if (cart.items.values.any((item) => cart.hasConflict(item, widget.currentMenu()))) {
        throw OrderMenuChangedException();
      }
      _draft ??= OrderDraft.fromCart(cart);
    } on FormatException catch (error) {
      setState(() => _saveError = error.message);
      return;
    } on OrderMenuChangedException {
      setState(() => _saveError = '菜單已變更，請檢查已選品項');
      return;
    } catch (error) {
      logMenuSync('local order draft failed type=${error.runtimeType}');
      setState(() => _saveError = '無法建立訂單，請檢查選餐資料');
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = await widget.saveOrder!(_draft!);
      if (!mounted) return;
      cart.clear();
      Navigator.of(context).pop();
      if (!widget.parentContext.mounted) return;
      await showDialog<void>(
        context: widget.parentContext,
        builder: (context) => AlertDialog(
          title: const Text('已存入本機'),
          content: Text('暫定流水號 ${saved.serial}\n${saved.businessDate}\n待同步，尚未上傳或列印。'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('確定'))],
        ),
      );
    } on OrderMenuChangedException {
      if (mounted) setState(() => _saveError = '菜單已變更，請檢查已選品項');
    } on UnknownOrderDateException {
      if (mounted) setState(() => _saveError = '本機舊訂單日期缺少時區，無法產生暫定流水號');
    } catch (error) {
      logMenuSync('local order save failed type=${error.runtimeType}');
      if (mounted) setState(() => _saveError = '存單失敗，已保留選餐，請重試');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = widget.cart;
    final currentMenu = widget.currentMenu;
    return PopScope(
      canPop: !_saving,
      child: ListenableBuilder(
        listenable: Listenable.merge([cart, cart.options, ?widget.menuUpdates]),
        builder: (context, _) => AbsorbPointer(
          absorbing: _saving,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: SizedBox(
                height: (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom) * 0.75,
                child: ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text('已選品項', style: Theme.of(context).textTheme.titleLarge)),
                          Text('NT\$ ${cart.total}', style: Theme.of(context).textTheme.titleMedium),
                          IconButton(
                            tooltip: '關閉已選品項',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: SegmentedButton<ServiceType>(
                        segments: const [
                          ButtonSegment(value: ServiceType.dineIn, label: Text('內用')),
                          ButtonSegment(value: ServiceType.takeout, label: Text('外帶')),
                          ButtonSegment(value: ServiceType.uber, label: Text('Uber')),
                        ],
                        selected: {if (cart.options.serviceType != null) cart.options.serviceType!},
                        emptySelectionAllowed: true,
                        onSelectionChanged: (selection) =>
                            cart.options.setServiceType(selection.isEmpty ? null : selection.single),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: TextFormField(
                        key: const ValueKey('order-payment'),
                        initialValue: cart.options.paymentInput,
                        onChanged: cart.options.setPaymentInput,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: '實收金額',
                          prefixIcon: const Icon(Icons.payments_outlined),
                          errorText: cart.options.receivedAmount == null ? '金額過大，請重新輸入' : null,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Text(
                        cart.options.changeFor(cart.total) == null
                            ? '找零：--'
                            : '找零：NT\$ ${cart.options.changeFor(cart.total)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: TextFormField(
                        key: const ValueKey('order-mark'),
                        initialValue: cart.options.mark,
                        onChanged: cart.options.setMark,
                        decoration: const InputDecoration(labelText: '標註 / 備註'),
                      ),
                    ),
                    if (cart.items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('尚未選餐')),
                      )
                    else
                      ...cart.items.entries.map((entry) {
                        final selected = entry.value;
                        final item = selected.snapshot;
                        final conflict = cart.hasConflict(selected, currentMenu());
                        final subName = item['sub_name'] as String;
                        final name = '${item['name']}${subName.isEmpty ? '' : '-$subName'}';
                        return ListTile(
                          title: Text(name),
                          subtitle: Text(conflict ? '菜單已變更或停售，請移除後重新選擇' : '單價 NT\$ ${item['price']}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '減少 $name',
                                onPressed: () => cart.removeOne(entry.key),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                              SizedBox(width: 28, child: Text('${selected.quantity}', textAlign: TextAlign.center)),
                              IconButton(
                                tooltip: '增加 $name',
                                onPressed: conflict ? null : () => cart.add(item),
                                icon: const Icon(Icons.add_circle_outline),
                              ),
                              IconButton(
                                tooltip: '移除 $name',
                                onPressed: () => cart.removeItem(entry.key),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        );
                      }),
                    if (_saveError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text(_saveError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    if (widget.saveOrder != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.save_outlined),
                          label: Text(_saving ? '儲存中' : '存入本機'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MenuView extends StatefulWidget {
  const MenuView({super.key, required this.items, required this.state, this.cart});

  final List<Map<String, Object?>> items;
  final MenuSyncState state;
  final CartController? cart;

  @override
  State<MenuView> createState() => _MenuViewState();
}

class _MenuViewState extends State<MenuView> {
  late CartController _cart;

  @override
  void initState() {
    super.initState();
    _cart = widget.cart ?? CartController();
  }

  @override
  void didUpdateWidget(covariant MenuView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cart != widget.cart) {
      if (oldWidget.cart == null) _cart.dispose();
      _cart = widget.cart ?? CartController();
    }
  }

  @override
  void dispose() {
    if (widget.cart == null) _cart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final state = widget.state;
    return ListenableBuilder(
      listenable: _cart,
      builder: (context, _) => Column(
        children: [
          Expanded(
            child: items.isEmpty
                ? Center(child: Text(state == MenuSyncState.loading ? '載入中' : '目前沒有可顯示的菜單'))
                : LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: constraints.maxWidth < 600 ? 600 : constraints.maxWidth,
                        child: SingleChildScrollView(
                          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: ['1', '2', '3'].map((row) {
                              final rowItems = items.where((item) => item['menu_row'] == row);
                              return Expanded(
                                child: Column(
                                  children: [
                                    ...rowItems.map((item) {
                                      final selected = _cart.items[cartItemKey(item)];
                                      final conflict = selected != null && _cart.hasConflict(selected, items);
                                      return _MenuTableRow(
                                        key: ValueKey(cartItemKey(item)),
                                        item: item,
                                        quantity: _cart.quantityFor(item),
                                        conflict: conflict,
                                        onQuantityChanged: (quantity) => _cart.setQuantity(item, quantity),
                                      );
                                    }),
                                    if (row == '3') _IngredientOptions(options: _cart.options),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _IngredientOptions extends StatelessWidget {
  const _IngredientOptions({required this.options});

  final OrderOptions options;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: options,
    builder: (context, _) => Column(
      children: [
        _optionRow('不加酸菜', options.excludeSauerkraut, (value) => options.setExcludeSauerkraut(value)),
        _optionRow('不加薑絲', options.excludeGinger, (value) => options.setExcludeGinger(value)),
        for (final (index, label) in ['不辣', '小辣', '中辣', '大辣'].indexed)
          _optionRow(label, options.spiceLevel == index, (value) {
            if (value) options.setSpiceLevel(index);
          }),
      ],
    ),
  );

  Widget _optionRow(String label, bool selected, ValueChanged<bool> onChanged) => Container(
    height: 40,
    decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 0.5)),
    child: Row(
      children: [
        Expanded(
          flex: 9,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Checkbox(
            key: ValueKey('option:$label'),
            value: selected,
            onChanged: (value) => onChanged(value ?? false),
            semanticLabel: label,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    ),
  );
}

class _MenuTableRow extends StatelessWidget {
  const _MenuTableRow({
    super.key,
    required this.item,
    required this.quantity,
    required this.conflict,
    required this.onQuantityChanged,
  });

  final Map<String, Object?> item;
  final int quantity;
  final bool conflict;
  final bool Function(int) onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    final subName = item['sub_name'] as String;
    final name = '${item['name']}${subName.isEmpty ? '' : '-$subName'}';
    final available = item['is_available'] == 1;
    const textStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black);
    return Container(
      height: 40,
      decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 0.5)),
      child: Row(
        children: [
          Expanded(
            flex: 7,
            child: Container(
              height: double.infinity,
              color: item['item_type'] == 'mainProduct' ? Colors.amberAccent : null,
              child: Tooltip(
                message: conflict ? '$name：菜單已變更，請檢查已選品項' : (!available ? '$name：停售' : name),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text.rich(
                      TextSpan(
                        text: item['name'] as String,
                        style: textStyle,
                        children: [
                          if (subName.isNotEmpty)
                            TextSpan(
                              text: '-$subName',
                              style: TextStyle(color: subName == '乾' ? Colors.blueGrey : Colors.black),
                            ),
                          if (!available)
                            const TextSpan(
                              text: ' 停售',
                              style: TextStyle(color: Colors.red),
                            ),
                        ],
                      ),
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              height: double.infinity,
              decoration: const BoxDecoration(
                border: Border.symmetric(vertical: BorderSide(color: Colors.black, width: 0.5)),
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${item['price']}', style: textStyle),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: _QuantityField(
              itemKey: cartItemKey(item),
              name: name,
              quantity: quantity,
              enabled: available && !conflict,
              onChanged: onQuantityChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuantityField extends StatefulWidget {
  const _QuantityField({
    required this.itemKey,
    required this.name,
    required this.quantity,
    required this.enabled,
    required this.onChanged,
  });

  final String itemKey;
  final String name;
  final int quantity;
  final bool enabled;
  final bool Function(int) onChanged;

  @override
  State<_QuantityField> createState() => _QuantityFieldState();
}

class _QuantityFieldState extends State<_QuantityField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.quantity == 0 ? '' : '${widget.quantity}');
  }

  @override
  void didUpdateWidget(covariant _QuantityField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quantity != widget.quantity && int.tryParse(_controller.text) != widget.quantity) {
      _controller.text = widget.quantity == 0 ? '' : '${widget.quantity}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '數量 ${widget.name}',
    child: TextField(
      key: ValueKey('quantity:${widget.itemKey}'),
      controller: _controller,
      enabled: widget.enabled,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.red),
      decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
      onChanged: (value) {
        final quantity = value.isEmpty ? 0 : int.tryParse(value);
        if (quantity == null || !widget.onChanged(quantity)) {
          _controller.text = widget.quantity == 0 ? '' : '${widget.quantity}';
          _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
        }
      },
    ),
  );
}
