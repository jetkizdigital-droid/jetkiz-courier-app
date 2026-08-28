class CourierOrderItem {
  const CourierOrderItem({
    required this.id,
    required this.number,
    required this.status,
    required this.createdAt,
    this.assignedAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.promisedAt,
    this.restaurantName,
    this.restaurantAddress,
    this.clientName,
    this.clientPhone,
    this.clientAddress,
    this.clientComment,
    this.leaveAtDoor = false,
    this.itemsCount = 0,
    this.totalAmount,
    this.courierFee,
    this.courierFeeGross,
    this.courierCommissionAmount,
  });

  final String id;
  final int number;
  final String status;
  final DateTime createdAt;

  final DateTime? assignedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final DateTime? promisedAt;

  final String? restaurantName;
  final String? restaurantAddress;

  final String? clientName;
  final String? clientPhone;
  final String? clientAddress;
  final String? clientComment;
  final bool leaveAtDoor;

  final int itemsCount;
  final int? totalAmount;

  final int? courierFee;
  final int? courierFeeGross;
  final int? courierCommissionAmount;

  bool get isDelivered => status.toUpperCase() == 'DELIVERED';

  bool get isCompleted => isDelivered;

  bool get isCanceled {
    final s = status.toUpperCase();
    return s == 'CANCELED' || s == 'CANCELLED';
  }

  bool get isOnTheWay => status.toUpperCase() == 'ON_THE_WAY';

  bool get needsPickup {
    final s = status.toUpperCase();
    return s == 'READY';
  }

  DateTime get relevantDate {
    return deliveredAt ?? pickedUpAt ?? assignedAt ?? promisedAt ?? createdAt;
  }

  String? get routeAddress {
    final value = clientAddress?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  int? get courierNetAmount {
    if (courierFee != null) return courierFee;
    if (courierFeeGross != null && courierCommissionAmount != null) {
      return courierFeeGross! - courierCommissionAmount!;
    }
    return courierFeeGross;
  }

  factory CourierOrderItem.fromJson(Map<String, dynamic> json) {
    final restaurant = _readMap(json, const ['restaurant']);
    final user = _readMap(json, const ['user']);
    final address = _readMap(json, const ['address']);

    final previewItems =
        _extractList(json, const ['items']) ??
        _extractList(json, const ['orderItems']) ??
        _extractList(json, const ['previewItems']) ??
        const [];

    final itemsCount =
        _readNullableInt(json, const ['itemsCount']) ??
        _readNullableInt(json, const ['totalItems']) ??
        _readNullableInt(json, const ['count']) ??
        _countItems(previewItems);

    return CourierOrderItem(
      id: _readString(json, const ['id']),
      number: _readInt(
        json,
        const ['number'],
        fallbackKeys: const ['orderNumber'],
      ),
      status: _readString(json, const ['status']).toUpperCase(),
      createdAt:
          _parseDateTime(_readValue(json, const ['createdAt'])) ?? DateTime.now(),
      assignedAt: _parseDateTime(_readValue(json, const ['assignedAt'])),
      pickedUpAt: _parseDateTime(_readValue(json, const ['pickedUpAt'])),
      deliveredAt: _parseDateTime(_readValue(json, const ['deliveredAt'])),
      promisedAt: _parseDateTime(_readValue(json, const ['promisedAt'])),
      restaurantName:
          _readNullableString(
            restaurant ?? json,
            const ['name'],
            fallbackKeys: const ['nameRu', 'titleRu', 'restaurantName'],
          ) ??
          _readNullableString(json, const ['restaurantName']),
      restaurantAddress:
          _readNullableString(
            restaurant ?? json,
            const ['address'],
            fallbackKeys: const ['restaurantAddress', 'pickupAddress'],
          ) ??
          _readNullableString(json, const ['restaurantAddress']),
      clientName: _buildClientName(user, json),
      clientPhone:
          _readNullableString(
            user ?? json,
            const ['phone'],
            fallbackKeys: const ['clientPhone', 'address.contactPhone'],
          ) ??
          _readNullableString(json, const ['clientPhone']) ??
          _readNullableString(address ?? json, const ['contactPhone']),
      clientAddress: _buildClientAddress(address, json),
      clientComment: _readNullableString(
        json,
        const ['comment'],
        fallbackKeys: const [
          'clientComment',
          'deliveryComment',
          'address.comment',
        ],
      ),
      leaveAtDoor:
          _readBool(
            json,
            const ['leaveAtDoor'],
            fallbackKeys: const ['address.leaveAtDoor'],
          ) ||
          _readBool(
            json,
            const ['contactless'],
            fallbackKeys: const ['noContact'],
          ),
      itemsCount: itemsCount,
      totalAmount: _readNullableInt(
        json,
        const ['total'],
        fallbackKeys: const ['amount', 'totalAmount'],
      ),
      courierFee: _readNullableInt(json, const ['courierFee']),
      courierFeeGross: _readNullableInt(json, const ['courierFeeGross']),
      courierCommissionAmount: _readNullableInt(
        json,
        const ['courierCommissionAmount'],
      ),
    );
  }

  static String? _buildClientName(
    Map<String, dynamic>? userMap,
    Map<String, dynamic> json,
  ) {
    if (userMap == null) {
      return _readNullableString(json, const ['clientName']);
    }

    final first = _readNullableString(
      userMap,
      const ['firstName'],
      fallbackKeys: const ['name'],
    );
    final last = _readNullableString(userMap, const ['lastName']);

    final joined = [
      (first ?? '').trim(),
      (last ?? '').trim(),
    ].where((e) => e.isNotEmpty).join(' ');

    if (joined.isNotEmpty) return joined;
    return _readNullableString(json, const ['clientName']);
  }

  static String? _buildClientAddress(
    Map<String, dynamic>? addressMap,
    Map<String, dynamic> json,
  ) {
    final direct = _readNullableString(
      json,
      const ['clientAddress'],
      fallbackKeys: const [
        'deliveryAddress',
        'deliveryAddressText',
        'address.address',
      ],
    );
    if ((direct ?? '').trim().isNotEmpty) return direct!.trim();

    if (addressMap == null) return null;

    final mainAddress =
        _readNullableString(addressMap, const ['address']) ??
        _readNullableString(addressMap, const ['title']);

    final entrance =
        _readNullableString(addressMap, const ['entrance']) ??
        _readNullableString(addressMap, const ['door']);

    final floor = _readNullableString(addressMap, const ['floor']);
    final intercom = _readNullableString(addressMap, const ['intercom']);

    final parts = <String>[
      if ((mainAddress ?? '').trim().isNotEmpty) mainAddress!.trim(),
      if ((entrance ?? '').trim().isNotEmpty) 'подъезд: ${entrance!.trim()}',
      if ((floor ?? '').trim().isNotEmpty) 'этаж: ${floor!.trim()}',
      if ((intercom ?? '').trim().isNotEmpty) 'домофон: ${intercom!.trim()}',
    ];

    final joined = parts.join(', ').trim();
    return joined.isEmpty ? null : joined;
  }

  static int _countItems(List<dynamic> items) {
    var total = 0;

    for (final item in items) {
      if (item is Map<String, dynamic>) {
        total += _readInt(item, const ['quantity']);
      } else if (item is Map) {
        total += _readInt(Map<String, dynamic>.from(item), const ['quantity']);
      }
    }

    return total;
  }

  static dynamic _readValue(
    Map<String, dynamic> json,
    List<String> path, {
    List<String> fallbackKeys = const [],
  }) {
    dynamic current = json;

    for (final part in path) {
      if (current is Map<String, dynamic> && current.containsKey(part)) {
        current = current[part];
      } else if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        current = null;
        break;
      }
    }

    if (current != null) return current;

    for (final key in fallbackKeys) {
      final value = _readByKeyPath(json, key);
      if (value != null) return value;
    }

    return null;
  }

  static dynamic _readByKeyPath(Map<String, dynamic> json, String keyPath) {
    dynamic current = json;

    for (final part in keyPath.split('.')) {
      if (current is Map<String, dynamic> && current.containsKey(part)) {
        current = current[part];
      } else if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }

    return current;
  }

  static String _readString(
    Map<String, dynamic> json,
    List<String> path, {
    List<String> fallbackKeys = const [],
  }) {
    final value = _readValue(json, path, fallbackKeys: fallbackKeys);
    return value?.toString() ?? '';
  }

  static String? _readNullableString(
    Map<String, dynamic> json,
    List<String> path, {
    List<String> fallbackKeys = const [],
  }) {
    final value = _readValue(json, path, fallbackKeys: fallbackKeys);
    final s = value?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static int _readInt(
    Map<String, dynamic> json,
    List<String> path, {
    List<String> fallbackKeys = const [],
  }) {
    final value = _readValue(json, path, fallbackKeys: fallbackKeys);
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _readNullableInt(
    Map<String, dynamic> json,
    List<String> path, {
    List<String> fallbackKeys = const [],
  }) {
    final value = _readValue(json, path, fallbackKeys: fallbackKeys);
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value.toString());
  }

  static bool _readBool(
    Map<String, dynamic> json,
    List<String> path, {
    List<String> fallbackKeys = const [],
  }) {
    final value = _readValue(json, path, fallbackKeys: fallbackKeys);
    if (value is bool) return value;
    if (value is String) {
      final v = value.trim().toLowerCase();
      return v == 'true' || v == '1';
    }
    if (value is num) return value != 0;
    return false;
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

  static List<dynamic>? _extractList(
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

    return current is List ? current : null;
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}
