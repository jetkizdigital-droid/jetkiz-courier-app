import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/events/courier_order_events.dart';
import 'package:jetkiz_courier_app/core/localization/courier_locale.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/core/time/almaty_date_range.dart';
import 'package:jetkiz_courier_app/features/orders/data/courier_order_details_api.dart';
import 'package:jetkiz_courier_app/features/orders/domain/courier_order_item.dart';

import 'courier_order_details_page.dart';

class CourierOrdersPage extends StatefulWidget {
  const CourierOrdersPage({super.key});

  @override
  State<CourierOrdersPage> createState() => _CourierOrdersPageState();
}

enum _OrdersPeriod { today, week, month, custom }

class _CourierOrdersPageState extends State<CourierOrdersPage>
    with WidgetsBindingObserver {
  late final ApiClient _client;
  late final CourierOrderDetailsApi _detailsApi;
  Timer? _pollTimer;
  StreamSubscription<CourierOrderEvent>? _orderEvents;

  bool _foreground = true;
  bool _tabActive = true;
  bool _loading = true;
  bool _refreshing = false;
  bool _requestInFlight = false;
  bool _reloadRequested = false;
  bool _pollingActive = false;
  bool _hasLoadedOnce = false;
  int _dataGeneration = 0;
  String? _actionOrderId;
  String? _errorKey;
  _OrdersPeriod _period = _OrdersPeriod.today;
  DateTimeRange? _customRange;
  CourierOrderItem? _active;
  List<CourierOrderItem> _history = const [];

  CourierLocaleController get _locale => CourierLocaleController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _client = ApiClient();
    _detailsApi = CourierOrderDetailsApi(_client);
    _orderEvents = CourierOrderEvents.stream.listen((_) {
      if (_foreground && _tabActive) {
        unawaited(_load(silent: true));
      }
    });
    unawaited(_load());
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground && _tabActive) {
        unawaited(_pollActiveOrder());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasActive = _tabActive;
    _tabActive = TickerMode.of(context);

    if (!wasActive && _tabActive) {
      unawaited(_load(silent: true));
    }
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
    if (!wasForeground && _foreground && _tabActive) {
      unawaited(_load(silent: true));
    }
  }

  AlmatyDateRange get _range {
    switch (_period) {
      case _OrdersPeriod.today:
        return AlmatyDateRange.today();
      case _OrdersPeriod.week:
        return AlmatyDateRange.lastDays(7);
      case _OrdersPeriod.month:
        return AlmatyDateRange.lastDays(30);
      case _OrdersPeriod.custom:
        final custom = _customRange;
        if (custom == null) return AlmatyDateRange.today();
        return AlmatyDateRange.custom(custom.start, custom.end);
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (_requestInFlight) {
      _reloadRequested = true;
      return;
    }

    _requestInFlight = true;
    final generation = _dataGeneration;
    final range = _range;
    final hadLoaded = _hasLoadedOnce;

    if (mounted) {
      setState(() {
        _refreshing = silent && hadLoaded;
        if (!silent && !hadLoaded) _loading = true;
        if (!silent || !hadLoaded) _errorKey = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _loadActive(),
        _loadHistory(range),
      ]);
      if (!mounted || generation != _dataGeneration) return;

      final active = results[0] as CourierOrderItem?;
      final history = (results[1] as List<CourierOrderItem>)
          .where((order) => active == null || order.id != active.id)
          .toList(growable: false);

      setState(() {
        _active = active;
        _history = history;
        _hasLoadedOnce = true;
        _errorKey = null;
      });
    } on ApiException catch (error) {
      if (mounted &&
          generation == _dataGeneration &&
          (!silent || !_hasLoadedOnce)) {
        setState(() => _errorKey = _errorFor(error));
      }
    } on FormatException {
      if (mounted &&
          generation == _dataGeneration &&
          (!silent || !_hasLoadedOnce)) {
        setState(() => _errorKey = 'error.generic');
      }
    } finally {
      _requestInFlight = false;

      if (mounted && generation == _dataGeneration) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }

      final shouldReload = _reloadRequested;
      _reloadRequested = false;
      if (mounted && shouldReload) {
        unawaited(_load(silent: _hasLoadedOnce));
      }
    }
  }

  Future<void> _pollActiveOrder() async {
    if (_requestInFlight || _pollingActive || !_foreground || !_tabActive) {
      return;
    }

    _pollingActive = true;
    final generation = _dataGeneration;
    final range = _range;
    try {
      final previousId = _active?.id;
      final previousKey = _orderFingerprint(_active);
      final nextActive = await _loadActive();
      if (!mounted || generation != _dataGeneration) return;

      final nextId = nextActive?.id;
      final nextKey = _orderFingerprint(nextActive);
      final historyContainsActive =
          nextId != null && _history.any((order) => order.id == nextId);

      if (previousKey != nextKey || historyContainsActive) {
        setState(() {
          _active = nextActive;
          if (nextId != null) {
            _history = _history
                .where((order) => order.id != nextId)
                .toList(growable: false);
          }
        });
      }

      // History is expensive and does not need to be downloaded every 30s.
      // Refresh it only when an active order actually leaves/replaces the slot.
      if (previousId != null && previousId != nextId) {
        final history = await _loadHistory(range);
        if (!mounted || generation != _dataGeneration) return;
        setState(() {
          _history = history
              .where((order) => nextId == null || order.id != nextId)
              .toList(growable: false);
        });
      }
    } catch (_) {
      // Polling is a best-effort fallback. Push/manual refresh remain available.
    } finally {
      _pollingActive = false;
    }
  }

  String _orderFingerprint(CourierOrderItem? order) {
    if (order == null) return '';
    return [
      order.id,
      order.number,
      order.status,
      order.fulfillmentType,
      order.assignedAt?.toIso8601String() ?? '',
      order.pickedUpAt?.toIso8601String() ?? '',
      order.deliveredAt?.toIso8601String() ?? '',
      order.promisedAt?.toIso8601String() ?? '',
      order.restaurantName ?? '',
      order.clientAddress ?? '',
      order.courierNetAmount ?? '',
    ].join('|');
  }

  Future<CourierOrderItem?> _loadActive() async {
    final raw = _asMap(await _client.get('/orders/courier/active'));
    if (raw.isEmpty) return null;
    final orderMap =
        _map(raw['activeOrder']) ?? (_text(raw['id']).isNotEmpty ? raw : null);
    if (orderMap == null) return null;
    if (_text(orderMap['fulfillmentType']).toUpperCase() == 'PICKUP') {
      return null;
    }
    return CourierOrderItem.fromJson(orderMap);
  }

  Future<List<CourierOrderItem>> _loadHistory(AlmatyDateRange range) async {
    final items = <CourierOrderItem>[];
    final seenIds = <String>{};
    const pageSize = 100;

    for (var page = 1; page <= 10; page++) {
      final path = Uri(
        path: '/orders/courier/history',
        queryParameters: {
          ...range.toQuery(),
          'page': '$page',
          'limit': '$pageSize',
        },
      ).toString();
      final raw = await _client.get(path);
      final map = _asMap(raw);
      final rows = _extractItems(raw);

      for (final row in rows.whereType<Map>()) {
        final json = Map<String, dynamic>.from(row);
        if (_text(json['fulfillmentType']).toUpperCase() == 'PICKUP') continue;
        final parsed = CourierOrderItem.fromJson(json);
        if (parsed.id.isEmpty || !seenIds.add(parsed.id)) continue;
        items.add(parsed);
      }

      final total = _int(map['total']);
      if (rows.length < pageSize || (total != null && items.length >= total)) {
        break;
      }
    }

    items.sort((a, b) => b.relevantDate.compareTo(a.relevantDate));
    return items;
  }

  List<dynamic> _extractItems(dynamic raw) {
    if (raw is List) return raw;
    final map = _asMap(raw);
    final items = map['items'];
    if (items is List) return items;
    final data = _map(map['data']);
    if (data?['items'] is List) return data!['items'] as List;
    return const [];
  }

  Future<void> _selectPeriod(_OrdersPeriod period) async {
    if (period == _OrdersPeriod.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2024),
        lastDate: DateTime(now.year + 1, 12, 31),
        initialDateRange:
            _customRange ??
            DateTimeRange(
              start: now.subtract(const Duration(days: 6)),
              end: now,
            ),
        helpText: _locale.t('orders.pickPeriod'),
        cancelText: _locale.t('common.cancel'),
        saveText: _locale.t('common.save'),
        locale: _locale.locale,
      );
      if (picked == null) return;
      _customRange = picked;
    }

    if (!mounted) return;
    _dataGeneration++;
    setState(() {
      _period = period;
      _errorKey = null;
    });
    await _load(silent: _hasLoadedOnce);
  }

  Future<void> _open(CourierOrderItem order) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CourierOrderDetailsPage(orderId: order.id),
      ),
    );
    if (mounted) await _load(silent: true);
  }

  Future<void> _quickAction(CourierOrderItem order) async {
    if (_actionOrderId != null || (!order.needsPickup && !order.isOnTheWay)) {
      return;
    }
    final pickup = order.needsPickup;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _locale.format('home.orderNumber', {'number': order.number}),
        ),
        content: Text(
          _locale.format(
            pickup ? 'orders.confirmPickup' : 'orders.confirmDelivery',
            {'number': order.number},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_locale.t('common.back')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              _locale.t(pickup ? 'orders.checked' : 'orders.deliveredButton'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _actionOrderId = order.id);
    try {
      if (pickup) {
        await _detailsApi.markPickedUp(order.id);
        _show(_locale.format('orders.pickedSuccess', {'number': order.number}));
      } else {
        await _detailsApi.markDelivered(order.id);
        _show(
          _locale.format('orders.deliveredSuccess', {'number': order.number}),
        );
      }
      await _load(silent: true);
    } on ApiException catch (error) {
      _show(_locale.t(_errorFor(error)));
      await _load(silent: true);
    } catch (_) {
      _show(_locale.t('error.generic'));
      await _load(silent: true);
    } finally {
      if (mounted) setState(() => _actionOrderId = null);
    }
  }

  void _show(String message) {
    if (!mounted) return;
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
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _locale.t('orders.title'),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _periodChip(_OrdersPeriod.today, 'orders.today'),
                        _periodChip(_OrdersPeriod.week, 'orders.week'),
                        _periodChip(_OrdersPeriod.month, 'orders.month'),
                        _periodChip(_OrdersPeriod.custom, 'orders.custom'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _periodChip(_OrdersPeriod value, String labelKey) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: _period == value,
        label: Text(_locale.t(labelKey)),
        onSelected: (_) => _selectPeriod(value),
      ),
    );
  }

  Widget _body() {
    if (_loading && !_hasLoadedOnce) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorKey != null && !_hasLoadedOnce) {
      return _StateView(
        icon: Icons.cloud_off_rounded,
        title: _locale.t(_errorKey!),
        action: _locale.t('common.retry'),
        onAction: _load,
      );
    }

    if (_active == null && _history.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            _StateView(
              icon: Icons.receipt_long_outlined,
              title: _locale.t('orders.empty'),
              action: _locale.t('common.refresh'),
              onAction: _load,
              embedded: true,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_active != null) ...[
                  Text(
                    _locale.t('orders.active'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  _OrderCard(
                    order: _active!,
                    actionLoading: _actionOrderId == _active!.id,
                    onOpen: () => _open(_active!),
                    onQuickAction: () => _quickAction(_active!),
                  ),
                  const SizedBox(height: 20),
                ],
                if (_history.isNotEmpty) ...[
                  Text(
                    _locale.t('orders.history'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                ],
              ]),
            ),
          ),
          if (_history.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              sliver: SliverList.builder(
                itemCount: _history.length,
                itemBuilder: (context, index) {
                  final order = _history[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _OrderCard(
                      order: order,
                      actionLoading: _actionOrderId == order.id,
                      onOpen: () => _open(order),
                      onQuickAction: () => _quickAction(order),
                    ),
                  );
                },
              ),
            )
          else
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.actionLoading,
    required this.onOpen,
    required this.onQuickAction,
  });

  final CourierOrderItem order;
  final bool actionLoading;
  final VoidCallback onOpen;
  final VoidCallback onQuickAction;

  @override
  Widget build(BuildContext context) {
    final locale = CourierLocaleController.instance;
    final quickAction = order.needsPickup || order.isOnTheWay;
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
          Row(
            children: [
              Expanded(
                child: Text(
                  locale.format('home.orderNumber', {'number': order.number}),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                locale.t('status.${order.status.toUpperCase()}'),
                style: const TextStyle(
                  color: Color(0xFF175CD3),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if ((order.restaurantName ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              order.restaurantName!.trim(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
          if ((order.clientAddress ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              order.clientAddress!.trim(),
              style: const TextStyle(color: Color(0xFF667085)),
            ),
          ],
          if (order.courierNetAmount != null) ...[
            const SizedBox(height: 8),
            Text(
              locale.format('home.income', {
                'amount': _money(order.courierNetAmount!),
              }),
              style: const TextStyle(
                color: Color(0xFF2F8731),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onOpen,
                  child: Text(locale.t('orders.open')),
                ),
              ),
              if (quickAction) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: actionLoading ? null : onQuickAction,
                    child: actionLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            locale.t(
                              order.needsPickup
                                  ? 'orders.pickupAction'
                                  : 'orders.deliverAction',
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StateView extends StatelessWidget {
  const _StateView({
    required this.icon,
    required this.title,
    required this.action,
    required this.onAction,
    this.embedded = false,
  });

  final IconData icon;
  final String title;
  final String action;
  final Future<void> Function() onAction;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 46, color: const Color(0xFF667085)),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () => unawaited(onAction()),
          child: Text(action),
        ),
      ],
    );
    return embedded
        ? Padding(padding: const EdgeInsets.all(24), child: child)
        : Center(
            child: Padding(padding: const EdgeInsets.all(24), child: child),
          );
  }
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

int? _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(_text(value));
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
