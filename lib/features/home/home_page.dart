import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/location/courier_location_service.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/features/finance/presentation/finance_page.dart';
import 'package:jetkiz_courier_app/features/navigation/navigation_presentation/widgets/courier_bottom_bar.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/order_details_page.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/orders_page.dart';
import 'package:jetkiz_courier_app/features/profile/presentation/profile_page.dart';
import 'package:jetkiz_courier_app/features/notifications/presentation/notifications_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final _CourierHomeApi _api;
  late final CourierLocationService _locationService;

  Timer? _activeOrderTimer;
  bool _isPollingActiveOrder = false;
  bool _isActiveOrderActionLoading = false;
  bool _isChangingOnline = false;

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool isOnline = false;

  String courierName = 'Курьер';
  int todayOrders = 0;
  int todayEarnings = 0;
  int todayCompleted = 0;
  int unreadCount = 0;

  Map<String, dynamic>? activeOrder;
  String error = '';

  String get todayText {
    final now = DateTime.now();
    const months = [
      '',
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    return '${now.day} ${months[now.month]}';
  }

  @override
  void initState() {
    super.initState();
    _api = _CourierHomeApi(ApiClient());
    _locationService = CourierLocationService();
    _loadInitial();
    _startActiveOrderPolling();
  }

  @override
  void dispose() {
    _activeOrderTimer?.cancel();
    unawaited(_locationService.dispose());
    super.dispose();
  }

  void _startActiveOrderPolling() {
    _activeOrderTimer?.cancel();

    _activeOrderTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _silentRefreshActiveOrder(),
    );
  }

  Future<void> _silentRefreshActiveOrder() async {
    if (!mounted ||
        _isLoading ||
        _isRefreshing ||
        _isPollingActiveOrder ||
        _isActiveOrderActionLoading) {
      return;
    }

    _isPollingActiveOrder = true;

    try {
      final active = await _api.getActiveOrder();
      final unread = await _api.getUnreadCount();
      final resolvedActiveOrder = _normalizeActiveOrder(active);

      if (!mounted) return;

      final previousId = activeOrder?['id']?.toString() ?? '';
      final nextId = resolvedActiveOrder?['id']?.toString() ?? '';

      final hadNoOrderBefore = activeOrder == null;
      final hasNewOrderNow = resolvedActiveOrder != null;
      final isNewOrderAppeared =
          hadNoOrderBefore && hasNewOrderNow && nextId.isNotEmpty;

      setState(() {
        activeOrder = resolvedActiveOrder;
        unreadCount = unread;
      });

      if (isNewOrderAppeared) {
        _showSnackBar('Поступил новый заказ');
      } else if (previousId.isNotEmpty &&
          nextId.isNotEmpty &&
          previousId != nextId) {
        _showSnackBar('Активный заказ обновился');
      }
    } catch (_) {
      // silent polling
    } finally {
      _isPollingActiveOrder = false;
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      error = '';
    });

    try {
      await _loadData();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'Не удалось загрузить данные';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _isRefreshing = true;
      error = '';
    });

    try {
      await _loadData();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'Не удалось обновить данные';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _loadData() async {
    final meFuture = _api.getMe();
    final todayStatsFuture = _api.getTodayStats();
    final activeOrderFuture = _api.getActiveOrder();
    final unreadFuture = _api.getUnreadCount();

    final results = await Future.wait<dynamic>([
      meFuture,
      todayStatsFuture,
      activeOrderFuture,
      unreadFuture,
    ]);

    final me = results[0] as Map<String, dynamic>;
    final todayStats = results[1] as _HomeTodayStats;
    final active = results[2] as Map<String, dynamic>?;
    final unread = results[3] as int;

    final firstName = _readString(
      me,
      const ['firstName'],
      fallbackKeys: const ['name', 'user.firstName', 'profile.firstName'],
    );
    final lastName = _readNullableString(
      me,
      const ['lastName'],
      fallbackKeys: const ['user.lastName', 'profile.lastName'],
    );

    final resolvedName = [
      firstName.trim(),
      (lastName ?? '').trim(),
    ].where((e) => e.isNotEmpty).join(' ');

    final activeFromMe =
        _readMap(me, const ['activeOrder']) ??
        _readMap(me, const ['order']) ??
        _readMap(me, const ['currentOrder']);

    final resolvedActiveOrder = _normalizeActiveOrder(active ?? activeFromMe);

    final resolvedOnline = _readBool(
      me,
      const ['isOnline'],
      fallbackKeys: const ['profile.isOnline', 'courierProfile.isOnline'],
    );

    if (!mounted) return;

    setState(() {
      courierName = resolvedName.isEmpty ? 'Курьер' : resolvedName;
      isOnline = resolvedOnline;
      todayOrders = todayStats.orders;
      todayEarnings = todayStats.earnings;
      todayCompleted = todayStats.completed;
      unreadCount = unread;
      activeOrder = resolvedActiveOrder;
      error = '';
    });

    if (resolvedOnline && !_locationService.isTracking) {
      unawaited(_startLocationTrackingSilently());
    }

    if (!resolvedOnline && _locationService.isTracking) {
      unawaited(_locationService.stopTracking());
    }
  }

  Future<void> _startLocationTrackingSilently() async {
    try {
      final result = await _locationService.startTracking();

      if (!mounted) return;

      if (!result.started) {
        _showSnackBar(result.message);
      }
    } catch (_) {
      // Геолокация не должна ломать загрузку главного экрана.
    }
  }

  Future<void> _toggleOnline() async {
  if (_isChangingOnline) return;

  final nextValue = !isOnline;
  final previousValue = isOnline;

  setState(() {
    _isChangingOnline = true;
  });

  if (nextValue) {
    try {
      final permission = await _locationService.ensurePermission();

      if (!permission.allowed) {
        if (!mounted) return;

        setState(() {
          isOnline = previousValue;
          _isChangingOnline = false;
        });

        _showSnackBar(permission.message);
        return;
      }

      await _api.setOnline(true);

      if (!mounted) return;

      setState(() {
        isOnline = true;
        _isChangingOnline = false;
      });

      _showSnackBar('Вы онлайн. Запускаем геолокацию.');

      unawaited(_locationService.startTracking());
    } catch (_) {
      await _locationService.stopTracking();

      if (!mounted) return;

      setState(() {
        isOnline = previousValue;
        _isChangingOnline = false;
      });

      _showSnackBar('Не удалось выйти на линию');
    }

    return;
  }

  try {
    await _api.setOnline(false);
    await _locationService.stopTracking();

    if (!mounted) return;

    setState(() {
      isOnline = false;
      _isChangingOnline = false;
    });

    _showSnackBar('Вы оффлайн. Геолокация остановлена.');
  } catch (_) {
    if (!mounted) return;

    setState(() {
      isOnline = previousValue;
      _isChangingOnline = false;
    });

    _showSnackBar('Не удалось изменить статус');
  }
}

  void _onBottomBarTap(int index) {
    if (index == 0) return;

    if (index == 1) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const OrdersPage(),
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

  void _openNotifications() {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const NotificationsPage(),
    ),
  );
}

  Future<void> _openActiveOrder() async {
    final id = activeOrder?['id']?.toString() ?? '';
    if (id.isEmpty) {
      _showSnackBar('Активного заказа нет');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDetailsPage(orderId: id),
      ),
    );

    await _loadInitial();
  }

  String _activeOrderActionLabel() {
    final status = (activeOrder?['status'] ?? '').toString().toUpperCase();

    if (status == 'READY') {
      return 'Забрал заказ';
    }

    if (status == 'ON_THE_WAY') {
      return 'Доставил';
    }

    return 'Открыть заказ';
  }

  Future<void> _handleActiveOrderAction() async {
    final current = activeOrder;
    if (current == null || _isActiveOrderActionLoading) return;

    final id = current['id']?.toString() ?? '';
    final status = (current['status'] ?? '').toString().toUpperCase();

    if (id.isEmpty) {
      _showSnackBar('Активный заказ не найден');
      return;
    }

    if (!(status == 'READY' || status == 'ON_THE_WAY')) {
      await _openActiveOrder();
      return;
    }

    setState(() {
      _isActiveOrderActionLoading = true;
    });

    try {
      if (status == 'READY') {
        await _api.updateCourierOrderStatus(
          orderId: id,
          status: 'ON_THE_WAY',
        );
        _showSnackBar('Заказ забран');
      } else if (status == 'ON_THE_WAY') {
        await _api.updateCourierOrderStatus(
          orderId: id,
          status: 'DELIVERED',
        );
        _showSnackBar('Заказ доставлен');
      }

      await _loadInitial();
    } catch (_) {
      _showSnackBar('Ошибка обновления статуса');
    } finally {
      if (!mounted) return;
      setState(() {
        _isActiveOrderActionLoading = false;
      });
    }
  }

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF3FAE2A);
    const darkGreen = Color(0xFF2F8731);
    const red = Color(0xFFDC2626);
    const orange = Color(0xFFF59E0B);
    const textMuted = Color(0xFF8E8E93);
    const borderColor = Color(0xFFD8DDE6);
    const bg = Color(0xFFF8F8FA);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: bg,
        bottomNavigationBar: CourierBottomBar(
          currentIndex: 0,
          onTap: _onBottomBarTap,
        ),
        body: const SafeArea(
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      bottomNavigationBar: CourierBottomBar(
        currentIndex: 0,
        onTap: _onBottomBarTap,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              decoration: const BoxDecoration(
                color: bg,
                border: Border(
                  bottom: BorderSide(
                    color: Color(0xFFE4E8EF),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Привет, $courierName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Сегодня: $todayText',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: borderColor,
                            width: 1.3,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x0D000000),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: IconButton(
                          onPressed: _openNotifications,
                          icon: const Icon(
                            Icons.notifications_none_rounded,
                            size: 24,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            decoration: BoxDecoration(
                              color: red,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  children: [
                    if (error.isNotEmpty) ...[
                      Container(
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
                        ),
                        child: Text(
                          error,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: red,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (activeOrder != null) ...[
                      GestureDetector(
                        onTap: _openActiveOrder,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4FBF1),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: green, width: 1.8),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0A000000),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: orange,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'Активный заказ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Заказ №${activeOrder!['orderNumber']}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(
                                      Icons.location_on_outlined,
                                      size: 20,
                                      color: textMuted,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (activeOrder!['restaurantName'] ?? '')
                                              .toString(),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          (activeOrder!['restaurantAddress'] ??
                                                  '')
                                              .toString(),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(
                                      Icons.location_on_outlined,
                                      size: 20,
                                      color: green,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      (activeOrder!['clientAddress'] ?? '')
                                          .toString(),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Ваш доход',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: textMuted,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${activeOrder!['courierPayout']} ₸',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                            color: darkGreen,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text(
                                        'Забрать до',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: textMuted,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        (activeOrder!['deadlineText'] ?? '—')
                                            .toString(),
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          color: orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: ElevatedButton(
                                  onPressed: _isActiveOrderActionLoading
                                      ? null
                                      : _handleActiveOrderAction,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: darkGreen,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: _isActiveOrderActionLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              _activeOrderActionLabel(),
                                              style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Icon(
                                              Icons.arrow_forward_rounded,
                                              size: 20,
                                              color: Colors.white,
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    const Text(
                      'Статистика за сегодня',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _CompactStatCard(
                            icon: Icons.trending_up_rounded,
                            iconBg: const Color(0x143FAE2A),
                            iconColor: green,
                            value: '$todayOrders',
                            label: 'Заказов',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CompactStatCard(
                            icon: Icons.payments_outlined,
                            iconBg: const Color(0x142E7D32),
                            iconColor: darkGreen,
                            value: '$todayEarnings',
                            label: 'Заработано',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CompactStatCard(
                            icon: Icons.check_circle_outline_rounded,
                            iconBg: const Color(0x143FAE2A),
                            iconColor: green,
                            value: '$todayCompleted',
                            label: 'Завершено',
                          ),
                        ),
                      ],
                    ),
                    if (_isRefreshing) ...[
                      const SizedBox(height: 18),
                      const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              decoration: const BoxDecoration(
                color: bg,
                border: Border(
                  top: BorderSide(
                    color: Color(0xFFE4E8EF),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Center(
                    child: Text(
                      _isChangingOnline
                          ? 'Обновляем статус и геолокацию...'
                          : isOnline
                              ? 'Вы можете принимать заказы'
                              : 'Включите статус, чтобы получать заказы',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _isChangingOnline ? null : _toggleOnline,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: double.infinity,
                      height: 76,
                      decoration: BoxDecoration(
                        color: isOnline ? darkGreen : const Color(0xFFEDEDF1),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isOnline
                              ? const Color(0xFF256B28)
                              : borderColor,
                          width: 1.4,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 14,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isChangingOnline)
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: isOnline
                                    ? Colors.white
                                    : const Color(0xFF676B73),
                              ),
                            )
                          else
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: isOnline
                                    ? Colors.white
                                    : const Color(0xFF7E7E86),
                                shape: BoxShape.circle,
                              ),
                            ),
                          const SizedBox(width: 14),
                          Text(
                            isOnline ? 'Онлайн' : 'Оффлайн',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: isOnline
                                  ? Colors.white
                                  : const Color(0xFF676B73),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourierHomeApi {
  const _CourierHomeApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> getMe() async {
    final data = await _client.get('/couriers/me');
    return _asMap(data);
  }

  Future<Map<String, dynamic>?> getActiveOrder() async {
    try {
      final data = await _client.get('/orders/courier/active');
      if (data == null) return null;
      return _asMap(data);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getFinanceSummary() async {
    try {
      final data = await _client.get('/couriers/me/finance/summary');
      return _asMap(data);
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  Future<_HomeTodayStats> getTodayStats() async {
    final now = DateTime.now();
    final from = _formatDate(now);
    final to = _formatDate(now);

    try {
      final data = await _client.get(
        '/orders/courier/my?page=1&limit=200&from=$from&to=$to',
      );

      final map = _asMap(data);
      final items =
          _extractList(map, const ['items']) ??
          _extractList(map, const ['data', 'items']) ??
          _extractList(map, const ['orders']) ??
          _extractList(map, const ['data', 'orders']) ??
          (data is List ? data : const []);

      final todayOrdersRaw = items
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      int orders = 0;
      int completed = 0;
      int earnings = 0;

      for (final order in todayOrdersRaw) {
        final assignedAt = _parseDateTime(
          _readValue(order, const ['assignedAt']),
        );
        final createdAt = _parseDateTime(
          _readValue(order, const ['createdAt']),
        );
        final deliveredAt = _parseDateTime(
          _readValue(order, const ['deliveredAt']),
        );

        final status = (_readValue(order, const ['status']) ?? '')
            .toString()
            .trim()
            .toUpperCase();

        final courierFeeNet =
            _tryInt(_readValue(order, const ['courierFee'])) ??
                _resolveNetCourierPayout(order);

        final orderDayBase = assignedAt ?? createdAt;
        final isTodayOrder =
            orderDayBase != null && _isSameDay(orderDayBase.toLocal(), now);

        final isDeliveredToday =
            deliveredAt != null &&
            _isSameDay(deliveredAt.toLocal(), now) &&
            status == 'DELIVERED';

        if (isTodayOrder) {
          orders += 1;
        }

        if (isDeliveredToday) {
          completed += 1;
          earnings += courierFeeNet;
        }
      }

      return _HomeTodayStats(
        orders: orders,
        earnings: earnings,
        completed: completed,
      );
    } catch (_) {
      final finance = await getFinanceSummary();

      return _HomeTodayStats(
        orders: _readInt(
          finance,
          const ['todayOrders'],
          fallbackKeys: const ['ordersToday', 'stats.todayOrders'],
        ),
        earnings: _readInt(
          finance,
          const ['todayEarnings'],
          fallbackKeys: const [
            'earningsToday',
            'todayIncome',
            'stats.todayEarnings',
          ],
        ),
        completed: _readInt(
          finance,
          const ['todayCompleted'],
          fallbackKeys: const [
            'completedToday',
            'completed',
            'stats.todayCompleted',
          ],
        ),
      );
    }
  }

  Future<int> getUnreadCount() async {
    try {
      final data = await _client.get('/notifications/unread-count');
      final map = _asMap(data);

      final count = _tryInt(map['count']);
      if (count != null) return count;

      final unreadCount = _tryInt(map['unreadCount']);
      if (unreadCount != null) return unreadCount;
    } catch (_) {
      // fallback below
    }

    try {
      final data = await _client.get('/notifications?page=1&limit=50');
      final map = _asMap(data);

      final direct = _tryInt(map['unreadCount']);
      if (direct != null) return direct;

      final meta = _readMap(map, const ['meta']);
      final metaUnread = _tryInt(meta?['unreadCount']);
      if (metaUnread != null) return metaUnread;

      final items = _extractList(map, const ['items']) ?? const [];

      return items
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => item['isRead'] != true)
          .length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> setOnline(bool value) async {
    await _client.patch('/couriers/me/online', {
      'isOnline': value,
      'source': 'mobile',
    });
  }

  Future<void> updateCourierOrderStatus({
    required String orderId,
    required String status,
  }) async {
    await _client.patch('/orders/courier/$orderId/status', {
      'status': status,
    });
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<dynamic>? _extractList(
    Map<String, dynamic> json,
    List<String> path,
  ) {
    dynamic current = json;

    for (final part in path) {
      if (current is Map<String, dynamic> && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }

    return current is List ? current : null;
  }

  dynamic _readValue(
    Map<String, dynamic> json,
    List<String> path,
  ) {
    dynamic current = json;

    for (final part in path) {
      if (current is Map<String, dynamic> && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }

    return current;
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  int _resolveNetCourierPayout(Map<String, dynamic> order) {
    final net = _tryInt(_readValue(order, const ['courierFee']));
    if (net != null && net >= 0) return net;

    final gross = _tryInt(
          _readValue(order, const ['courierFeeGross']) ??
              _readValue(order, const ['courierPayout']) ??
              _readValue(order, const ['courierFeeApplied']),
        ) ??
        0;

    final commission =
        _tryInt(_readValue(order, const ['courierCommissionAmount'])) ?? 0;

    final computed = gross - commission;
    if (computed >= 0) return computed;

    return 0;
  }
}

class _HomeTodayStats {
  const _HomeTodayStats({
    required this.orders,
    required this.earnings,
    required this.completed,
  });

  final int orders;
  final int earnings;
  final int completed;
}

Map<String, dynamic>? _normalizeActiveOrder(Map<String, dynamic>? raw) {
  if (raw == null || raw.isEmpty) return null;

  final restaurant = _readMap(raw, const ['restaurant']);
  final address = _readMap(raw, const ['address']);
  final client = _readMap(raw, const ['user']);

  final orderNumber = _readString(
    raw,
    const ['number'],
    fallbackKeys: const ['orderNumber'],
    fallbackValue: '—',
  );

  final restaurantName = _readString(
    raw,
    const ['restaurantName'],
    fallbackKeys: const ['restaurant.name', 'restaurant.titleRu'],
    fallbackValue: '',
  );

  final restaurantAddress = _readString(
    raw,
    const ['restaurantAddress'],
    fallbackKeys: const ['restaurant.address', 'pickupAddress'],
    fallbackValue: '',
  );

  final clientAddress = _buildClientAddress(raw, address);
  final payout = _resolveActiveOrderNetPayout(raw);

  final deadlineText =
      _formatTime(
        _readNullableString(
          raw,
          const ['promisedAt'],
          fallbackKeys: const ['deadline', 'pickupDeadline'],
        ),
      ) ??
      '—';

  return {
    'id': _readString(raw, const ['id'], fallbackValue: ''),
    'status': _readString(raw, const ['status'], fallbackValue: ''),
    'orderNumber': orderNumber,
    'restaurantName': restaurantName.isNotEmpty
        ? restaurantName
        : (restaurant?['name'] ?? '').toString(),
    'restaurantAddress': restaurantAddress,
    'clientAddress': clientAddress,
    'courierPayout': payout,
    'deadlineText': deadlineText,
    'clientName': _buildClientName(client),
  };
}

int _resolveActiveOrderNetPayout(Map<String, dynamic> raw) {
  final net = _readInt(
    raw,
    const ['courierFee'],
    fallbackKeys: const ['courierNetFee', 'courierNetPayout'],
  );
  if (net > 0) return net;

  final gross = _readInt(
    raw,
    const ['courierFeeGross'],
    fallbackKeys: const ['courierPayout', 'courierFeeApplied'],
  );
  final commission = _readInt(
    raw,
    const ['courierCommissionAmount'],
  );

  final computed = gross - commission;
  return computed > 0 ? computed : 0;
}

String _buildClientAddress(
  Map<String, dynamic> raw,
  Map<String, dynamic>? address,
) {
  final direct = _readNullableString(
    raw,
    const ['clientAddress'],
    fallbackKeys: const [
      'deliveryAddress',
      'deliveryAddressText',
      'address.address',
    ],
  );
  if (direct != null && direct.trim().isNotEmpty) {
    return direct;
  }

  if (address == null || address.isEmpty) {
    return '';
  }

  final mainAddress =
      (address['address'] ?? address['title'] ?? '').toString().trim();

  final entrance =
      (address['entrance'] ?? address['door'] ?? '').toString().trim();

  final floor = (address['floor'] ?? '').toString().trim();
  final intercom = (address['intercom'] ?? '').toString().trim();

  final parts = <String>[
    if (mainAddress.isNotEmpty) mainAddress,
    if (entrance.isNotEmpty) 'подъезд: $entrance',
    if (floor.isNotEmpty) 'этаж: $floor',
    if (intercom.isNotEmpty) 'домофон: $intercom',
  ];

  return parts.join(', ');
}

String _buildClientName(Map<String, dynamic>? client) {
  if (client == null || client.isEmpty) return '';
  final parts = <String>[
    (client['firstName'] ?? '').toString().trim(),
    (client['lastName'] ?? '').toString().trim(),
  ].where((e) => e.isNotEmpty).toList();
  return parts.join(' ');
}

String? _formatTime(String? iso) {
  if (iso == null || iso.trim().isEmpty) return null;
  final dt = DateTime.tryParse(iso);
  if (dt == null) return null;
  final local = dt.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

Map<String, dynamic>? _readMap(
  Map<String, dynamic> json,
  List<String> path,
) {
  dynamic current = json;
  for (final part in path) {
    if (current is Map<String, dynamic> && current.containsKey(part)) {
      current = current[part];
    } else {
      return null;
    }
  }

  if (current is Map<String, dynamic>) return current;
  if (current is Map) return Map<String, dynamic>.from(current);
  return null;
}

String _readString(
  Map<String, dynamic> json,
  List<String> path, {
  List<String> fallbackKeys = const [],
  String fallbackValue = '',
}) {
  final first = _readNullableString(json, path);
  if (first != null && first.trim().isNotEmpty) return first;

  for (final key in fallbackKeys) {
    final value = _readByKeyPath(json, key);
    if (value != null) {
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
  }

  return fallbackValue;
}

String? _readNullableString(
  Map<String, dynamic> json,
  List<String> path, {
  List<String> fallbackKeys = const [],
}) {
  dynamic current = json;
  for (final part in path) {
    if (current is Map<String, dynamic> && current.containsKey(part)) {
      current = current[part];
    } else {
      current = null;
      break;
    }
  }

  if (current != null) {
    final text = current.toString();
    if (text.trim().isNotEmpty) return text;
  }

  for (final key in fallbackKeys) {
    final value = _readByKeyPath(json, key);
    if (value != null) {
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
  }

  return null;
}

bool _readBool(
  Map<String, dynamic> json,
  List<String> path, {
  List<String> fallbackKeys = const [],
}) {
  dynamic current = json;
  for (final part in path) {
    if (current is Map<String, dynamic> && current.containsKey(part)) {
      current = current[part];
    } else {
      current = null;
      break;
    }
  }

  final parsed = _tryBool(current);
  if (parsed != null) return parsed;

  for (final key in fallbackKeys) {
    final fallback = _tryBool(_readByKeyPath(json, key));
    if (fallback != null) return fallback;
  }

  return false;
}

int _readInt(
  Map<String, dynamic> json,
  List<String> path, {
  List<String> fallbackKeys = const [],
}) {
  dynamic current = json;
  for (final part in path) {
    if (current is Map<String, dynamic> && current.containsKey(part)) {
      current = current[part];
    } else {
      current = null;
      break;
    }
  }

  final parsed = _tryInt(current);
  if (parsed != null) return parsed;

  for (final key in fallbackKeys) {
    final fallback = _tryInt(_readByKeyPath(json, key));
    if (fallback != null) return fallback;
  }

  return 0;
}

dynamic _readByKeyPath(Map<String, dynamic> json, String keyPath) {
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

int? _tryInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

bool? _tryBool(dynamic value) {
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  return null;
}

class _CompactStatCard extends StatelessWidget {
  const _CompactStatCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 126,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFD8DDE6),
          width: 1.3,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 20,
            ),
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.black,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF7E8794),
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}