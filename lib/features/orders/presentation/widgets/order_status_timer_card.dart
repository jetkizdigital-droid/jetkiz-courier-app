import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/features/orders/domain/courier_order_details.dart';

class OrderStatusTimerCard extends StatelessWidget {
  const OrderStatusTimerCard({
    super.key,
    required this.order,
    required this.now,
  });

  final CourierOrderDetails order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFF59E0B);
    const green = Color(0xFF2F8731);

    final phase = _resolvePhase(order);
    final deadline = _resolveDeadline(order);
    final remaining = deadline?.difference(now);
    final isOverdue = remaining != null && remaining.inSeconds <= 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isOverdue ? const Color(0xFFFFF7ED) : const Color(0xFFF4FBF1),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isOverdue ? orange : green, width: 1.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            phase.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            phase.subtitle,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF667085),
            ),
          ),
          if (deadline != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _MetricBox(
                    label: 'До',
                    value: _formatClock(deadline),
                    valueColor: isOverdue ? orange : Colors.black,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricBox(
                    label: 'Осталось',
                    value: _formatRemaining(remaining!),
                    valueColor: isOverdue ? const Color(0xFFDC2626) : green,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  _OrderPhase _resolvePhase(CourierOrderDetails order) {
    if (order.isDelivered) {
      return const _OrderPhase(
        title: 'Заказ доставлен',
        subtitle: 'Работа по заказу завершена',
      );
    }

    if (order.isCanceled) {
      return const _OrderPhase(
        title: 'Заказ отменён',
        subtitle: 'Дальнейшие действия не требуются',
      );
    }

    if (order.needsPickup) {
      return const _OrderPhase(
        title: 'Нужно забрать заказ',
        subtitle: 'У вас 15 минут с момента назначения заказа',
      );
    }

    return const _OrderPhase(
      title: 'Нужно доставить заказ',
      subtitle: 'У вас 15 минут с момента, когда вы забрали заказ',
    );
  }

  DateTime? _resolveDeadline(CourierOrderDetails order) {
    if (order.isDelivered || order.isCanceled) return null;

    if (order.needsPickup && order.assignedAt != null) {
      return order.assignedAt!.toLocal().add(const Duration(minutes: 15));
    }

    if (order.isOnTheWay && order.pickedUpAt != null) {
      return order.pickedUpAt!.toLocal().add(const Duration(minutes: 15));
    }

    return order.promisedAt?.toLocal();
  }

  static String _formatClock(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _formatRemaining(Duration value) {
    final seconds = value.inSeconds;

    if (seconds <= 0) {
      final overdue = Duration(seconds: seconds.abs());
      final mm = overdue.inMinutes.toString().padLeft(2, '0');
      final ss = (overdue.inSeconds % 60).toString().padLeft(2, '0');
      return '-$mm:$ss';
    }

    final mm = value.inMinutes.toString().padLeft(2, '0');
    final ss = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

class _MetricBox extends StatelessWidget {
  const _MetricBox({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF667085),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderPhase {
  const _OrderPhase({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}
