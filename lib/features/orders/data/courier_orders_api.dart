import 'dart:math' as math;

import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/features/orders/domain/courier_order_item.dart';

class CourierOrdersApi {
  const CourierOrdersApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<CourierOrderItem>> getCourierOrders({
    int page = 1,
    int limit = 100,
    String? status,
    String? from,
    String? to,
  }) {
    return _loadPaged(
      '/orders/courier/my',
      page: page,
      limit: limit,
      status: status,
    );
  }

  Future<List<CourierOrderItem>> getCourierHistory({
    int page = 1,
    int limit = 100,
    String? status,
    String? from,
    String? to,
  }) {
    return _loadPaged(
      '/orders/courier/history',
      page: page,
      limit: limit,
      status: status,
    );
  }

  Future<List<CourierOrderItem>> _loadPaged(
    String endpoint, {
    required int page,
    required int limit,
    String? status,
  }) async {
    final requested = limit.clamp(1, 1000);
    final items = <CourierOrderItem>[];
    var currentPage = math.max(1, page);

    while (items.length < requested) {
      final pageSize = math.min(100, requested - items.length);
      final query = <String, String>{
        'page': '$currentPage',
        'limit': '$pageSize',
      };

      final normalizedStatus = (status ?? '').trim();
      if (normalizedStatus.isNotEmpty) query['status'] = normalizedStatus;

      final response = await _apiClient.get(_buildPath(endpoint, query));
      final pageItems = _parseOrderList(response);
      items.addAll(pageItems);

      if (pageItems.length < pageSize) break;
      currentPage++;
    }

    return items.take(requested).toList(growable: false);
  }

  Future<CourierOrderItem?> getActiveOrder() async {
    final dynamic response = await _apiClient.get('/orders/courier/active');

    if (response == null) return null;

    final map = _asMap(response);
    if (map.isEmpty) return null;

    final wrapped =
        _readMap(map, const ['item']) ??
        _readMap(map, const ['data']) ??
        map;

    if (wrapped.isEmpty || _isPickup(wrapped)) return null;
    return CourierOrderItem.fromJson(wrapped);
  }

  List<CourierOrderItem> _parseOrderList(dynamic response) {
    final itemsRaw =
        _extractList(response, const ['items']) ??
        _extractList(response, const ['data', 'items']) ??
        _extractList(response, const ['orders']) ??
        _extractList(response, const ['data', 'orders']) ??
        (response is List ? response : const []);

    return itemsRaw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => !_isPickup(item))
        .map(CourierOrderItem.fromJson)
        .toList(growable: false);
  }

  bool _isPickup(Map<String, dynamic> item) {
    return (item['fulfillmentType'] ?? '')
            .toString()
            .trim()
            .toUpperCase() ==
        'PICKUP';
  }

  String _buildPath(String basePath, Map<String, String> query) {
    return Uri(path: basePath, queryParameters: query).toString();
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static List<dynamic>? _extractList(dynamic json, List<String> path) {
    dynamic current = json;

    for (final part in path) {
      if (current is Map<String, dynamic> && current.containsKey(part)) {
        current = current[part];
      } else if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }

    return current is List ? current : null;
  }

  static Map<String, dynamic>? _readMap(
    Map<String, dynamic> json,
    List<String> path,
  ) {
    dynamic current = json;

    for (final part in path) {
      if (current is Map<String, dynamic> && current.containsKey(part)) {
        current = current[part];
      } else if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }

    if (current is Map<String, dynamic>) return current;
    if (current is Map) return Map<String, dynamic>.from(current);
    return null;
  }
}
