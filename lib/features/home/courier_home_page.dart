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

class CourierHomePage extends StatefulWidget {
  const CourierHomePage({super.key});

  @override
  State<CourierHomePage> createState() => _CourierHomePageState();
}

class _CourierHomePageState extends State<CourierHomePage>
    with WidgetsBindingObserver {
  static const _backgroundLocationDisclosureKey =
      'jetkiz.courier.background_location_disclosure.v1';

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
      final fullName = [
        firstName,
        lastName,
      ].where((value) => value.isNotEmpty).join(' ');
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
        final disclosed = await _ensureBackgroundLocationDisclosure();
        if (disclosed) {
          final tracking = await _location.startTracking();
          if (!tracking.started && mounted) _show(tracking.message);
        }
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
        final disclosed = await _ensureBackgroundLocationDisclosure();
        if (!disclosed) return;

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

  Future<bool> _ensureBackgroundLocationDisclosure() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_backgroundLocationDisclosureKey) == true) {
      return true;
    }
    if (!mounted) return false;

    final isKazakh = _locale.isKazakh;
    final title = isKazakh
        ? 'Фондық геолокация'
        : 'Геолокация в фоновом режиме';
    final body = isKazakh
        ? 'JETKIZ Курьер қолданбасы курьердің орналасқан жерін диспетчерге көрсету және тапсырыстарды тағайындау мен жеткізуді қамтамасыз ету үшін, қолданба жабық немесе пайдаланылмаған кезде де, орналасқан жер деректерін жинайды.'
        : 'JETKIZ Курьер собирает данные о местоположении, чтобы показывать диспетчеру положение курьера и обеспечивать назначение и выполнение доставок, даже когда приложение закрыто или не используется.';
    final continueLabel = isKazakh ? 'Жалғастыру' : 'Продолжить';

    final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(_locale.t('common.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(continueLabel),
              ),
            ],
          ),
        ) ??
        false;

    if (accepted) {
      await preferences.setBool(_backgroundLocationDisclosureKey, true);
    }
    return accepted;
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
        child: RefreshIndicator(
          onRefresh: () => _load(silent: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
            children: [
              _Header(
                name: displayName,
                unread: _unread,
                onNotifications: _openNotifications,
              ),
              const SizedBox(height: 18),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_errorKey != null)
                _ErrorCard(
                  message: _locale.t(_errorKey!),
                  onRetry: () => _load(),
                )
              else ...[
                _ShiftCard(
                  online: _isOnline,
                  changing: _changingOnline,
                  onToggle: _toggleOnline,
                ),
                const SizedBox(height: 14),
                _MetricsRow(
                  orders: _orders,
                  delivered: _delivered,
                  earnings: _earnings,
                ),
                const SizedBox(height: 14),
                if (_activeOrder != null)
                  _ActiveOrderCard(
                    order: _activeOrder!,
                    onOpen: _openActiveOrder,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CourierNotificationsPage()),
    );
    if (mounted) await _load(silent: true);
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.unread,
    required this.onNotifications,
  });

  final String name;
  final int unread;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final locale = CourierLocaleController.instance;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                locale.format('home.greeting', {'name': name}),
                style: const TextStyle(
                  fontSize: 25,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                locale.t('home.shift'),
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: locale.t('notifications.title'),
          onPressed: onNotifications,
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: const Icon(Icons.notifications_none_rounded),
          ),
        ),
      ],
    );
  }
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard({
    required this.online,
    required this.changing,
    required this.onToggle,
  });

  final bool online;
  final bool changing;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final locale = CourierLocaleController.instance;
    final color = online ? const Color(0xFF18B56B) : Colors.grey.shade700;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: online ? const Color(0xFFEAF9F1) : const Color(0xFFF4F5F7),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              online ? Icons.location_on_rounded : Icons.location_off_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  locale.t(online ? 'home.online' : 'home.offline'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  locale.t(online ? 'home.onlineHint' : 'home.offlineHint'),
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch.adaptive(
            value: online,
            onChanged: changing ? null : (_) => onToggle(),
          ),
        ],
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({
    required this.orders,
    required this.delivered,
    required this.earnings,
  });

  final int orders;
  final int delivered;
  final int earnings;

  @override
  Widget build(BuildContext context) {
    final locale = CourierLocaleController.instance;
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            label: locale.t('home.orders'),
            value: '$orders',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(
            label: locale.t('home.delivered'),
            value: '$delivered',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(
            label: locale.t('home.earned'),
            value: '$earnings ₸',
          ),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 11,
              height: 1.15,
            ),
          ),
        ],
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
    final locale = CourierLocaleController.instance;
    final id = _text(order['id']);
    final orderNumber = _text(order['orderNumber']);
    final number = orderNumber.isNotEmpty
        ? orderNumber
        : (id.length >= 8 ? id.substring(0, 8) : id);
    final restaurant = _text(_map(order['restaurant'])?['name']);
    final income = _int(order['courierIncome'] ?? order['courierPayout']);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101714),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            locale.t('home.activeOrder'),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            locale.format('home.orderNumber', {'number': number}),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (restaurant.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              restaurant,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            locale.format('home.income', {'amount': income}),
            style: const TextStyle(
              color: Color(0xFF69E7A6),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
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

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final locale = CourierLocaleController.instance;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3F2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text(locale.t('common.retry'))),
        ],
      ),
    );
  }
}

class _CourierHomeApi {
  _CourierHomeApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> getMe() async {
    return _map(await _client.get('/auth/me')) ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>?> getActiveOrder() async {
    try {
      final raw = await _client.get('/orders/courier/current');
      return _map(raw);
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<int> getUnreadCount() async {
    final raw = await _client.get('/notifications/unread-count');
    if (raw is num) return raw.toInt();
    final map = _map(raw);
    return _int(map?['count'] ?? map?['unreadCount']);
  }

  Future<_TodayMetrics> getTodayMetrics() async {
    final range = buildAlmatyDayRange(DateTime.now());
    try {
      final raw = await _client.get(
        '/couriers/me/stats?from=${range.fromUtc.toIso8601String()}&to=${range.toExclusiveUtc.toIso8601String()}',
      );
      final map = _map(raw) ?? <String, dynamic>{};
      return _TodayMetrics(
        orders: _int(map['ordersCount'] ?? map['totalOrders']),
        delivered: _int(map['deliveredCount'] ?? map['deliveredOrders']),
        earnings: _int(map['earnings'] ?? map['totalEarnings']),
      );
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        return const _TodayMetrics(orders: 0, delivered: 0, earnings: 0);
      }
      rethrow;
    }
  }

  Future<void> setOnline(bool online) async {
    await _client.patch('/couriers/me/status', {'isOnline': online});
  }
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

int _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _bool(dynamic value) {
  if (value is bool) return value;
  final text = value?.toString().toLowerCase();
  return text == 'true' || text == '1';
}
