import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/features/orders/domain/courier_order_details.dart';

class CourierOrderDetailsApi {
  const CourierOrderDetailsApi(this._client);

  final ApiClient _client;

  Future<CourierOrderDetails> getOrderDetails(String orderId) async {
    return _parseDeliveryOrder(
      await _client.get('/orders/courier/$orderId'),
    );
  }

  Future<CourierOrderDetails> markPickedUp(String orderId) async {
    return _parseDeliveryOrder(
      await _client.patch(
        '/orders/courier/$orderId/status',
        {'status': 'ON_THE_WAY'},
      ),
    );
  }

  Future<CourierOrderDetails> markDelivered(String orderId) async {
    return _parseDeliveryOrder(
      await _client.patch(
        '/orders/courier/$orderId/status',
        {'status': 'DELIVERED'},
      ),
    );
  }

  CourierOrderDetails _parseDeliveryOrder(dynamic response) {
    final Map<String, dynamic> map;

    if (response is Map<String, dynamic>) {
      map = response;
    } else if (response is Map) {
      map = Map<String, dynamic>.from(response);
    } else {
      throw const FormatException('Некорректный ответ сервера по заказу');
    }

    final order = CourierOrderDetails.fromJson(map);

    if (!order.isDelivery) {
      throw const FormatException(
        'Самовывоз не должен быть доступен курьерскому приложению',
      );
    }

    return order;
  }
}
