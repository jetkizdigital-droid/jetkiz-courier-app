import 'package:flutter_test/flutter_test.dart';
import 'package:jetkiz_courier_app/core/localization/courier_locale.dart';
import 'package:jetkiz_courier_app/core/push/push_message_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('courier push payload', () {
    test('opens assigned order details from production payload', () {
      final intent = PushNavigationIntent.fromData({
        'app': 'courier',
        'type': 'courier_order',
        'route': 'orders',
        'screen': 'order_details',
        'action': 'open_order',
        'orderId': 'order-123',
        'orderNumber': '456',
        'status': 'READY',
        'channelId': 'courier_orders_v2',
        'sound': 'courier_order',
      });

      expect(intent, isNotNull);
      expect(intent!.type, PushNavigationIntentType.order);
      expect(intent.orderId, 'order-123');
      expect(intent.orderNumber, 456);
      expect(intent.screen, 'order_details');
      expect(intent.action, 'open_order');
    });

    test('order details screen without order id falls back to orders list', () {
      final intent = PushNavigationIntent.fromData({
        'app': 'courier',
        'type': 'courier_order',
        'screen': 'order_details',
      });

      expect(intent, isNotNull);
      expect(intent!.type, PushNavigationIntentType.ordersList);
    });
  });

  group('courier home localization regressions', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('Russian home keys resolve to readable labels', () async {
      final locale = CourierLocaleController.instance;
      await locale.selectBeforeLogin('ru');

      expect(locale.t('home.earnings'), 'Заработано сегодня');
      expect(locale.t('home.online'), 'Вы на линии');
      expect(locale.t('home.order'), 'Заказ');
      expect(locale.t('home.goOnline'), 'Выйти на линию');
      expect(locale.t('home.goOffline'), 'Выйти с линии');
      expect(
        locale.t('home.onlineDescription'),
        'GPS активен для назначения и доставки',
      );
    });

    test('Kazakh home keys resolve to readable labels', () async {
      final locale = CourierLocaleController.instance;
      await locale.selectBeforeLogin('kk');

      expect(locale.t('home.earnings'), 'Бүгінгі табыс');
      expect(locale.t('home.online'), 'Сіз желідесіз');
      expect(locale.t('home.order'), 'Тапсырыс');
      expect(locale.t('home.goOnline'), 'Желіге шығу');
      expect(locale.t('home.goOffline'), 'Желіден шығу');
      expect(
        locale.t('home.onlineDescription'),
        'GPS тағайындау және жеткізу үшін қосулы',
      );
    });
  });
}
