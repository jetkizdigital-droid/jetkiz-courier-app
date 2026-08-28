import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/features/orders/domain/courier_order_item.dart';

class CourierOrderCompactCard extends StatelessWidget {
  const CourierOrderCompactCard({
    super.key,
    required this.order,
    this.onTap,
    this.onPrimaryAction,
    this.isPrimaryActionLoading = false,
  });

  final CourierOrderItem order;
  final VoidCallback? onTap;

  // Kept temporarily for source compatibility with OrdersPage. Status changes
  // are intentionally not exposed from this compact card: courier must open
  // order details and confirm pickup/delivery there.
  final Future<void> Function()? onPrimaryAction;
  final bool isPrimaryActionLoading;

  @override
  Widget build(BuildContext context) {
    final statusStyle = _statusStyle(order.status);
    final dateText = _formatDateTime(order.relevantDate);
    final payout = _formatMoney(order.courierNetAmount ?? 0);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Заказ №${order.number}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusStyle.background,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusStyle.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusStyle.foreground,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _InfoRow(
                icon: Icons.storefront_outlined,
                title: order.restaurantName ?? 'Ресторан',
                subtitle: order.restaurantAddress ?? 'Адрес ресторана не указан',
              ),
              const SizedBox(height: 10),
              _InfoRow(
                icon: Icons.location_on_outlined,
                title: order.clientAddress ?? 'Адрес доставки не указан',
                subtitle: order.clientName ?? order.clientPhone ?? 'Клиент',
              ),
              if ((order.clientComment ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                _InfoRow(
                  icon: Icons.comment_outlined,
                  title: 'Комментарий клиента',
                  subtitle: order.clientComment!.trim(),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _BottomMetric(
                      label: 'Выплата',
                      value: '$payout ₸',
                      valueColor: const Color(0xFF2F8731),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BottomMetric(
                      label: _dateMetricLabel(order),
                      value: dateText,
                    ),
                  ),
                ],
              ),
              if (order.needsPickup || order.isOnTheWay) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Откройте заказ, чтобы изменить статус',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475467),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _dateMetricLabel(CourierOrderItem order) {
    if (order.isDelivered) return 'Доставлен';
    if (order.isCanceled) return 'Отменён';
    if (order.isOnTheWay) return 'В пути';
    if (order.needsPickup) return 'Назначен';
    return 'Дата';
  }

  static String _formatMoney(int value) {
    final s = value.toString();
    final buffer = StringBuffer();
    var count = 0;

    for (var i = s.length - 1; i >= 0; i--) {
      buffer.write(s[i]);
      count++;
      if (count % 3 == 0 && i != 0) buffer.write(' ');
    }

    return buffer.toString().split('').reversed.join();
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d.$m.$y  $h:$min';
  }

  static _StatusStyle _statusStyle(String raw) {
    switch (raw.toUpperCase()) {
      case 'DELIVERED':
        return const _StatusStyle('Доставлен', Color(0xFFEAF7EA), Color(0xFF2F8731));
      case 'ON_THE_WAY':
        return const _StatusStyle('В пути', Color(0xFFEEF4FF), Color(0xFF175CD3));
      case 'READY':
        return const _StatusStyle('Готов', Color(0xFFFFF4E5), Color(0xFFB54708));
      case 'COOKING':
        return const _StatusStyle('Готовится', Color(0xFFF2F4F7), Color(0xFF344054));
      case 'ACCEPTED':
        return const _StatusStyle('Принят', Color(0xFFF2F4F7), Color(0xFF344054));
      case 'CANCELED':
      case 'CANCELLED':
        return const _StatusStyle('Отменён', Color(0xFFFDECEC), Color(0xFFDC2626));
      default:
        return const _StatusStyle('Статус', Color(0xFFF2F4F7), Color(0xFF667085));
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF667085)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF667085),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BottomMetric extends StatelessWidget {
  const _BottomMetric({
    required this.label,
    required this.value,
    this.valueColor = Colors.black,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusStyle {
  const _StatusStyle(this.label, this.background, this.foreground);

  final String label;
  final Color background;
  final Color foreground;
}
