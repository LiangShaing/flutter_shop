import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_shop/cart_controller.dart';
import 'package:flutter_shop/order_options.dart';

void main() {
  test('adds and removes quantities using integer prices', () {
    final cart = CartController();
    final first = item(id: '1', price: 35);
    final second = item(id: '2', price: 50);
    expect(cart.add(first), isTrue);
    expect(cart.add(first), isTrue);
    expect(cart.add(second), isTrue);
    expect(cart.quantity, 3);
    expect(cart.total, 120);
    cart.removeOne(cartItemKey(first));
    expect(cart.quantity, 2);
    expect(cart.total, 85);
    cart.removeOne(cartItemKey(first));
    expect(cart.quantityFor(first), 0);
    expect(cart.total, 50);
    cart.dispose();
  });

  test('keeps selection snapshots and detects changes or unavailability', () {
    final cart = CartController();
    final original = item(id: '1', price: 35);
    cart.add(original);
    original['price'] = 40;
    expect(cart.total, 35);
    expect(cart.hasConflict(cart.items.values.single, [original]), isTrue);
    expect(cart.add(original), isFalse);
    expect(cart.hasConflict(cart.items.values.single, []), isTrue);
    expect(cart.add({...original, 'is_available': 0}), isFalse);
    cart.dispose();
  });

  test('matches bundled and cloud versions by legacy id', () {
    final cart = CartController();
    final offline = {...item(id: 'offline', price: 50), 'legacy_id': 'old-1'};
    final cloud = {...offline, 'id': 'cloud'};
    cart.add(offline);
    expect(cart.hasConflict(cart.items.values.single, [cloud]), isFalse);
    expect(cart.add(cloud), isTrue);
    expect(cart.quantityFor(cloud), 2);
    expect(cart.total, 100);
    cart.dispose();
  });

  test('sets quantities directly without accepting stale prices', () {
    final cart = CartController();
    final original = item(id: '1', price: 35);
    expect(cart.setQuantity(original, 12), isTrue);
    expect(cart.total, 420);
    expect(cart.setQuantity({...original, 'price': 40}, 3), isFalse);
    expect(cart.total, 420);
    expect(cart.setQuantity(original, -1), isFalse);
    expect(cart.setQuantity(original, 0), isTrue);
    expect(cart.total, 0);
    cart.dispose();
  });

  test('detects changes to legacy identity and item type', () {
    final cart = CartController();
    final original = {...item(id: '1', price: 35), 'sid': 1, 'item_type': 'product'};
    cart.add(original);
    expect(
      cart.hasConflict(cart.items.values.single, [
        {...original, 'sid': 2},
      ]),
      isTrue,
    );
    expect(
      cart.hasConflict(cart.items.values.single, [
        {...original, 'item_type': 'other'},
      ]),
      isTrue,
    );
    cart.dispose();
  });

  test('clears the cart and all temporary order options', () {
    final cart = CartController();
    cart.add(item(id: '1', price: 35));
    cart.options.setServiceType(ServiceType.uber);
    cart.options.setExcludeSauerkraut(true);
    cart.options.setExcludeGinger(true);
    cart.options.setSpiceLevel(3);
    cart.options.setMark('少湯');
    cart.options.setPaymentInput('100');
    cart.clear();
    expect(cart.items, isEmpty);
    expect(cart.options.serviceType, isNull);
    expect(cart.options.sauerkraut, isTrue);
    expect(cart.options.ginger, isTrue);
    expect(cart.options.spiceLevel, 0);
    expect(cart.options.mark, isEmpty);
    expect(cart.options.receivedAmount, 0);
    cart.dispose();
  });
}

Map<String, Object?> item({required String id, required int price}) => {
  'id': id,
  'name': '米粉',
  'sub_name': '湯',
  'price': price,
  'is_available': 1,
};
