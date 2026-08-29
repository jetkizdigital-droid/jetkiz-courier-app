import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/events/courier_order_events.dart';
import 'package:jetkiz_courier_app/core/localization/courier_locale.dart';
import 'package:jetkiz_courier_app/core/location/courier_location_service.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/core/time/almaty_date_range.dart';
import 'package:jetkiz_courier_app/features/notifications/presentation/courier_notifications_page.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/courier_order_details_page.dart';

class CourierHomePage extends StatefulWidget {
  const CourierHomePage({super.key});

  @override
  State<CourierHomePage> createState() => _CourierHomePageState();
}

class _CourierHomePageState extends State<CourierHomePage>
    with WidgetsBindingObserver {
  late final ApiClient _client;
  late final _CourierHomeApi _api;
  final CourierLocationService _location = CourierLocationService();

  Timer? _pollTimer;
  StreamSubscription<CourierOrderEvent>? _orderEvents;
  bool _foreground = true;
  bool _loading = true;
  bool _refreshing = false;
  bool _changingOnline = false;
  bool _isOnline = false;
  String _name = '';
  int _orders = 0;
  int _delivered = 0;
  int _earnings = 0;
  int _unread = 0;
  Map<String, dynamic>? _activeOrder;
  String? _errorKey;

  CourierLocaleController get _locale => CourierLocaleController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _client = ApiClient();
    _api = _CourierHomeApi(_client);
    _orderEvents = CourierOrderEvents.stream.listen((_) {
      if (_foreground) unawaited(_load(silent: true));
    });
    unawaited(_load());
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground) unawaited(_load(silent: true));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    unawaited(_orderEvents?.cancel());
    _client.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _foreground;
    _foreground = state == AppLifecycleState.resumed;
    if (!wasForeground && _foreground) unawaited(_load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    if (mounted) {
      setState(() {
        if (silent) {
          _refreshing = true;
        } else {
          _loading = true;
        }
        _errorKey = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _api.getMe(),
        _api.getActiveOrder(),
        _api.getUnreadCount(),
        _api.getTodayMetrics(),
      ]);

      final me = results[0] as Map<String, dynamic>;
      final profile = _map(me['courierProfile']) ?? _map(me['profile']);
      final firstName = _firstText([me['firstName'], profile?['firstName']]);
      final lastName = _firstText([me['lastName'], profile?['lastName']]);
      final fullName = [firstName, lastName]
          .where((value) => value.isNotEmpty)
          .join(' ');
      final online = _bool(me['isOnline']) || _bool(profile?['isOnline']);
      final metrics = results[3] as _TodayMetrics;

      if (!mounted) return;
      setState(() {
        _name = fullName;
        _isOnline = online;
        _activeOrder = results[1] as Map<String, dynamic>?;
        _unread = results[2] as int;
        _orders = metrics.orders;
        _delivered = metrics.delivered;
        _earnings = metrics.earnings;
      });

      if (online && !_location.isTracking) {
        final tracking = await _location.startTracking();
        if (!tracking.started && mounted) _show(tracking.message);
      }
      if (!online && _location.isTracking && _activeOrder == null) {
        await _location.stopTracking();
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorKey = _errorFor(error));
    } catch (_) {
      if (mounted) setState(() => _errorKey = 'error.generic');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _toggleOnline() async {
    if (_changingOnline) return;
    final next = !_isOnline;

    if (!next && _activeOrder != null) {
      _show(_locale.t('home.cannotOffline'));
      return;
    }

    setState(() => _changingOnline = true);
    try {
      if (next) {
        final permission = await _location.ensurePermission();
        if (!permission.allowed) {
          _show(permission.message);
          return;
        }

        await _api.setOnline(true);
        final tracking = await _location.startTracking();
        if (!tracking.started) {
          try {
            await _api.setOnline(false);
          } catch (_) {}
          _show(tracking.message);
          return;
        }
        if (mounted) setState(() => _isOnline = true);
        _show(_locale.t('home.onlineSuccess'));
      } else {
        await _api.setOnline(false);
        await _location.stopTracking();
        if (mounted) setState(() => _isOnline = false);
        _show(_locale.t('home.offlineSuccess'));
      }
    } on ApiException catch (error) {
      if (next) await _location.stopTracking();
      _show(_locale.t(_errorFor(error)));
    } catch (_) {
      if (next) await _location.stopTracking();
      _show(_locale.t('error.generic'));
    } finally {
      if (mounted) setState(() => _changingOnline = false);
    }
  }

  Future<void> _openActiveOrder() async {
    final id = _text(_activeOrder?['id']);
    if (id.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CourierOrderDetailsPage(orderId: id),
      ),
    );
    if (mounted) await _load(silent: true);
  }

  void _show(String message) {
    if (!mounted || message.trim().isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorFor(ApiException error) {
    switch (error.kind) {
      case ApiErrorKind.network:
        return 'error.network';
      case ApiErrorKind.timeout:
        return 'error.timeout';
      case ApiErrorKind.sessionExpired:
      case ApiErrorKind.unauthorized:
        return 'error.session';
      case ApiErrorKind.forbidden:
        return 'error.forbidden';
      default:
        return 'error.generic';
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _name.isEmpty ? _locale.t('home.courier') : _name;

    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () => _load(silent: true),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _locale.format('home.greeting', {
                                  'name': displayName,
                                }),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _locale.t('home.shift'),
                                style: const TextStyle(
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
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const CourierNotificationsPage(),
                                  ),
                                );
                                if (mounted) await _load(silent: true);
                              },
                              icon: const Icon(Icons.notifications_none_rounded),
                            ),
                            if (_unread > 0)
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
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    _unread > 99 ? '99+' : '$_unread',
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
                    if (_errorKey != null) ...[
                      const SizedBox(height: 14),
                      _ErrorCard(message: _locale.t(_errorKey!)),
                    ],
                    if (_activeOrder != null) ...[
                      const SizedBox(height: 18),
                      _ActiveOrderCard(
                        order: _activeOrder!,
                        onOpen: _openActiveOrder,
                      ),
                    ],
                    const SizedBox(height: 22),
                    Text(
                      _locale.t('home.today'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _MetricCard(
                            value: '$_orders',
                            label: _locale.t('home.orders'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MetricCard(
                            value: '$_delivered',
                            label: _locale.t('home.delivered'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _IncomeCard(amount: _earnings),
                    const SizedBox(height: 22),
                    _OnlineCard(
                      isOnline: _isOnline,
                      loading: _changingOnline,
                      onTap: _toggleOnline,
                    ),
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
  const _CourierHomeApi(this.client);

  final ApiClient client;

  Future<Map<String, dynamic>> getMe() async =>
      _asMap(await client.get('/couriers/me'));

  Future<Map<String, dynamic>?> getActiveOrder() async {
    final raw = _asMap(await client.get('/orders/courier/active'));
    if (raw.isEmpty) return null;
    final active = _map(raw['activeOrder']);
    final order = active ?? (_text(raw['id']).isNotEmpty ? raw : null);
    if (order == null) return null;
    if (_text(order['fulfillmentType']).toUpperCase() == 'PICKUP') return null;
    return order;
  }

  Future<int> getUnreadCount() async {
    final raw = _asMap(await client.get('/notifications/unread-count'));
    return _int(raw['count']) ?? _int(raw['unreadCount']) ?? 0;
  }

  Future<void> setOnline(bool value) async {
    await client.post('/couriers/me/online-status', {'isOnline': value});
  }

  Future<_TodayMetrics> getTodayMetrics() async {
    final range = AlmatyDateRange.today();
    final query = range.toQuery();
    final allPath = _path('/orders/courier/my', {
      ...query,
      'page': '1',
      'limit': '100',
    });
    final deliveredPath = _path('/orders/courier/history', {
      ...query,
      'status': 'DELIVERED',
      'page': '1',
      'limit': '100',
    });
    final financePath = _path('/couriers/me/finance/summary', query);

    final results = await Future.wait<dynamic>([
      client.get(allPath),
      client.get(deliveredPath),
      client.get(financePath),
    ]);

    final all = _asMap(results[0]);
    final delivered = _asMap(results[1]);
    final finance = _asMap(results[2]);

    return _TodayMetrics(
      orders: _resultCount(all, results[0]),
      delivered: _resultCount(delivered, results[1]),
      earnings:
          _int(finance['accruedPayoutAmount']) ??
          _int(_map(finance['stats'])?['accruedPayoutAmount']) ??
          0,
    );
  }

  static int _resultCount(Map<String, dynamic> map, dynamic raw) {
    final total = _int(map['total']);
    if (total != null) return total;
    final items = map['items'];
    if (items is List) return items.length;
    if (raw is List) return raw.length;
    return 0;
  }

  static String _path(String base, Map<String, String> query) =>
      Uri(path: base, queryParameters: query).toString();
}

class _TodayMetrics {
  const _TodayMetrics({
    required this.orders,
    required this.delivered,
    required this.earnings,
  });

  final int orders;
  final int delivered;
  final int earnings;
}

class _ActiveOrderCard extends StatelessWidget {
  const _ActiveOrderCard({required this.order, required this.onOpen});

  final Map<String, dynamic> order;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final locale = CourierLocaleController.instance;
    final number = _text(order['number']);
    final restaurant = _firstText([
      _map(order['restaurant'])?['nameRu'],
      _map(order['restaurant'])?['name'],
      order['restaurantName'],
    ]);
    final address = _firstText([
      order['clientAddress'],
      order['deliveryAddress'],
      order['deliveryAddressText'],
    ]);
    final status = _text(order['status']).toUpperCase();
    final income =
        _int(order['courierFee']) ??
        ((_int(order['courierFeeGross']) ?? 0) -
                (_int(order['courierCommissionAmount']) ?? 0))
            .clamp(0, 1 << 31)
            .toInt();

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
                  number.isEmpty
                      ? locale.t('home.activeOrder')
                      : locale.format('home.orderNumber', {'number': number}),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                locale.t('status.$status'),
                style: const TextStyle(
                  color: Color(0xFF175CD3),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (restaurant.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              restaurant,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
          if (address.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(address, style: const TextStyle(color: Color(0xFF667085))),
          ],
          const SizedBox(height: 12),
          Text(
            locale.format('home.income', {'amount': _money(income)}),
            style: const TextStyle(
              color: Color(0xFF2F8731),
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: onOpen,
              child: Text(locale.t('home.openOrder')),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.value, required this.label});
  final String value;
  final String label;

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
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: Color(0xFF667085))),
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
    final locale = CourierLocaleController.instance;
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9EE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFC8E8C1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              locale.t('home.earned'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '${_money(amount)} ₸',
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
    final locale = CourierLocaleController.instance;
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
                      locale.t(isOnline ? 'home.online' : 'home.offline'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      locale.t(
                        isOnline ? 'home.onlineHint' : 'home.offlineHint',
                      ),
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

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF5F5),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFF1C4C4)),
    ),
    child: Text(message),
  );
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

String _money(int value) {
  final negative = value < 0;
  final raw = value.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) out.write(' ');
    out.write(raw[i]);
  }
  return '${negative ? '-' : ''}$out';
}
