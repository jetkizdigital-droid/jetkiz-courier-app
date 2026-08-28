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
  late final ApiClient _client;
  late final _CourierHomeApi _api;
  final CourierLocationService _location = CourierLocationService();

  Timer? _pollTimer;
  bool _foreground = true;
  bool _loading = true;
  bool _refreshing = false;
  bool _polling = false;
  bool _changingOnline = false;

  bool _isOnline = false;
  String _courierName = 'Курьер';
  int _todayOrders = 0;
  int _todayCompleted = 0;
  int _todayEarnings = 0;
  int _unreadCount = 0;
  Map<String, dynamic>? _activeOrder;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _client = ApiClient();
    _api = _CourierHomeApi(_client);
    unawaited(_load());
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_foreground) unawaited(_pollOperationalState());
    });
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

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;

    if (silent) {
      if (mounted) setState(() => _refreshing = true);
    } else {
      if (mounted) {
        setState(() {
          _loading = true;
          _error = null;
        });
      }
    }

    try {
      final results = await Future.wait<dynamic>([
        _api.getMe(),
        _api.getTodayStats(),
        _api.getActiveOrder(),
        _api.getUnreadCount(),
      ]);

      final me = results[0] as Map<String, dynamic>;
      final stats = results[1] as _HomeTodayStats;
      final active = results[2] as Map<String, dynamic>?;
      final profile = _map(me['courierProfile']) ?? _map(me['profile']);
      final firstName = _text(me['firstName']).isNotEmpty
          ? _text(me['firstName'])
          : _text(profile?['firstName']);
      final lastName = _text(me['lastName']).isNotEmpty
          ? _text(me['lastName'])
          : _text(profile?['lastName']);
      final online = _bool(me['isOnline']) || _bool(profile?['isOnline']);

      if (!mounted) return;

      setState(() {
        final name = [
          firstName,
          lastName,
        ].where((value) => value.isNotEmpty).join(' ');
        _courierName = name.isEmpty ? 'Курьер' : name;
        _isOnline = online;
        _todayOrders = stats.orders;
        _todayCompleted = stats.completed;
        _todayEarnings = stats.earnings;
        _unreadCount = results[3] as int;
        _activeOrder = _normalizeActiveOrder(active);
        _error = null;
      });

      if (online && !_location.isTracking) {
        final tracking = await _location.startTracking();
        if (!tracking.started && mounted) {
          _showSnackBar(tracking.message);
        }
      }

      if (!online && _location.isTracking && _activeOrder == null) {
        await _location.stopTracking();
      }
    } catch (error) {
      if (mounted) setState(() => _error = _humanizeError(error));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
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

      final previousId = _text(_activeOrder?['id']);
      final next = _normalizeActiveOrder(results[0] as Map<String, dynamic>?);
      final nextId = _text(next?['id']);

      setState(() {
        _activeOrder = next;
        _unreadCount = results[1] as int;
      });

      if (previousId.isEmpty && nextId.isNotEmpty) {
        _showSnackBar('Поступил новый заказ');
      }
    } catch (_) {
      // Push is the primary signal; polling is only a fallback.
    } finally {
      _polling = false;
    }
  }

  Future<void> _toggleOnline() async {
    if (_changingOnline) return;

    final next = !_isOnline;

    if (!next && _activeOrder != null) {
      _showSnackBar('Нельзя уйти оффлайн, пока есть активный заказ.');
      return;
    }

    setState(() => _changingOnline = true);

    try {
      if (next) {
        final permission = await _location.ensurePermission();

        if (!permission.allowed) {
          _showSnackBar(permission.message);
          return;
        }

        await _api.setOnline(true);
        final tracking = await _location.startTracking();

        if (!tracking.started) {
          try {
            await _api.setOnline(false);
          } catch (_) {
            // Best effort rollback; the next bootstrap reconciles presence.
          }
          _showSnackBar(tracking.message);
          return;
        }

        if (mounted) setState(() => _isOnline = true);
        _showSnackBar('Вы на линии. Геолокация активна.');
      } else {
        await _api.setOnline(false);
        await _location.stopTracking();

        if (mounted) setState(() => _isOnline = false);
        _showSnackBar('Вы оффлайн.');
      }
    } catch (error) {
      if (next) await _location.stopTracking();
      _showSnackBar(_humanizeError(error));
    } finally {
      if (mounted) setState(() => _changingOnline = false);
    }
  }

  Future<void> _openActiveOrder() async {
    final id = _text(_activeOrder?['id']);
    if (id.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OrderDetailsPage(orderId: id)),
    );

    if (mounted) await _load(silent: true);
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
    if (error is FormatException) {
      return 'Сервер вернул некорректные данные. Попробуйте обновить экран.';
    }

    if (error is ApiException) {
      switch (error.kind) {
        case ApiErrorKind.network:
          return 'Нет соединения с сервером. Проверьте интернет.';
        case ApiErrorKind.timeout:
          return 'Сервер не ответил вовремя.';
        case ApiErrorKind.sessionExpired:
        case ApiErrorKind.unauthorized:
          return 'Сессия истекла. Войдите заново.';
        case ApiErrorKind.forbidden:
          return 'Действие недоступно для этого аккаунта.';
        default:
          return 'Не удалось обновить данные.';
      }
    }

    return 'Не удалось выполнить действие.';
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: CourierBottomBar(
        currentIndex: 0,
        onTap: _onBottomBarTap,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () => _load(silent: true),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    _HomeHeader(
                      name: _courierName,
                      unreadCount: _unreadCount,
                      onNotifications: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NotificationsPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _OnlineCard(
                      isOnline: _isOnline,
                      loading: _changingOnline,
                      onTap: _toggleOnline,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _ErrorBanner(message: _error!),
                    ],
                    if (_activeOrder != null) ...[
                      const SizedBox(height: 18),
                      _ActiveOrderCard(
                        order: _activeOrder!,
                        onOpen: _openActiveOrder,
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Text(
                      'Сегодня',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _MetricCard(
                            label: 'Заказов',
                            value: '$_todayOrders',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MetricCard(
                            label: 'Доставлено',
                            value: '$_todayCompleted',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _IncomeCard(amount: _todayEarnings),
                    if (_refreshing) ...[
                      const SizedBox(height: 18),
                      const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
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
    final raw = _asMap(await _client.get('/orders/courier/active'));
    if (raw.isEmpty) return null;

    final wrapped = _map(raw['activeOrder']);
    if (wrapped != null) return wrapped;

    // Backward compatibility for an older backend that returned the order
    // directly instead of { activeOrder, activeOrders }.
    return _text(raw['id']).isEmpty ? null : raw;
  }

  Future<int> getUnreadCount() async {
    final raw = _asMap(await _client.get('/notifications/unread-count'));
    return _int(raw['count']) ?? _int(raw['unreadCount']) ?? 0;
  }

  Future<void> setOnline(bool value) async {
    await _client.post('/couriers/me/online-status', {'isOnline': value});
  }

  Future<_HomeTodayStats> getTodayStats() async {
    final raw = _asMap(
      await _client.get('/orders/courier/my?page=1&limit=100'),
    );
    final values = raw['items'] is List ? raw['items'] as List : const <dynamic>[];
    final today = DateTime.now();
    var orders = 0;
    var completed = 0;
    var earnings = 0;

    for (final value in values.whereType<Map>()) {
      final order = Map<String, dynamic>.from(value);

      if (_text(order['fulfillmentType']).toUpperCase() == 'PICKUP') {
        continue;
      }

      final assignedAt = DateTime.tryParse(_text(order['assignedAt']));
      final createdAt = DateTime.tryParse(_text(order['createdAt']));
      final deliveredAt = DateTime.tryParse(_text(order['deliveredAt']));
      final status = _text(order['status']).toUpperCase();

      final start = assignedAt ?? createdAt;
      if (start != null && _sameDay(start.toLocal(), today)) {
        orders++;
      }

      if (status == 'DELIVERED' &&
          deliveredAt != null &&
          _sameDay(deliveredAt.toLocal(), today)) {
        completed++;
        final gross = _int(order['courierFeeGross']) ?? 0;
        final commission = _int(order['courierCommissionAmount']) ?? 0;
        final fallbackNet = (gross - commission).clamp(0, 1 << 31).toInt();
        earnings += _int(order['courierFee']) ?? fallbackNet;
      }
    }

    return _HomeTodayStats(
      orders: orders,
      completed: completed,
      earnings: earnings,
    );
  }
}

class _HomeTodayStats {
  const _HomeTodayStats({
    required this.orders,
    required this.completed,
    required this.earnings,
  });

  final int orders;
  final int completed;
  final int earnings;
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.name,
    required this.unreadCount,
    required this.onNotifications,
  });

  final String name;
  final int unreadCount;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Привет, $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Рабочая смена JETKIZ',
                style: TextStyle(
                  fontSize: 14,
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
              onPressed: onNotifications,
              icon: const Icon(Icons.notifications_none_rounded),
            ),
            if (unreadCount > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
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
    );
  }
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
    final background = isOnline ? const Color(0xFF2F8731) : Colors.white;
    final foreground = isOnline ? Colors.white : const Color(0xFF344054);

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              if (loading)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              else
                Icon(
                  isOnline
                      ? Icons.location_on_rounded
                      : Icons.location_off_outlined,
                  color: foreground,
                ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOnline ? 'Вы на линии' : 'Вы оффлайн',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isOnline
                          ? 'GPS активен для назначения и доставки'
                          : 'Выйдите на линию, чтобы получать заказы',
                      style: TextStyle(
                        fontSize: 13,
                        color: foreground.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
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
    final number = _text(order['number']);
    final restaurant = _text(order['restaurantName']);
    final clientAddress = _text(order['clientAddress']);
    final status = _statusLabel(_text(order['status']));
    final income = _int(order['courierPayout']) ?? 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
              Text(
                status,
                style: const TextStyle(
                  color: Color(0xFF175CD3),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (restaurant.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              restaurant,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
          if (clientAddress.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              clientAddress,
              style: const TextStyle(color: Color(0xFF667085)),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Ваш доход: ${_formatMoney(income)} ₸',
            style: const TextStyle(
              color: Color(0xFF2F8731),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: onOpen,
              child: const Text(
                'Открыть заказ',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

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
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF667085)),
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
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9EE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC8E8C1)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Заработано сегодня',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '${_formatMoney(amount)} ₸',
            style: const TextStyle(
              color: Color(0xFF2F8731),
              fontSize: 19,
              fontWeight: FontWeight.w900,
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
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Map<String, dynamic>? _normalizeActiveOrder(Map<String, dynamic>? raw) {
  if (raw == null || raw.isEmpty) return null;

  if (_text(raw['fulfillmentType']).toUpperCase() == 'PICKUP') {
    return null;
  }

  final restaurant = _map(raw['restaurant']);
  final address = _map(raw['address']);
  final gross = _int(raw['courierFeeGross']) ?? 0;
  final commission = _int(raw['courierCommissionAmount']) ?? 0;
  final payout = _int(raw['courierFee']) ??
      (gross - commission).clamp(0, 1 << 31).toInt();

  return <String, dynamic>{
    'id': _text(raw['id']),
    'number': _text(raw['number']),
    'status': _text(raw['status']),
    'restaurantName': _firstText([
      restaurant?['nameRu'],
      restaurant?['name'],
      raw['restaurantName'],
    ]),
    'clientAddress': _buildAddress(address, raw),
    'courierPayout': payout,
  };
}

String _buildAddress(
  Map<String, dynamic>? address,
  Map<String, dynamic> raw,
) {
  final direct = _firstText([
    raw['clientAddress'],
    raw['deliveryAddress'],
    raw['deliveryAddressText'],
  ]);

  if (direct.isNotEmpty) return direct;
  if (address == null) return '';

  final main = _firstText([address['address'], address['title']]);
  final entrance = _text(address['entrance']);
  final floor = _text(address['floor']);
  final door = _text(address['door']);
  final intercom = _text(address['intercom']);

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

String _text(dynamic value) => value?.toString().trim() ?? '';

String _firstText(List<dynamic> values) {
  for (final value in values) {
    final text = _text(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

int? _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(_text(value));
}

bool _bool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = _text(value).toLowerCase();
  return text == 'true' || text == '1';
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _formatMoney(int value) {
  final digits = value.abs().toString();
  final output = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) output.write(' ');
    output.write(digits[i]);
  }

  return '${value < 0 ? '-' : ''}$output';
}

String _statusLabel(String value) {
  switch (value.toUpperCase()) {
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
