import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/features/finance/presentation/finance_page.dart';
import 'package:jetkiz_courier_app/features/home/home_page.dart';
import 'package:jetkiz_courier_app/features/navigation/navigation_presentation/widgets/courier_bottom_bar.dart';
import 'package:jetkiz_courier_app/features/orders/data/courier_order_details_api.dart';
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
  late final CourierOrdersApi _api;
  late final CourierOrderDetailsApi _detailsApi;

  Timer? _pollTimer;

  bool _isForeground = true;
  bool _isLoading = true;
  bool _isPolling = false;
  bool _hasLoadedOnce = false;

  String _error = '';
  OrdersDateRange _range = OrdersDateRange.today();
  List<CourierOrderItem> _orders = const [];
  final Set<String> _actionLoadingIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = CourierOrdersApi(ApiClient());
    _detailsApi = CourierOrderDetailsApi(ApiClient());
    _loadInitial();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _isForeground;
    _isForeground = state == AppLifecycleState.resumed;

    if (!wasForeground && _isForeground) {
      _silentRefresh(force: true);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _silentRefresh(),
    );
  }

  DateTime _onlyDate(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  DateTime _resolveFilterDate(CourierOrderItem order) {
    return _onlyDate(order.relevantDate);
  }

  bool _matchesRange(CourierOrderItem order, OrdersDateRange range) {
    final orderDate = _resolveFilterDate(order);

    final from = range.from == null ? null : _onlyDate(range.from!);
    final to = range.to == null ? null : _onlyDate(range.to!);

    if (from != null && orderDate.isBefore(from)) return false;
    if (to != null && orderDate.isAfter(to)) return false;

    return true;
  }

  bool _isActiveOrder(CourierOrderItem order) {
    return !order.isDelivered && !order.isCanceled;
  }

  int _sortWeight(CourierOrderItem order) {
    final status = order.status.toUpperCase();

    if (status == 'ON_THE_WAY') return 0;
    if (status == 'READY') return 1;
    if (status == 'COOKING') return 2;
    if (status == 'ACCEPTED') return 3;
    if (status == 'DELIVERED') return 4;
    if (status == 'CANCELED' || status == 'CANCELLED') return 5;
    return 6;
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      await _loadOrders();
      _hasLoadedOnce = true;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить заказы';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _silentRefresh({bool force = false}) async {
    if (!_isForeground && !force) return;
    if (_isLoading || _isPolling) return;

    _isPolling = true;

    try {
      await _loadOrders();
      _hasLoadedOnce = true;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось обновить заказы';
      });
    } finally {
      _isPolling = false;
    }
  }

  Future<void> _loadOrders() async {
    final result = await _api.getCourierOrders(
      page: 1,
      limit: 200,
    );

    final filtered = result.where((e) {
      if (_isActiveOrder(e)) return true;
      return _matchesRange(e, _range);
    }).toList()
      ..sort((a, b) {
        final cmp = _sortWeight(a).compareTo(_sortWeight(b));
        if (cmp != 0) return cmp;
        return b.relevantDate.compareTo(a.relevantDate);
      });

    if (!mounted) return;

    setState(() {
      _orders = filtered;
      _error = '';
    });
  }

  Future<void> _handlePrimaryAction(CourierOrderItem order) async {
    if (_actionLoadingIds.contains(order.id)) return;

    final status = order.status.toUpperCase();

    setState(() {
      _actionLoadingIds.add(order.id);
    });

    try {
      if (status == 'READY') {
        await _detailsApi.markPickedUp(order.id);
      } else if (status == 'ON_THE_WAY') {
        await _detailsApi.markDelivered(order.id);
      } else {
        return;
      }

      await _loadOrders();

      if (!mounted) return;

      final message = status == 'ON_THE_WAY'
          ? 'Заказ отмечен как доставленный'
          : 'Заказ отмечен как забранный';

      _showSnackBar(message);
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('Не удалось обновить статус заказа');
    } finally {
      if (!mounted) return;
      setState(() {
        _actionLoadingIds.remove(order.id);
      });
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initial = DateTimeRange(
      start: _range.from ?? now.subtract(const Duration(days: 6)),
      end: _range.to ?? now,
    );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initial,
      helpText: 'Выберите период',
      saveText: 'Готово',
      cancelText: 'Отмена',
      confirmText: 'Готово',
      locale: const Locale('ru'),
    );

    if (picked == null) return;

    setState(() {
      _range = OrdersDateRange.custom(
        from: picked.start,
        to: picked.end,
      );
    });

    await _loadInitial();
  }

  void _onBottomBarTap(int index) {
    if (index == 1) return;

    if (index == 0) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const HomePage(),
        ),
      );
      return;
    }

    if (index == 2) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const FinancePage(),
        ),
      );
      return;
    }

    if (index == 3) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const ProfilePage(),
        ),
      );
      return;
    }
  }

  Future<void> _openOrder(CourierOrderItem order) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDetailsPage(orderId: order.id),
      ),
    );

    await _silentRefresh(force: true);
  }

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
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
                color: bg,
                border: Border(
                  bottom: BorderSide(
                    color: Color(0xFFE4E8EF),
                    width: 1,
                  ),
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
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OrdersPeriodFilter(
                    value: _range,
                    onChanged: (value) async {
                      setState(() {
                        _range = value;
                      });
                      await _loadInitial();
                    },
                    onTapCustom: _pickCustomRange,
                  ),
                  const SizedBox(height: 10),
                  AnimatedOpacity(
                    opacity: _isPolling ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Обновляется...',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF667085),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && !_hasLoadedOnce) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
      children: [
        _orders.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 48, 20, 24),
                children: const [
                  _EmptyState(),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: _orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, index) {
                  final order = _orders[index];
                  return CourierOrderCompactCard(
                    order: order,
                    onTap: () => _openOrder(order),
                    onPrimaryAction: () => _handlePrimaryAction(order),
                    isPrimaryActionLoading: _actionLoadingIds.contains(order.id),
                  );
                },
              ),
        if (_error.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5F5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFF1C4C4),
                    width: 1.2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Text(
                  'Не удалось обновить заказы. Повторим автоматически.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 42,
            color: Color(0xFF98A2B3),
          ),
          SizedBox(height: 12),
          Text(
            'Заказов нет',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Здесь будут показаны активные, доставленные и отменённые заказы',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF667085),
            ),
          ),
        ],
      ),
    );
  }
}
