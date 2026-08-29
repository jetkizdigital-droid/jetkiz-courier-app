import 'dart:async';

class CourierOrderEvent {
  const CourierOrderEvent({
    required this.orderId,
    required this.type,
    this.status,
  });

  final String orderId;
  final String type;
  final String? status;
}

class CourierOrderEvents {
  CourierOrderEvents._();

  static final StreamController<CourierOrderEvent> _controller =
      StreamController<CourierOrderEvent>.broadcast();

  static Stream<CourierOrderEvent> get stream => _controller.stream;

  static void emit({
    required String orderId,
    required String type,
    String? status,
  }) {
    final normalizedId = orderId.trim();
    if (normalizedId.isEmpty) return;
    _controller.add(
      CourierOrderEvent(
        orderId: normalizedId,
        type: type.trim().isEmpty ? 'courier_order' : type.trim(),
        status: status?.trim().isEmpty == true
            ? null
            : status?.trim().toUpperCase(),
      ),
    );
  }

  static void emitFromPush(Map<String, String> data) {
    final orderId = (data['orderId'] ?? data['order_id'] ?? '').trim();
    if (orderId.isEmpty) return;

    final type = (data['type'] ?? '').trim().toLowerCase();
    final screen = (data['screen'] ?? '').trim().toLowerCase();

    if (type != 'courier_order' &&
        type != 'order_status' &&
        screen != 'order_details') {
      return;
    }

    emit(
      orderId: orderId,
      type: type.isEmpty ? 'courier_order' : type,
      status: data['status'],
    );
  }
}
