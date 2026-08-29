import 'package:flutter/material.dart';

enum OrdersPeriodType { today, week, month, custom }

class OrdersDateRange {
  const OrdersDateRange({required this.type, this.from, this.to});

  final OrdersPeriodType type;
  final DateTime? from;
  final DateTime? to;

  String get apiFrom => from == null ? '' : _formatDate(from!);
  String get apiTo => to == null ? '' : _formatDate(to!);

  String get title {
    switch (type) {
      case OrdersPeriodType.today:
        return 'Сегодня';
      case OrdersPeriodType.week:
        return '7 дней';
      case OrdersPeriodType.month:
        return '30 дней';
      case OrdersPeriodType.custom:
        return from != null && to != null
            ? '${_formatViewDate(from!)} — ${_formatViewDate(to!)}'
            : 'Период';
    }
  }

  static OrdersDateRange today() {
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, now.day);
    return OrdersDateRange(type: OrdersPeriodType.today, from: date, to: date);
  }

  static OrdersDateRange week() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final start = end.subtract(const Duration(days: 6));
    return OrdersDateRange(type: OrdersPeriodType.week, from: start, to: end);
  }

  static OrdersDateRange month() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final start = end.subtract(const Duration(days: 29));
    return OrdersDateRange(type: OrdersPeriodType.month, from: start, to: end);
  }

  static OrdersDateRange custom({
    required DateTime from,
    required DateTime to,
  }) {
    return OrdersDateRange(
      type: OrdersPeriodType.custom,
      from: DateTime(from.year, from.month, from.day),
      to: DateTime(to.year, to.month, to.day),
    );
  }

  static String _formatDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _formatViewDate(DateTime value) {
    final d = value.day.toString().padLeft(2, '0');
    final m = value.month.toString().padLeft(2, '0');
    return '$d.$m.${value.year}';
  }
}

class OrdersPeriodFilter extends StatelessWidget {
  const OrdersPeriodFilter({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onTapCustom,
  });

  final OrdersDateRange value;
  final ValueChanged<OrdersDateRange> onChanged;
  final VoidCallback onTapCustom;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF3FAE2A);
    const chipBg = Color(0xFFF2F4F7);

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _PeriodChip(
            label: 'Сегодня',
            selected: value.type == OrdersPeriodType.today,
            onTap: () => onChanged(OrdersDateRange.today()),
            selectedColor: green,
            backgroundColor: chipBg,
          ),
          const SizedBox(width: 8),
          _PeriodChip(
            label: '7 дней',
            selected: value.type == OrdersPeriodType.week,
            onTap: () => onChanged(OrdersDateRange.week()),
            selectedColor: green,
            backgroundColor: chipBg,
          ),
          const SizedBox(width: 8),
          _PeriodChip(
            label: '30 дней',
            selected: value.type == OrdersPeriodType.month,
            onTap: () => onChanged(OrdersDateRange.month()),
            selectedColor: green,
            backgroundColor: chipBg,
          ),
          const SizedBox(width: 8),
          _PeriodChip(
            label: value.type == OrdersPeriodType.custom
                ? value.title
                : 'Период',
            selected: value.type == OrdersPeriodType.custom,
            onTap: onTapCustom,
            selectedColor: green,
            backgroundColor: chipBg,
          ),
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.selectedColor,
    required this.backgroundColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color selectedColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? selectedColor : backgroundColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
