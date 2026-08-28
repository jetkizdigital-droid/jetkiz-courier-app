import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/location/courier_location_service.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/features/finance/presentation/finance_page.dart';
import 'package:jetkiz_courier_app/features/navigation/navigation_presentation/widgets/courier_bottom_bar.dart';
import 'package:jetkiz_courier_app/features/notifications/presentation/notifications_page.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/order_details_page.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/orders_page.dart';
import 'package:jetkiz_courier_app/features/profile/presentation/profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final _CourierHomeApi _api;
  late final CourierLocationService _locationService;

  Timer? _pollTimer;
  bool _foreground = true;
  bool _loading = true;
  bool _refreshing = false;
  bool _changingOnline = false;
  bool _polling = false;

  bool isOnline = false;
  String courierName = 'Курьер';
  int todayOrders = 0;
  int todayEarnings = 0;
  int todayCompleted = 0;
  int unreadCount = 0;
  Map<String, dynamic>? activeOrder;
  String error = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = _CourierHomeApi(ApiClient());
    _locationService = CourierLocationService();
    _loadInitial();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    unawaited(_locationService.dispose());
    _api.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _foreground;
    _foreground = state == AppLifecycleState.resumed;

    if (!wasForeground && _foreground) {
      unawaited(_refresh(silent: true));
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_foreground) unawaited(_pollOperationalState());
    });
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      error = '';
    });

    try {
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      setState(() => error = _humanizeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshing) return;

    if (!silent && mounted) {
      setState(() {
        _refreshing = true;
        error = '';
      });
    }

    try {
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      setState(() => error = _humanizeError(e));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _loadData() async {
    final results = await Future.wait<dynamic>([
      _api.getMe(),
      _api.getTodayStats(),
      _api.getActiveOrder(),
      _api.getUnreadCount(),
    ]);

    final me = results[0] as Map<String, dynamic>;
    final stats = results[1] as _HomeTodayStats;
    final active = results[2] as Map<String, dynamic>?;
    final unread = results[3] as int;

    final firstName = _string(me['firstName']);
    final lastName = _string(me['lastName']);
    final fullName = [firstName, lastName].where((e) => e.isNotEmpty).join(' ');
    final online = _bool(me['isOnline']) ||
        _bool(_map(me['profile'])?['isOnline']) ||
        _bool(_map(me['courierProfile'])?['isOnline']);

    if (!mounted) return;

    setState(() {
      courierName = fullName.isEmpty ? 'Курьер' : fullName;
      isOnline = online;
      todayOrders = stats.orders;
      todayEarnings = stats.earnings;
      todayCompleted = stats.completed;
      unreadCount = unread;
      activeOrder = _normalizeActiveOrder(active);
      error = '';
    });

    if (online && !_locationService.isTracking) {
      unawaited(_startLocationTrackingSilently());
    }

    if (!online && _locationService.isTracking && activeOrder == null) {
      unawaited(_locationService.stopTracking());
    }
  }

  Future<void> _pollOperationalState() async {
    if (_polling || _loading || _refreshing) return;
    _polling = true;

    try {
      final results = await Future.wait<dynamic>([
        _api.getActiveOrder(),
        _api.getUnreadCount(),
      ]);

      if (!mounted) return;

      final nextOrder = _normalizeActiveOrder(
        results[0] as Map<String, dynamic>?,
      );
      final previousId = _string(activeOrder?['id']);
      final nextId = _string(nextOrder?['id']);

      setState(() {
        activeOrder = nextOrder;
        unreadCount = results[1] as int;
      });

      if (previousId.isEmpty && nextId.isNotEmpty) {
        _showSnackBar('Поступил новый заказ');
      }
    } catch (_) {
      // Background polling is best-effort. Push remains the primary signal.
    } finally {
      _polling = false;
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
      // The screen stays usable; the next foreground/resume retries tracking.
    }
  }

  Future<void> _toggleOnline() async {
    if (_changingOnline) return;

    final next = !isOnline;

    if (!next && activeOrder != null) {
      _showSnackBar('Нельзя уйти оффлайн, пока есть активный заказ.');
      return;
    }

    setState(() => _changingOnline = true);

    try {
      if (next) {
        final permission = await _locationService.ensurePermission();
        if (!permission.allowed) {
          _showSnackBar(permission.message);
          return;
        }

        await _api.setOnline(true);
        final tracking = await _locationService.startTracking();

        if (!tracking.started) {
          await _api.setOnline(false).catchError((_) {});
          _showSnackBar(tracking.message);
          return;
        }

        if (!mounted) return;
        setState(() => isOnline = true);
        _showSnackBar('Вы на линии. Геолокация активна.');
      } else {
        await _api.setOnline(false);
        await _locationService.stopTracking();

        if (!mounted) return;
        setState(() => isOnline = false);
        _showSnackBar('Вы оффлайн.');
      }
    } catch (e) {
      if (next) {
        await _locationService.stopTracking();
      }
      _showSnackBar(_humanizeError(e));
    } finally {
      if (mounted) setState(() => _changingOnline = false);
    }
  }

  Future<void> _openActiveOrder() async {
    final id = _string(activeOrder?['id']);
    if (id.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OrderDetailsPage(orderId: id)),
    );

    if (mounted) await _refresh(silent: true);
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsPage()),
    );
  }

  void _onBottomBarTap(int index) {
    if (index == 0) return;

    final Widget page = switch (index) {
      1 => const OrdersPage(),
      2 => const FinancePage(),
      3 => const ProfilePage(),
      _ => const HomePage(),
    };

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  String _humanizeError(Object error) {
    if (error is ApiException) {
      switch (error.kind) {
        case ApiErrorKind.network:
          return 'Нет соединения с сервером. Проверьте интернет.';
        case ApiErrorKind.timeout:
          return 'Сервер не ответил вовремя. Попробуйте ещё раз.';
        case ApiErrorKind.forbidden:
          return 'Действие недоступно для этого аккаунта.';
        case ApiErrorKind.sessionExpired:
        case ApiErrorKind.unauthorized:
          return 'Сессия истекла. Войдите заново.';
        default:
          return 'Не удалось обновить данные. Попробуйте ещё раз.';
      }
    }

    return 'Не удалось выполнить действие. Попробуйте ещё раз.';
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  String get _todayText {
    final now = DateTime.now();
    const months = [
      '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    return '${now.day} ${months[now.month]}';
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF8F8FA);
    const green = Color(0xFF3FAE2A);
    const darkGreen = Color(0xFF2F8731);

    return Scaffold(
      backgroundColor: bg,
      bottomNavigationBar: CourierBottomBar(
        currentIndex: 0,
        onTap: _onBottomBarTap,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  children: [
                    Row(
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
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Сегодня: $_todayText',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF667085),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconButton.filledTonal(
                              onPressed: _openNotifications,
                              icon: const Icon(Icons.notifications_none_rounded),
                            ),
                            if (unreadCount > 0)
                              Positioned(
                                right: -2,
                                top: -3,
                                child: Container(
                                  constraints: const BoxConstraints(minWidth: 20),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDC2626),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: bg, width: 2),
                                  ),
                                  child: Text(
                                    unreadCount > 99 ? '99+' : '$unreadCount',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _OnlineCard(
                      isOnline: isOnline,
                      loading: _changingOnline,
                      onTap: _toggleOnline,
                    ),
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _ErrorBanner(message: error),
                    ],
                    const SizedBox(height: 18),
                    if (activeOrder != null) ...[
                      _ActiveOrderCard(
                        order: activeOrder!,
                        onOpen: _openActiveOrder,
                      ),
                      const SizedBox(height: 20),
                    ],
                    const Text(
                      'Статистика за сегодня',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.receipt_long_outlined,
                            value: '$todayOrders',
                            label: 'Заказов',
                            accent: green,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.check_circle_outline_rounded,
                            value: '$todayCompleted',
                            label: 'Доставлено',
                            accent: darkGreen,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _IncomeCard(amount: todayEarnings),
                    if (_refreshing) ...[
                      const SizedBox(height: 18),
                      const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _CourierHomeApi {
  const _CourierHomeApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> getMe() async {
    return _asMap(await _client.get('/couriers/me'));
  }

  Future<Map<String, dynamic>?> getActiveOrder() async {
    final data = await _client.get('/orders/courier/active');
    if (data == null) return null;

    final map = _asMap(data);
    if (map.isEmpty) return null;
    return map;
  }

  Future<int> getUnreadCount() async {
    final data = _asMap(await _client.get('/notifications/unread-count'));
    return _int(data['count']) ?? _int(data['unreadCount']) ?? 0;
  }

  Future<void> setOnline(bool value) async {
    await _client.post('/couriers/me/online-status', {'isOnline': value});
  }

  Future<_HomeTodayStats> getTodayStats() async {
    final data = await _client.get('/orders/courier/my?page=1&limit=100');
    final map = _asMap(data);
    final items = (map['items'] is List ? map['items'] as List : const <dynamic>[])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e));

    final today = DateTime.now();
    var orders = 0;
    var completed = 0;
    var earnings = 0;

    for (final order in items) {
      final assignedAt = DateTime.tryParse(_string(order['assignedAt']));
      final createdAt = DateTime.tryParse(_string(order['createdAt']));
      final deliveredAt = DateTime.tryParse(_string(order['deliveredAt']));
      final status = _string(order['status']).toUpperCase();

      final base = assignedAt ?? createdAt;
      if (base != null && _sameDay(base.toLocal(), today)) {
        orders++;
      }

      if (status == 'DELIVERED' &&
          deliveredAt != null &&
          _sameDay(deliveredAt.toLocal(), today)) {
        completed++;
        final net = _int(order['courierFee']);
        final gross = _int(order['courierFeeGross']) ?? 0;
        final commission = _int(order['courierCommissionAmount']) ?? 0;
        earnings += net ?? (gross - commission).clamp(0, 1 << 31);
      }
    }

    return _HomeTodayStats(
      orders: orders,
      earnings: earnings,
      completed: completed,
    );
  }

  void dispose() => _client.dispose();
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

class _OnlineCard extends StatelessWidget {
  const _OnlineCard({
    required this.isOnline,
    required this.loading,
    required this.onTap,
  });

  final bool isOnline;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = isOnline
        ? const Color(0xFF2F8731)
        : const Color(0xFFEDEFF2);
    final foreground = isOnline ? Colors.white : const Color(0xFF475467);

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isOnline
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: foreground,
                        ),
                      )
                    : Icon(
                        isOnline
                            ? Icons.location_on_rounded
                            : Icons.location_off_outlined,
                        color: foreground,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOnline ? 'Вы на линии' : 'Вы оффлайн',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isOnline
                          ? 'GPS работает для назначения и доставки'
                          : 'Выйдите на линию, чтобы получать заказы',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: foreground.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveOrderCard extends StatelessWidget {
  const _ActiveOrderCard({required this.order, required this.onOpen});

  final Map<String, dynamic> order;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final number = _string(order['number']);
    final status = _statusLabel(_string(order['status']));
    final restaurant = _string(order['restaurantName']);
    final restaurantAddress = _string(order['restaurantAddress']);
    final clientAddress = _string(order['clientAddress']);
    final payout = _int(order['courierPayout']) ?? 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDDE3EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  number.isEmpty ? 'Активный заказ' : 'Заказ №$number',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF4FF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: const TextStyle(
                    color: Color(0xFF175CD3),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Line(icon: Icons.storefront_outlined, text: restaurant),
          if (restaurantAddress.isNotEmpty) ...[
            const SizedBox(height: 7),
            _Line(icon: Icons.pin_drop_outlined, text: restaurantAddress),
          ],
          if (clientAddress.isNotEmpty) ...[
            const SizedBox(height: 7),
            _Line(icon: Icons.flag_outlined, text: clientAddress),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ваш доход: ${_money(payout)} ₸',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2F8731),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2F8731),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Открыть заказ',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF667085)),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text.isEmpty ? '—' : text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: Color(0xFF344054),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF667085),
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomeCard extends StatelessWidget {
  const _IncomeCard({required this.amount});

  final int amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9EE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC8E8C1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments_outlined, color: Color(0xFF2F8731)),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Заработано сегодня',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '${_money(amount)} ₸',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2F8731),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1C4C4)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFFB42318),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Map<String, dynamic>? _normalizeActiveOrder(Map<String, dynamic>? raw) {
  if (raw == null || raw.isEmpty) return null;

  final fulfillmentType = _string(raw['fulfillmentType']).toUpperCase();
  if (fulfillmentType == 'PICKUP') {
    // Pickup is never a courier job. Ignore defensively even if stale data
    // exists on the backend.
    return null;
  }

  final restaurant = _map(raw['restaurant']);
  final address = _map(raw['address']);
  final gross = _int(raw['courierFeeGross']) ?? 0;
  final commission = _int(raw['courierCommissionAmount']) ?? 0;
  final net = _int(raw['courierFee']) ?? (gross - commission).clamp(0, 1 << 31);

  return <String, dynamic>{
    'id': _string(raw['id']),
    'number': _string(raw['number']),
    'status': _string(raw['status']),
    'restaurantName': _string(restaurant?['nameRu']).isNotEmpty
        ? _string(restaurant?['nameRu'])
        : _string(raw['restaurantName']),
    'restaurantAddress': _string(restaurant?['address']).isNotEmpty
        ? _string(restaurant?['address'])
        : _string(raw['restaurantAddress']),
    'clientAddress': _buildAddress(address, raw),
    'courierPayout': net,
  };
}

String _buildAddress(
  Map<String, dynamic>? address,
  Map<String, dynamic> raw,
) {
  final direct = _string(raw['clientAddress']);
  if (direct.isNotEmpty) return direct;
  if (address == null) return '';

  final main = _string(address['address']).isNotEmpty
      ? _string(address['address'])
      : _string(address['title']);
  final entrance = _string(address['entrance']);
  final floor = _string(address['floor']);
  final door = _string(address['door']);
  final intercom = _string(address['intercom']);

  return <String>[
    if (main.isNotEmpty) main,
    if (entrance.isNotEmpty) 'подъезд: $entrance',
    if (floor.isNotEmpty) 'этаж: $floor',
    if (door.isNotEmpty) 'квартира/дверь: $door',
    if (intercom.isNotEmpty) 'домофон: $intercom',
  ].join(', ');
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

Map<String, dynamic>? _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String _string(dynamic value) => value?.toString().trim() ?? '';

bool _bool(dynamic value) {
  if (value is bool) return value;
  final text = _string(value).toLowerCase();
  return text == 'true' || text == '1';
}

int? _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(_string(value));
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _money(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final out = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(' ');
    out.write(digits[i]);
  }

  return '${negative ? '-' : ''}$out';
}

String _statusLabel(String raw) {
  switch (raw.toUpperCase()) {
    case 'ACCEPTED':
      return 'Принят';
    case 'COOKING':
      return 'Готовится';
    case 'READY':
      return 'Готов';
    case 'ON_THE_WAY':
      return 'В пути';
    case 'DELIVERED':
      return 'Доставлен';
    default:
      return 'Активный';
  }
}
