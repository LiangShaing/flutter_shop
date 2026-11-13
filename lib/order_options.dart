import 'package:flutter/foundation.dart';

enum ServiceType { dineIn, takeout, uber }

class OrderOptions extends ChangeNotifier {
  ServiceType? _serviceType;
  bool _excludeSauerkraut = false;
  bool _excludeGinger = false;
  int _spiceLevel = 0;
  String _mark = '';

  ServiceType? get serviceType => _serviceType;
  bool get excludeSauerkraut => _excludeSauerkraut;
  bool get excludeGinger => _excludeGinger;
  bool get sauerkraut => !_excludeSauerkraut;
  bool get ginger => !_excludeGinger;
  int get spiceLevel => _spiceLevel;
  String get mark => _mark;

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
}
