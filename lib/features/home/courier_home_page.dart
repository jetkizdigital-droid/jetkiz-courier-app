import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/events/courier_order_events.dart';
import 'package:jetkiz_courier_app/core/localization/courier_locale.dart';
import 'package:jetkiz_courier_app/core/location/courier_location_service.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/core/time/almaty_date_range.dart';
import 'package:jetkiz_courier_app/features/notifications/presentation/courier_notifications_page.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/courier_order_details_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class CourierHomePage extends StatefulWidget {
  const CourierHomePage({super.key});

  @override
  State<CourierHomePage> createState() => _CourierHomePageState();
}

class _CourierHomePageState extends State<CourierHomePage>
    with WidgetsBindingObserver {
  static const String _backgroundLocationDisclosureKey =
      'jetkiz.courier.background_location_disclosure.v1';
  static final Uri _privacyUri = Uri.parse('https://jetkiz.asia/privacy');

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
    _refreshing = true;

    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _errorKey = null;
      });
    }

    try {
      // Profile and active order are the data needed to make the home screen
      // usable. Do not keep the whole UI behind notification/finance metrics.
      final critical = await Future.wait<dynamic>([
        _api.getMe(),
        _api.getActiveOrder(),
      ]);

      final me = critical[0] as Map<String, dynamic>;
      final activeOrder = critical[1] as Map<String, dynamic>?;
      final profile = _map(me['courierProfile']) ?? _map(me['profile']);
      final firstName = _firstText([me['firstName'], profile?['firstName']]);
      final lastName = _firstText([me['lastName'], profile?['lastName']]);
      final fullName = [
        firstName,
        lastName,
      ].where((value) => value.isNotEmpty).join(' ');
      final online = _bool(me['isOnline']) || _bool(profile?['isOnline']);

      if (!mounted) return;
      final criticalChanged =
          _name != fullName ||
          _isOnline != online ||
          _activeOrderKey(_activeOrder) != _activeOrderKey(activeOrder) ||
          _errorKey != null ||
          _loading;

      if (criticalChanged) {
        setState(() {
          _name = fullName;
          _isOnline = online;
          _activeOrder = activeOrder;
          _errorKey = null;
          _loading = false;
        });
      }

      // Location is operationally important, but starting/stopping the native
      // tracking service must not hold the first usable frame hostage.
      unawaited(_syncLocationState(online, activeOrder));

      try {
        final secondary = await Future.wait<dynamic>([
          _api.getUnreadCount(),
          _api.getTodayMetrics(),
        ]);
        if (!mounted) return;

        final unread = secondary[0] as int;
        final metrics = secondary[1] as _TodayMetrics;
        if (_unread != unread ||
            _orders != metrics.orders ||
            _delivered != metrics.delivered ||
            _earnings != metrics.earnings) {
          setState(() {
            _unread = unread;
            _orders = metrics.orders;
            _delivered = metrics.delivered;
            _earnings = metrics.earnings;
          });
        }
      } catch (_) {
        // Secondary dashboard counters are best effort. Keep the last values
        // instead of turning an otherwise usable courier home into an error.
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _errorKey = _errorFor(error);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorKey = 'error.generic';
          _loading = false;
        });
      }
    } finally {
      _refreshing = false;
      if (mounted && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _syncLocationState(
    bool online,
    Map<String, dynamic>? activeOrder,
  ) async {
    try {
      if (online && !_location.isTracking) {
        final tracking = await _location.startTracking();
        if (!tracking.started && mounted) _show(tracking.message);
        return;
      }
      if (!online && _location.isTracking && activeOrder == null) {
        await _location.stopTracking();
      }
    } catch (_) {
      // Tracking errors are handled by the location service/next refresh. They
      // must not block or replace the home UI.
    }
  }

  String _activeOrderKey(Map<String, dynamic>? order) {
    if (order == null) return '';
    return [
      _text(order['id']),
      _text(order['number']),
      _text(order['status']),
      _text(order['updatedAt']),
      _text(order['courierFee']),
      _text(order['courierFeeGross']),
      _text(order['courierCommissionAmount']),
    ].join('|');
  }

  Future<bool> _ensureBackgroundLocationDisclosure() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_backgroundLocationDisclosureKey) == true) return true;
    if (!mounted) return false;

    final isKk = _locale.isKazakh;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isKk
              ? 'Фондық геолокацияны пайдалану'
              : 'Использование геолокации в фоне',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isKk
                    ? 'JETKIZ сіз желіде болған кезде тапсырыстарды тағайындау, жеткізу бағытын жүргізу және жеткізу барысын растау үшін нақты орналасқан жеріңізді пайдаланады.'
                    : 'JETKIZ использует ваше точное местоположение, когда вы на линии, чтобы назначать заказы, вести маршрут доставки и подтверждать ход доставки.',
              ),
              const SizedBox(height: 12),
              Text(
                isKk
                    ? 'Орналасқан жер туралы деректер қолданба жабық болғанда немесе экран өшірулі кезде де өңделуі және JETKIZ серверіне жіберілуі мүмкін. Бұл тек курьер желіде болған уақытта орындалады. Желіден шыққаннан кейін фондық геолокация тоқтатылады.'
                    : 'Данные о местоположении могут обрабатываться и передаваться на сервер JETKIZ, даже когда приложение закрыто или экран выключен. Это происходит только пока курьер находится на линии. После выхода с линии фоновая геолокация прекращается.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                isKk
                    ? 'Жалғастыру арқылы сіз жүйелік геолокация рұқсатын сұрауға өтесіз.'
                    : 'Нажав «Продолжить», вы перейдёте к системному запросу разрешения на геолокацию.',
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => unawaited(
                  launchUrl(_privacyUri, mode: LaunchMode.externalApplication),
                ),
                child: Text(
                  isKk ? 'Құпиялық саясаты' : 'Политика конфиденциальности',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(isKk ? 'Қазір емес' : 'Не сейчас'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isKk ? 'Жалғастыру' : 'Продолжить'),
          ),
        ],
      ),
    );

    if (accepted == true) {
      await prefs.setBool(_backgroundLocationDisclosureKey, true);
      return true;
    }
    return false;
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
        final disclosureAccepted = await _ensureBackgroundLocationDisclosure();
        if (!disclosureAccepted) return;

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
      MaterialPageRoute(builder: (_) => CourierOrderDetailsPage(orderId: id)),
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
                              icon: const Icon(
                                Icons.notifications_none_rounded,
                              ),
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
                      : '${locale.t('home.order')} №$number',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StatusPill(status: status),
            ],
          ),
          const SizedBox(height: 12),
          if (restaurant.isNotEmpty)
            _InfoRow(icon: Icons.storefront_outlined, text: restaurant),
          if (address.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoRow(icon: Icons.location_on_outlined, text: address),
          ],
          if (income > 0) ...[
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.payments_outlined,
              text: '${_formatMoney(income)} ₸',
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'ACCEPTED' => 'Принят',
      'COOKING' => 'Готовится',
      'READY' => 'Готов',
      'ON_THE_WAY' => 'В пути',
      'DELIVERED' => 'Доставлен',
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7E8),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF2E7D32),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 19, color: const Color(0xFF667085)),
      const SizedBox(width: 8),
      Expanded(child: Text(text)),
    ],
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4ED),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFF7C9A9)),
    ),
    child: Text(message),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
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
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Color(0xFF667085))),
      ],
    ),
  );
}

class _IncomeCard extends StatelessWidget {
  const _IncomeCard({required this.amount});

  final int amount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFF101828),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        const Icon(Icons.account_balance_wallet_outlined, color: Colors.white),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            CourierLocaleController.instance.t('home.earnings'),
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        Text(
          '${_formatMoney(amount)} ₸',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            locale.t(isOnline ? 'home.online' : 'home.offline'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            locale.t(
              isOnline ? 'home.onlineDescription' : 'home.offlineDescription',
            ),
            style: const TextStyle(color: Color(0xFF667085)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: loading ? null : onTap,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      isOnline ? Icons.pause_circle_outline : Icons.play_circle,
                    ),
              label: Text(
                locale.t(isOnline ? 'home.goOffline' : 'home.goOnline'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return <String, dynamic>{};
}

Map<String, dynamic>? _map(dynamic value) {
  if (value == null) return null;
  final map = _asMap(value);
  return map.isEmpty ? null : map;
}

String _text(dynamic value) => value?.toString().trim() ?? '';

String _firstText(List<dynamic> values) {
  for (final value in values) {
    final text = _text(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

bool _bool(dynamic value) => value == true || value?.toString() == 'true';

int? _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _formatMoney(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(raw[i]);
  }
  return buffer.toString();
}
