import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_shop/cart_controller.dart';
import 'package:flutter_shop/order_draft.dart';
import 'package:flutter_shop/order_options.dart';

void main() {
  test('copies order options and item snapshots with stable UUIDs', () {
    final cart = CartController();
    final menuItem = item();
    cart.setQuantity(menuItem, 2);
    cart.options.setServiceType(ServiceType.uber);
    cart.options.setSpiceLevel(3);
    cart.options.setPaymentInput('50');
    cart.options.setMark('少湯');
    final draft = OrderDraft.fromCart(cart, now: DateTime.utc(2026, 11, 12, 16));
    cart.setQuantity(menuItem, 3);
    cart.options.setSpiceLevel(0);
    expect(draft.serviceType, ServiceType.uber);
    expect(draft.spiceLevel, 3);
    expect(draft.receivedAmount, 50);
    expect(draft.mark, '少湯');
    expect(draft.total, 100);
    expect(draft.items.single.quantity, 2);
    expect(draft.id, isNot(draft.operationId));
    cart.dispose();
  });

  test('requires service type, items, a valid received amount and positive total', () {
    final cart = CartController();
    expect(() => OrderDraft.fromCart(cart), throwsFormatException);
    cart.options.setServiceType(ServiceType.takeout);
    expect(() => OrderDraft.fromCart(cart), throwsFormatException);
    cart.add(item());
    cart.options.setPaymentInput('99999999999999999999999999');
    expect(() => OrderDraft.fromCart(cart), throwsFormatException);
    cart.options.setPaymentInput('');
    cart.removeItem(cartItemKey(item()));
    cart.add({...item(), 'price': 0});
    expect(() => OrderDraft.fromCart(cart), throwsFormatException);
    cart.dispose();
  });
}

Map<String, Object?> item() => {
  'id': 'menu-1',
  'legacy_id': 'legacy-1',
  'sid': 43,
  'item_type': 'mainProduct',
  'name': '米粉',
  'sub_name': '湯',
  'price': 50,
  'is_available': 1,
};
