import 'package:flutter_test/flutter_test.dart';
import 'package:jetkiz_courier_app/features/orders/domain/courier_order_details.dart';
import 'package:jetkiz_courier_app/features/orders/domain/courier_order_item.dart';

void main() {
  final base = <String, dynamic>{
    'id': 'order-1',
    'number': 101,
    'status': 'READY',
    'createdAt': '2026-08-29T10:00:00.000Z',
    'fulfillmentType': 'DELIVERY',
    'courierFee': 722,
    'courierFeeGross': 850,
    'courierCommissionPctApplied': 15,
    'courierCommissionAmount': 128,
    'restaurant': {
      'nameRu': 'Тестовый ресторан',
      'address': 'ул. Абылай хана, 1',
    },
    'address': {
      'address': 'ул. Ауэзова, 10',
      'entrance': '2',
      'floor': '4',
      'door': '45',
      'intercom': '45К',
    },
    'items': [
      {'id': 'i1', 'title': 'Бургер', 'quantity': 1, 'price': 2500},
    ],
  };

  test('delivery order exposes pickup action and full address', () {
    final order = CourierOrderDetails.fromJson(base);

    expect(order.isDelivery, isTrue);
    expect(order.canMarkPickedUp, isTrue);
    expect(order.canMarkDelivered, isFalse);
    expect(order.clientAddress, contains('подъезд: 2'));
    expect(order.clientAddress, contains('этаж: 4'));
    expect(order.clientAddress, contains('квартира/дверь: 45'));
    expect(order.clientAddress, contains('домофон: 45К'));
  });

  test('courier finance snapshot is parsed without recomputing business rules', () {
    final order = CourierOrderDetails.fromJson(base);

    expect(order.courierFeeGross, 850);
    expect(order.courierCommissionPctApplied, 15);
    expect(order.courierCommissionAmount, 128);
    expect(order.courierNetAmount, 722);
  });

  test('pickup order cannot expose courier actions', () {
    final order = CourierOrderDetails.fromJson({
      ...base,
      'fulfillmentType': 'PICKUP',
    });

    expect(order.isDelivery, isFalse);
    expect(order.canMarkPickedUp, isFalse);
    expect(order.canMarkDelivered, isFalse);
  });

  test('required order fields fail closed instead of fabricating values', () {
    expect(
      () => CourierOrderItem.fromJson({
        'status': 'READY',
        'createdAt': '2026-08-29T10:00:00.000Z',
      }),
      throwsFormatException,
    );
  });
}
