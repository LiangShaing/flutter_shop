import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_shop/order_options.dart';

void main() {
  test('matches legacy ingredient and spice defaults without choosing a service type', () {
    final options = OrderOptions();
    expect(options.serviceType, isNull);
    expect(options.sauerkraut, isTrue);
    expect(options.ginger, isTrue);
    expect(options.spiceLevel, 0);
    expect(options.mark, isEmpty);
    expect(options.receivedAmount, 0);
    options.dispose();
  });

  test('retains a single service type and independent ingredient choices', () {
    final options = OrderOptions();
    var notifications = 0;
    options.addListener(() => notifications++);
    options.setServiceType(ServiceType.takeout);
    options.setServiceType(ServiceType.uber);
    options.setExcludeSauerkraut(true);
    options.setExcludeGinger(true);
    options.setSpiceLevel(2);
    options.setMark('少湯');
    expect(options.serviceType, ServiceType.uber);
    expect(options.sauerkraut, isFalse);
    expect(options.ginger, isFalse);
    expect(options.spiceLevel, 2);
    expect(options.mark, '少湯');
    expect(notifications, 6);
    expect(() => options.setSpiceLevel(4), throwsRangeError);
    expect(options.spiceLevel, 2);
    options.dispose();
  });

  test('calculates legacy change without inferring payment status', () {
    final options = OrderOptions();
    expect(options.changeFor(120), 0);
    options.setPaymentInput('100');
    expect(options.receivedAmount, 100);
    expect(options.changeFor(120), 0);
    options.setPaymentInput('120');
    expect(options.changeFor(120), 0);
    options.setPaymentInput('150');
    expect(options.changeFor(120), 30);
    options.setServiceType(ServiceType.uber);
    expect(options.changeFor(120), 30);
    options.setPaymentInput('');
    expect(options.receivedAmount, 0);
    expect(options.changeFor(120), 0);
    options.dispose();
  });

  test('rejects invalid values and flags amounts too large to parse', () {
    final options = OrderOptions();
    expect(() => options.setPaymentInput('-1'), throwsFormatException);
    expect(() => options.setPaymentInput('1.5'), throwsFormatException);
    options.setPaymentInput('999999999999999999999999999999');
    expect(options.receivedAmount, isNull);
    expect(options.changeFor(100), isNull);
    options.dispose();
  });
}
