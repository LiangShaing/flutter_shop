import 'package:uuid/uuid.dart';

import 'cart_controller.dart';
import 'order_options.dart';

class OrderDraftItem {
  const OrderDraftItem({
    required this.id,
    required this.menuId,
    required this.menuLegacyId,
    required this.sid,
    required this.itemType,
    required this.name,
    required this.subName,
    required this.price,
    required this.quantity,
  });

  final String id;
  final String menuId;
  final String? menuLegacyId;
  final int sid;
  final String itemType;
  final String name;
  final String subName;
  final int price;
  final int quantity;
}

class OrderDraft {
  OrderDraft._({
    required this.id,
    required this.operationId,
    required this.orderDate,
    required this.serviceType,
    required this.receivedAmount,
    required this.sauerkraut,
    required this.ginger,
    required this.spiceLevel,
    required this.mark,
    required this.items,
    required this.total,
  });

  factory OrderDraft.fromCart(CartController cart, {DateTime? now}) {
    final serviceType = cart.options.serviceType;
    if (serviceType == null) throw const FormatException('請選擇內用、外帶或 Uber');
    final receivedAmount = cart.options.receivedAmount;
    if (receivedAmount == null) throw const FormatException('實收金額過大，請重新輸入');
    if (cart.items.isEmpty) throw const FormatException('請先選餐');
    const uuid = Uuid();
    const maxInteger = 0x7fffffffffffffff;
    var total = 0;
    final items = <OrderDraftItem>[];
    for (final selected in cart.items.values) {
      final item = selected.snapshot;
      final price = item['price'] as int;
      final quantity = selected.quantity;
      if (price < 0 || quantity <= 0 || price > maxInteger ~/ quantity) {
        throw const FormatException('品項金額或數量無效');
      }
      final subtotal = price * quantity;
      if (subtotal > maxInteger - total) throw const FormatException('訂單金額過大');
      total += subtotal;
      items.add(
        OrderDraftItem(
          id: uuid.v4(),
          menuId: item['id'] as String,
          menuLegacyId: item['legacy_id'] as String?,
          sid: item['sid'] as int,
          itemType: item['item_type'] as String,
          name: item['name'] as String,
          subName: item['sub_name'] as String,
          price: price,
          quantity: quantity,
        ),
      );
    }
    if (total <= 0) throw const FormatException('總金額須大於 0');
    return OrderDraft._(
      id: uuid.v4(),
      operationId: uuid.v4(),
      orderDate: (now ?? DateTime.now()).toUtc(),
      serviceType: serviceType,
      receivedAmount: receivedAmount,
      sauerkraut: cart.options.sauerkraut,
      ginger: cart.options.ginger,
      spiceLevel: cart.options.spiceLevel,
      mark: cart.options.mark,
      items: List.unmodifiable(items),
      total: total,
    );
  }

  final String id;
  final String operationId;
  final DateTime orderDate;
  final ServiceType serviceType;
  final int receivedAmount;
  final bool sauerkraut;
  final bool ginger;
  final int spiceLevel;
  final String mark;
  final List<OrderDraftItem> items;
  final int total;
}
