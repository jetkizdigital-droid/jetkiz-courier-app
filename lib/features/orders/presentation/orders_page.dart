import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/features/finance/presentation/finance_page.dart';
import 'package:jetkiz_courier_app/features/home/home_page.dart';
import 'package:jetkiz_courier_app/features/navigation/navigation_presentation/widgets/courier_bottom_bar.dart';
import 'package:jetkiz_courier_app/features/orders/data/courier_orders_api.dart';
import 'package:jetkiz_courier_app/features/orders/domain/courier_order_item.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/order_details_page.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/widgets/courier_order_compact_card.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/widgets/orders_period_filter.dart';
import 'package:jetkiz_courier_app/features/profile/presentation/profile_page.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> with WidgetsBindingObserver {
  late final ApiClient _client;
  late final CourierOrdersApi _api;

  Timer? _pollTimer;
  bool _foreground = true;
  bool _loading = true;
  bool _refreshing = false;
  bool _polling = false;
  String _error = '';
  OrdersDateRange _range = OrdersDateRange.today();
  List<CourierOrderItem> _orders = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _client = ApiClient();
    _api = CourierOrdersApi(_client);
    unawaited(_load());
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _client.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _foreground;
    _foreground = state == AppLifecycleState.resumed;

    if (!wasForeground && _foreground) {
      unawaited(_load(silent: true));
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_foreground) unawaited(_load(silent: true, polling: true));
    });
  }

  Future<void> _load({bool silent = false, bool polling = false}) async {
    if (_loading && silent) return;
    if (_refreshing || _polling) return;

    if (polling) {
      _polling = true;
    } else if (silent) {
      if (mounted) setState(() => _refreshing = true);
    } else {
      if (mounted) {
        setState(() {
          _loading = true;
          _error = '';
        });
      }
    }

    try {
      // Active orders must always remain visible, while recent completed rows
      // are filtered locally by the selected date range. Paging in the API
      // prevents the old backend 100-row cap from silently truncating history.
      final rows = await _api.getCourierOrders(page: 1, limit: 500);
      final filtered = rows.where((order) {
        if (!_isTerminal(order)) return true;
        return _matchesRange(order, _range);
      }).toList()
        ..sort(_compareOrders);

      if (!mounted) return;
      setState(() {
        _orders = filtered;
        _error = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _humanizeError(e));
    } finally {
      _polling = false;
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  bool _isTerminal(CourierOrderItem order) => order.isDelivered || order.isCanceled;

  bool _matchesRange(CourierOrderItem order, OrdersDateRange range) {
    final date = _dateOnly(order.relevantDate.toLocal());
    final from = range.from == null ? null : _dateOnly(range.from!);
    final to = range.to == null ? null : _dateOnly(range.to!);

    if (from != null && date.isBefore(from)) return false;
    if (to != null && date.isAfter(to)) return false;
    return true;
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  int _compareOrders(CourierOrderItem a, CourierOrderItem b) {
    final byWeight = _statusWeight(a.status).compareTo(_statusWeight(b.status));
    if (byWeight != 0) return byWeight;
    return b.relevantDate.compareTo(a.relevantDate);
  }

  int _statusWeight(String raw) {
    switch (raw.toUpperCase()) {
      case 'ON_THE_WAY':
        return 0;
      case 'READY':
        return 1;
      case 'COOKING':
        return 2;
      case 'ACCEPTED':
        return 3;
      case 'DELIVERED':
        return 4;
      case 'CANCELED':
      case 'CANCELLED':
        return 5;
      default:
        return 6;
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: _range.from ?? now.subtract(const Duration(days: 6)),
        end: _range.to ?? now,
      ),
      helpText: 'Выберите период',
      saveText: 'Готово',
      cancelText: 'Отмена',
      confirmText: 'Готово',
      locale: const Locale('ru'),
    );

    if (picked == null) return;

    setState(() {
      _range = OrdersDateRange.custom(from: picked.start, to: picked.end);
    });
    await _load();
  }

  Future<void> _openOrder(CourierOrderItem order) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OrderDetailsPage(orderId: order.id)),
    );
    if (mounted) await _load(silent: true);
  }

  void _onBottomBarTap(int index) {
    if (index == 1) return;

    final Widget page = switch (index) {
      0 => const HomePage(),
      2 => const FinancePage(),
      3 => const ProfilePage(),
      _ => const OrdersPage(),
    };

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  String _humanizeError(Object error) {
    if (error is FormatException) {
      return 'Сервер вернул некорректные данные заказа. Обновите экран позже.';
    }

    if (error is ApiException) {
      switch (error.kind) {
        case ApiErrorKind.network:
          return 'Нет соединения с сервером.';
        case ApiErrorKind.timeout:
          return 'Сервер не ответил вовремя.';
        case ApiErrorKind.sessionExpired:
        case ApiErrorKind.unauthorized:
          return 'Сессия истекла. Войдите заново.';
        default:
          return 'Не удалось загрузить заказы.';
      }
    }

    return 'Не удалось загрузить заказы.';
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF8F8FA);

    return Scaffold(
      backgroundColor: bg,
      bottomNavigationBar: CourierBottomBar(
        currentIndex: 1,
        onTap: _onBottomBarTap,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE4E8EF)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Заказы',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OrdersPeriodFilter(
                    value: _range,
                    onChanged: (value) {
                      setState(() => _range = value);
                      unawaited(_load());
                    },
                    onTapCustom: _pickCustomRange,
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: (_refreshing || _polling)
                        ? const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Обновляем заказы…',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF667085),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox(height: 0),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_orders.isEmpty && _error.isNotEmpty) {
      return _CenteredState(
        icon: Icons.cloud_off_rounded,
        title: 'Не удалось загрузить заказы',
        subtitle: _error,
        action: 'Повторить',
        onAction: () => unawaited(_load()),
      );
    }

    if (_orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            _CenteredState(
              icon: Icons.inventory_2_outlined,
              title: 'Заказов нет',
              subtitle: 'Активные и завершённые доставки появятся здесь.',
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => _load(silent: true),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            itemCount: _orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, index) {
              final order = _orders[index];
              return CourierOrderCompactCard(
                order: order,
                onTap: () => _openOrder(order),
              );
            },
          ),
        ),
        if (_error.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5F5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF1C4C4)),
              ),
              child: Text(
                _error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFB42318),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: const Color(0xFF98A2B3)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.35,
                color: Color(0xFF667085),
              ),
            ),
            if (action != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      ),
    );
  }
}
