import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/features/notifications/domain/courier_notification_item.dart';

class CourierNotificationsApi {
  CourierNotificationsApi({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  Future<CourierNotificationsResult> getNotifications({
    int page = 1,
    int limit = 50,
  }) async {
    final dynamic response = await _apiClient.get(
      '/notifications?page=$page&limit=$limit',
    );

    final itemsRaw =
        _extractList(response, const ['items']) ??
        _extractList(response, const ['data', 'items']) ??
        _extractList(response, const ['notifications']) ??
        _extractList(response, const ['data', 'notifications']) ??
        (response is List ? response : const <dynamic>[]);

    final items = itemsRaw
        .whereType<Map>()
        .map(
          (item) =>
              CourierNotificationItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();

    final map = _asMap(response);

    final unreadCount =
        _readInt(map['unreadCount']) ??
        _readInt(map['count']) ??
        _readInt(_readMap(map, const ['meta'])?['unreadCount']) ??
        _readInt(_readMap(map, const ['data'])?['unreadCount']) ??
        items.where((item) => !item.isRead).length;

    return CourierNotificationsResult(items: items, unreadCount: unreadCount);
  }

  Future<int> getUnreadCount() async {
    try {
      final dynamic response = await _apiClient.get(
        '/notifications/unread-count',
      );

      final map = _asMap(response);

      return _readInt(map['count']) ??
          _readInt(map['unreadCount']) ??
          _readInt(_readMap(map, const ['data'])?['count']) ??
          _readInt(_readMap(map, const ['data'])?['unreadCount']) ??
          0;
    } catch (_) {
      final result = await getNotifications(page: 1, limit: 50);
      return result.unreadCount;
    }
  }

  Future<void> markRead(String id) async {
    final normalized = id.trim();

    if (normalized.isEmpty) {
      return;
    }

    await _apiClient.post('/notifications/$normalized/read', {});
  }

  Future<void> markAllRead() async {
    await _apiClient.post('/notifications/read-all', {});
  }

  void dispose() {
    _apiClient.dispose();
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return <String, dynamic>{};
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

    if (current is Map<String, dynamic>) {
      return current;
    }

    if (current is Map) {
      return Map<String, dynamic>.from(current);
    }

    return null;
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

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.round();
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '');
  }
}

class CourierNotificationsResult {
  const CourierNotificationsResult({
    required this.items,
    required this.unreadCount,
  });

  final List<CourierNotificationItem> items;
  final int unreadCount;
}
