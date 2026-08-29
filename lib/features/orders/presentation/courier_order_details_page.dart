import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/localization/courier_locale.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/core/services/two_gis_launcher.dart';
import 'package:jetkiz_courier_app/features/orders/data/courier_order_details_api.dart';
import 'package:jetkiz_courier_app/features/orders/domain/courier_order_details.dart';
import 'package:url_launcher/url_launcher.dart';

class CourierOrderDetailsPage extends StatefulWidget {
  const CourierOrderDetailsPage({super.key, required this.orderId});

  final String orderId;

  @override
  State<CourierOrderDetailsPage> createState() =>
      _CourierOrderDetailsPageState();
}

class _CourierOrderDetailsPageState extends State<CourierOrderDetailsPage>
    with WidgetsBindingObserver {
  late final ApiClient _client;
  late final CourierOrderDetailsApi _api;
  Timer? _pollTimer;
  CourierOrderDetails? _order;
  bool _loading = true;
  bool _refreshing = false;
  bool _submitting = false;
  String? _errorKey;

  CourierLocaleController get _locale => CourierLocaleController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _client = ApiClient();
    _api = CourierOrderDetailsApi(_client);
    unawaited(_load());
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_load(silent: true));
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
    if (state == AppLifecycleState.resumed) unawaited(_load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    if (mounted) {
      setState(() {
        _refreshing = silent;
        if (!silent) _loading = true;
        _errorKey = null;
      });
    }
    try {
      final order = await _api.getOrderDetails(widget.orderId);
      if (!mounted) return;
      setState(() => _order = order);
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorKey = _errorFor(error));
    } on FormatException {
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

  Future<void> _call(String? phone) async {
    final raw = phone?.trim() ?? '';
    if (raw.isEmpty) {
      _show(_locale.t('details.noPhone'));
      return;
    }
    final opened = await launchUrl(
      Uri.parse('tel:${raw.replaceAll(RegExp(r'\s+'), '')}'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) _show(_locale.t('details.callFailed'));
  }

  Future<void> _route(String? address) async {
    final raw = address?.trim() ?? '';
    if (raw.isEmpty) {
      _show(_locale.t('details.noAddress'));
      return;
    }
    try {
      await TwoGisLauncher.openRoute(destinationAddress: raw);
    } catch (_) {
      _show(_locale.t('details.routeFailed'));
    }
  }

  Future<void> _mainAction() async {
    final order = _order;
    if (order == null || _submitting) return;
    if (!order.canMarkPickedUp && !order.canMarkDelivered) {
      _show(_locale.t('details.actionUnavailable'));
      return;
    }

    final pickup = order.canMarkPickedUp;
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

    setState(() => _submitting = true);
    try {
      final updated = pickup
          ? await _api.markPickedUp(order.id)
          : await _api.markDelivered(order.id);
      if (!mounted) return;
      setState(() => _order = updated);
      _show(
        _locale.format(
          pickup ? 'orders.pickedSuccess' : 'orders.deliveredSuccess',
          {'number': order.number},
        ),
      );
      if (updated.isDelivered) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (mounted) Navigator.of(context).pop(true);
      }
    } on ApiException catch (error) {
      _show(_locale.t(_errorFor(error)));
      if (error.statusCode == 403 ||
          error.statusCode == 404 ||
          error.statusCode == 409) {
        await _load(silent: true);
      }
    } catch (_) {
      _show(_locale.t('error.generic'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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

  void _show(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          order == null
              ? _locale.t('orders.title')
              : _locale.format('details.title', {'number': order.number}),
        ),
        actions: [
          IconButton(
            onPressed: _refreshing ? null : () => _load(silent: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && order == null
          ? const Center(child: CircularProgressIndicator())
          : _errorKey != null && order == null
          ? _ErrorState(message: _locale.t(_errorKey!), onRetry: () => _load())
          : order == null
          ? const SizedBox.shrink()
          : RefreshIndicator(
              onRefresh: () => _load(silent: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                children: [
                  if (_refreshing) ...[
                    const LinearProgressIndicator(minHeight: 2),
                    const SizedBox(height: 10),
                  ],
                  _StatusCard(order: order),
                  const SizedBox(height: 12),
                  _PartyCard(
                    title: _locale.t('details.restaurant'),
                    icon: Icons.storefront_outlined,
                    name: order.restaurantName,
                    address: order.restaurantAddress,
                    phone: order.restaurantPhone,
                    onCall: () => _call(order.restaurantPhone),
                    onRoute: () => _route(order.restaurantAddress),
                  ),
                  const SizedBox(height: 12),
                  _PartyCard(
                    title: _locale.t('details.client'),
                    icon: Icons.person_outline_rounded,
                    name: order.clientName,
                    address: order.clientAddress,
                    phone: order.clientPhone,
                    onCall: () => _call(order.clientPhone),
                    onRoute: () => _route(order.clientAddress),
                  ),
                  if ((order.clientComment ?? '').trim().isNotEmpty ||
                      order.leaveAtDoor) ...[
                    const SizedBox(height: 12),
                    _CommentCard(order: order),
                  ],
                  if (order.items.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _ItemsCard(items: order.items),
                  ],
                  const SizedBox(height: 12),
                  _FinanceCard(order: order),
                  if (order.canMarkPickedUp || order.canMarkDelivered) ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        onPressed: _submitting ? null : _mainAction,
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _locale.t(
                                  order.canMarkPickedUp
                                      ? 'orders.pickupAction'
                                      : 'orders.deliverAction',
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.order});
  final CourierOrderDetails order;

  @override
  Widget build(BuildContext context) {
    final locale = CourierLocaleController.instance;
    return _Card(
      child: Row(
        children: [
          const Icon(Icons.local_shipping_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  locale.t('details.status'),
                  style: const TextStyle(color: Color(0xFF667085)),
                ),
                const SizedBox(height: 3),
                Text(
                  locale.t('status.${order.status.toUpperCase()}'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PartyCard extends StatelessWidget {
  const _PartyCard({
    required this.title,
    required this.icon,
    required this.name,
    required this.address,
    required this.phone,
    required this.onCall,
    required this.onRoute,
  });

  final String title;
  final IconData icon;
  final String? name;
  final String? address;
  final String? phone;
  final VoidCallback onCall;
  final VoidCallback onRoute;

  @override
  Widget build(BuildContext context) {
    final locale = CourierLocaleController.instance;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if ((name ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              name!.trim(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
          if ((address ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(address!.trim()),
          ],
          if ((phone ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(phone!.trim()),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCall,
                  icon: const Icon(Icons.phone_outlined),
                  label: Text(locale.t('details.call')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRoute,
                  icon: const Icon(Icons.route_outlined),
                  label: Text(locale.t('details.route')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({required this.order});
  final CourierOrderDetails order;

  @override
  Widget build(BuildContext context) {
    final locale = CourierLocaleController.instance;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            locale.t('details.comment'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if ((order.clientComment ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(order.clientComment!.trim()),
          ],
          if (order.leaveAtDoor) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.door_front_door_outlined, size: 19),
                const SizedBox(width: 7),
                Text(locale.t('details.leaveAtDoor')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.items});
  final List<CourierOrderLine> items;

  @override
  Widget build(BuildContext context) {
    final locale = CourierLocaleController.instance;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            locale.t('details.items'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: Text(item.title)),
                  Text('${item.quantity} × ${_money(item.price)} ₸'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceCard extends StatelessWidget {
  const _FinanceCard({required this.order});
  final CourierOrderDetails order;

  @override
  Widget build(BuildContext context) {
    final locale = CourierLocaleController.instance;
    final kk = locale.isKazakh;
    final gross = order.courierFeeGross ?? order.courierNetAmount ?? 0;
    final commission = order.courierCommissionAmount ?? 0;
    final payout = order.courierNetAmount ?? 0;
    final pct = order.courierCommissionPctApplied;
    final commissionLabel = pct == null
        ? (kk ? 'JETKIZ комиссиясы' : 'Комиссия JETKIZ')
        : (kk ? 'JETKIZ комиссиясы, $pct%' : 'Комиссия JETKIZ, $pct%');

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kk ? 'Тапсырыс бойынша есеп' : 'Расчёт по заказу',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _FinanceRow(
            label: kk ? 'Жеткізу үшін есептелді' : 'Начислено за доставку',
            amount: gross,
          ),
          const SizedBox(height: 8),
          _FinanceRow(label: commissionLabel, amount: commission),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          _FinanceRow(
            label: kk ? 'Төленуге тиіс' : 'К выплате',
            amount: payout,
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _FinanceRow extends StatelessWidget {
  const _FinanceRow({
    required this.label,
    required this.amount,
    this.emphasized = false,
  });

  final String label;
  final int amount;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontWeight: emphasized ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Text(
        '${_money(amount)} ₸',
        style: TextStyle(
          color: emphasized ? const Color(0xFF2F8731) : null,
          fontSize: emphasized ? 18 : 15,
          fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE4E8EF)),
    ),
    child: child,
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 46),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => unawaited(onRetry()),
            child: Text(CourierLocaleController.instance.t('common.retry')),
          ),
        ],
      ),
    ),
  );
}

String _money(int value) {
  final raw = value.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) out.write(' ');
    out.write(raw[i]);
  }
  return '${value < 0 ? '-' : ''}$out';
}
