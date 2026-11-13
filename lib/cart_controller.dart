import 'dart:collection';

import 'package:flutter/foundation.dart';

String cartItemKey(Map<String, Object?> item) {
  final legacyId = item['legacy_id'] as String?;
  return legacyId == null ? 'id:${item['id']}' : 'legacy:$legacyId';
}

class CartItem {
  CartItem(Map<String, Object?> item) : snapshot = Map.unmodifiable(item);

  final Map<String, Object?> snapshot;
  int quantity = 1;

  int get total => (snapshot['price'] as int) * quantity;
}

class CartController extends ChangeNotifier {
  final Map<String, CartItem> _items = {};

  UnmodifiableMapView<String, CartItem> get items => UnmodifiableMapView(_items);
  int get total => _items.values.fold(0, (total, item) => total + item.total);
  int get quantity => _items.values.fold(0, (total, item) => total + item.quantity);

  bool add(Map<String, Object?> item) {
    if (item['is_available'] != 1) return false;
    final key = cartItemKey(item);
    final selected = _items[key];
    if (selected != null && _changed(selected.snapshot, item)) return false;
    if (selected == null) {
      _items[key] = CartItem(item);
    } else {
      selected.quantity++;
    }
    notifyListeners();
    return true;
  }

  bool setQuantity(Map<String, Object?> item, int quantity) {
    final key = cartItemKey(item);
    if (quantity < 0) return false;
    if (quantity == 0) {
      removeItem(key);
      return true;
    }
    if (item['is_available'] != 1) return false;
    final selected = _items[key];
    if (selected != null && _changed(selected.snapshot, item)) return false;
    if (selected == null) {
      _items[key] = CartItem(item)..quantity = quantity;
    } else if (selected.quantity == quantity) {
      return true;
    } else {
      selected.quantity = quantity;
    }
    notifyListeners();
    return true;
  }

  void removeOne(String key) {
    final item = _items[key];
    if (item == null) return;
    if (item.quantity == 1) {
      _items.remove(key);
    } else {
      item.quantity--;
    }
    notifyListeners();
  }

  void removeItem(String key) {
    if (_items.remove(key) != null) notifyListeners();
  }

  int quantityFor(Map<String, Object?> item) => _items[cartItemKey(item)]?.quantity ?? 0;

  bool hasConflict(CartItem selected, List<Map<String, Object?>> menu) {
    final key = cartItemKey(selected.snapshot);
    final current = menu.where((item) => cartItemKey(item) == key);
    return current.isEmpty || current.length > 1 || _changed(selected.snapshot, current.single);
  }

  bool _changed(Map<String, Object?> selected, Map<String, Object?> current) =>
      current['is_available'] != 1 ||
      selected['name'] != current['name'] ||
      selected['sub_name'] != current['sub_name'] ||
      selected['price'] != current['price'];
}
