import 'package:flutter/foundation.dart';

enum ServiceType { dineIn, takeout, uber }

class OrderOptions extends ChangeNotifier {
  ServiceType? _serviceType;
  bool _excludeSauerkraut = false;
  bool _excludeGinger = false;
  int _spiceLevel = 0;
  String _mark = '';
  String _paymentInput = '';

  ServiceType? get serviceType => _serviceType;
  bool get excludeSauerkraut => _excludeSauerkraut;
  bool get excludeGinger => _excludeGinger;
  bool get sauerkraut => !_excludeSauerkraut;
  bool get ginger => !_excludeGinger;
  int get spiceLevel => _spiceLevel;
  String get mark => _mark;
  String get paymentInput => _paymentInput;
  int? get receivedAmount => _paymentInput.isEmpty ? 0 : int.tryParse(_paymentInput);

  int? changeFor(int total) {
    final received = receivedAmount;
    if (received == null) return null;
    return received >= total ? received - total : 0;
  }

  void setServiceType(ServiceType? value) {
    if (_serviceType == value) return;
    _serviceType = value;
    notifyListeners();
  }

  void setExcludeSauerkraut(bool value) {
    if (_excludeSauerkraut == value) return;
    _excludeSauerkraut = value;
    notifyListeners();
  }

  void setExcludeGinger(bool value) {
    if (_excludeGinger == value) return;
    _excludeGinger = value;
    notifyListeners();
  }

  void setSpiceLevel(int value) {
    RangeError.checkValueInInterval(value, 0, 3, 'spiceLevel');
    if (_spiceLevel == value) return;
    _spiceLevel = value;
    notifyListeners();
  }

  void setMark(String value) {
    if (_mark == value) return;
    _mark = value;
    notifyListeners();
  }

  void setPaymentInput(String value) {
    if (!RegExp(r'^\d*$').hasMatch(value)) throw const FormatException('Payment must contain only digits');
    if (_paymentInput == value) return;
    _paymentInput = value;
    notifyListeners();
  }

  void reset() {
    _serviceType = null;
    _excludeSauerkraut = false;
    _excludeGinger = false;
    _spiceLevel = 0;
    _mark = '';
    _paymentInput = '';
    notifyListeners();
  }
}
