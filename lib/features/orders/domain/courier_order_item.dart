class CourierOrderItem {
  const CourierOrderItem({
    required this.id,
    required this.number,
    required this.status,
    required this.createdAt,
    this.fulfillmentType = 'DELIVERY',
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
  final String fulfillmentType;
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

  bool get isDelivery => fulfillmentType.toUpperCase() != 'PICKUP';
  bool get isDelivered => status.toUpperCase() == 'DELIVERED';
  bool get isCompleted => isDelivered;

  bool get isCanceled {
    final value = status.toUpperCase();
    return value == 'CANCELED' || value == 'CANCELLED';
  }

  bool get isOnTheWay => status.toUpperCase() == 'ON_THE_WAY';
  bool get needsPickup => status.toUpperCase() == 'READY';

  DateTime get relevantDate =>
      deliveredAt ?? pickedUpAt ?? assignedAt ?? promisedAt ?? createdAt;

  String? get routeAddress {
    final value = clientAddress?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  int? get courierNetAmount {
    if (courierFee != null) return courierFee;
    if (courierFeeGross != null && courierCommissionAmount != null) {
      return (courierFeeGross! - courierCommissionAmount!).clamp(0, 1 << 31).toInt();
    }
    return courierFeeGross;
  }

  factory CourierOrderItem.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    final number = _requiredInt(json, const ['number', 'orderNumber'], 'number');
    final status = _requiredString(json, 'status').toUpperCase();
    final createdAt = _requiredDate(json, 'createdAt');

    final restaurant = _map(json['restaurant']);
    final user = _map(json['user']);
    final address = _map(json['address']);
    final previewItems = _list(json['items']) ?? _list(json['orderItems']) ?? const [];

    return CourierOrderItem(
      id: id,
      number: number,
      status: status,
      fulfillmentType: _string(json['fulfillmentType']).isEmpty
          ? 'DELIVERY'
          : _string(json['fulfillmentType']).toUpperCase(),
      createdAt: createdAt,
      assignedAt: _date(json['assignedAt']),
      pickedUpAt: _date(json['pickedUpAt']),
      deliveredAt: _date(json['deliveredAt']),
      promisedAt: _date(json['promisedAt']),
      restaurantName: _firstNonEmpty([
        restaurant?['nameRu'],
        restaurant?['name'],
        json['restaurantName'],
      ]),
      restaurantAddress: _firstNonEmpty([
        restaurant?['address'],
        json['restaurantAddress'],
        json['pickupAddress'],
      ]),
      clientName: _clientName(user, json),
      clientPhone: _firstNonEmpty([
        user?['phone'],
        json['clientPhone'],
        address?['contactPhone'],
        json['phone'],
      ]),
      clientAddress: _clientAddress(address, json),
      clientComment: _firstNonEmpty([
        json['comment'],
        json['clientComment'],
        json['deliveryComment'],
        address?['comment'],
      ]),
      leaveAtDoor: _bool(json['leaveAtDoor']) || _bool(json['contactless']),
      itemsCount: _nullableInt(json['itemsCount']) ??
          _nullableInt(json['totalItems']) ??
          _countItems(previewItems),
      totalAmount: _nullableInt(json['total']) ??
          _nullableInt(json['amount']) ??
          _nullableInt(json['totalAmount']),
      courierFee: _nullableInt(json['courierFee']),
      courierFeeGross: _nullableInt(json['courierFeeGross']),
      courierCommissionAmount: _nullableInt(json['courierCommissionAmount']),
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = _string(json[key]);
    if (value.isEmpty) {
      throw FormatException('Courier order is missing required field: $key');
    }
    return value;
  }

  static int _requiredInt(
    Map<String, dynamic> json,
    List<String> keys,
    String field,
  ) {
    for (final key in keys) {
      final value = _nullableInt(json[key]);
      if (value != null && value > 0) return value;
    }
    throw FormatException('Courier order is missing required field: $field');
  }

  static DateTime _requiredDate(Map<String, dynamic> json, String key) {
    final value = _date(json[key]);
    if (value == null) {
      throw FormatException('Courier order has invalid required date: $key');
    }
    return value;
  }

  static String? _clientName(
    Map<String, dynamic>? user,
    Map<String, dynamic> json,
  ) {
    final first = _firstNonEmpty([user?['firstName'], user?['name']]);
    final last = _firstNonEmpty([user?['lastName']]);
    final joined = [first, last]
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .join(' ')
        .trim();
    return joined.isNotEmpty ? joined : _firstNonEmpty([json['clientName']]);
  }

  static String? _clientAddress(
    Map<String, dynamic>? address,
    Map<String, dynamic> json,
  ) {
    final direct = _firstNonEmpty([
      json['clientAddress'],
      json['deliveryAddress'],
      json['deliveryAddressText'],
    ]);
    if (direct != null) return direct;
    if (address == null) return null;

    final main = _firstNonEmpty([address['address'], address['title']]);
    final entrance = _string(address['entrance']);
    final floor = _string(address['floor']);
    final door = _string(address['door']);
    final intercom = _string(address['intercom']);

    final parts = <String>[
      if (main != null) main,
      if (entrance.isNotEmpty) 'подъезд: $entrance',
      if (floor.isNotEmpty) 'этаж: $floor',
      if (door.isNotEmpty) 'квартира/дверь: $door',
      if (intercom.isNotEmpty) 'домофон: $intercom',
    ];

    final result = parts.join(', ').trim();
    return result.isEmpty ? null : result;
  }

  static int _countItems(List<dynamic> items) {
    var total = 0;
    for (final raw in items.whereType<Map>()) {
      total += _nullableInt(raw['quantity']) ?? 0;
    }
    return total;
  }

  static Map<String, dynamic>? _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static List<dynamic>? _list(dynamic value) => value is List ? value : null;

  static String _string(dynamic value) => value?.toString().trim() ?? '';

  static String? _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = _string(value);
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static int? _nullableInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(_string(value));
  }

  static bool _bool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = _string(value).toLowerCase();
    return text == 'true' || text == '1';
  }

  static DateTime? _date(dynamic value) {
    if (value is DateTime) return value;
    final text = _string(value);
    return text.isEmpty ? null : DateTime.tryParse(text);
  }
}
