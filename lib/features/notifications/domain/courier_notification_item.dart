class CourierNotificationItem {
  const CourierNotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.createdAt,
    required this.data,
    required this.orderId,
    required this.screen,
    required this.route,
    required this.action,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final DateTime? createdAt;
  final Map<String, dynamic> data;
  final String? orderId;
  final String? screen;
  final String? route;
  final String? action;

  factory CourierNotificationItem.fromJson(Map<String, dynamic> json) {
    final data =
        _readMap(json['data']) ??
        _readMap(json['payload']) ??
        _readMap(json['metadata']) ??
        <String, dynamic>{};

    final id = _readString(json['id']);

    final title = _firstNotEmpty([
      json['title'],
      json['titleRu'],
      data['title'],
      data['titleRu'],
    ]);

    final body = _firstNotEmpty([
      json['body'],
      json['message'],
      json['text'],
      json['bodyRu'],
      data['body'],
      data['message'],
      data['text'],
      data['bodyRu'],
    ]);

    final type = _firstNotEmpty([
      json['type'],
      json['notificationType'],
      data['type'],
    ]);

    final isRead =
        _readBool(json['isRead']) ||
        _readBool(json['read']) ||
        json['readAt'] != null;

    final createdAt = _readDateTime(
      json['createdAt'] ?? json['created_at'] ?? json['sentAt'],
    );

    final orderId = _firstNullableNotEmpty([
      json['orderId'],
      json['order_id'],
      data['orderId'],
      data['order_id'],
      data['id'],
    ]);

    final screen = _firstNullableNotEmpty([json['screen'], data['screen']]);

    final route = _firstNullableNotEmpty([json['route'], data['route']]);

    final action = _firstNullableNotEmpty([json['action'], data['action']]);

    return CourierNotificationItem(
      id: id,
      title: title.isEmpty ? 'Уведомление' : title,
      body: body,
      type: type,
      isRead: isRead,
      createdAt: createdAt,
      data: data,
      orderId: orderId,
      screen: screen,
      route: route,
      action: action,
    );
  }

  CourierNotificationItem copyWith({bool? isRead}) {
    return CourierNotificationItem(
      id: id,
      title: title,
      body: body,
      type: type,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      data: data,
      orderId: orderId,
      screen: screen,
      route: route,
      action: action,
    );
  }

  static Map<String, dynamic>? _readMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return null;
  }

  static String _readString(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  static String _firstNotEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';

      if (text.isNotEmpty) {
        return text;
      }
    }

    return '';
  }

  static String? _firstNullableNotEmpty(List<dynamic> values) {
    final text = _firstNotEmpty(values);
    return text.isEmpty ? null : text;
  }

  static bool _readBool(dynamic value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final text = value?.toString().trim().toLowerCase() ?? '';

    return text == 'true' || text == '1' || text == 'yes';
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    return DateTime.tryParse(value.toString());
  }
}
