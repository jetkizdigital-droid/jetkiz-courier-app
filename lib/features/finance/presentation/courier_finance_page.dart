import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/events/courier_order_events.dart';
import 'package:jetkiz_courier_app/core/localization/courier_locale.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/core/time/almaty_date_range.dart';

class CourierFinancePage extends StatefulWidget {
  const CourierFinancePage({super.key});

  @override
  State<CourierFinancePage> createState() => _CourierFinancePageState();
}

enum _FinancePeriod { today, yesterday, week, month, custom }

class _CourierFinancePageState extends State<CourierFinancePage>
    with WidgetsBindingObserver {
  late final ApiClient _client;
  Timer? _pollTimer;
  StreamSubscription<CourierOrderEvent>? _orderEvents;
  bool _foreground = true;
  bool _loading = true;
  bool _refreshing = false;
  String? _errorKey;
  _FinancePeriod _period = _FinancePeriod.month;
  DateTimeRange? _customRange;
  _FinanceSummary _summary = const _FinanceSummary();
  List<_LedgerItem> _ledger = const [];

  CourierLocaleController get _locale => CourierLocaleController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _client = ApiClient();
    _orderEvents = CourierOrderEvents.stream.listen((event) {
      if (_foreground) unawaited(_load(silent: true));
    });
    unawaited(_load());
    _pollTimer = Timer.periodic(const Duration(seconds: 45), (_) {
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

  AlmatyDateRange get _range {
    switch (_period) {
      case _FinancePeriod.today:
        return AlmatyDateRange.today();
      case _FinancePeriod.yesterday:
        return AlmatyDateRange.yesterday();
      case _FinancePeriod.week:
        return AlmatyDateRange.lastDays(7);
      case _FinancePeriod.month:
        return AlmatyDateRange.lastDays(30);
      case _FinancePeriod.custom:
        final range = _customRange;
        if (range == null) return AlmatyDateRange.lastDays(30);
        return AlmatyDateRange.custom(range.start, range.end);
    }
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
      final range = _range;
      final summaryPath = Uri(
        path: '/couriers/me/finance/summary',
        queryParameters: range.toQuery(),
      ).toString();
      final results = await Future.wait<dynamic>([
        _client.get(summaryPath),
        _loadLedger(range),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = _FinanceSummary.fromJson(_asMap(results[0]));
        _ledger = results[1] as List<_LedgerItem>;
      });
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

  Future<List<_LedgerItem>> _loadLedger(AlmatyDateRange range) async {
    final items = <_LedgerItem>[];
    const pageSize = 100;
    for (var page = 1; page <= 10; page++) {
      final path = Uri(
        path: '/couriers/me/finance/ledger',
        queryParameters: {
          ...range.toQuery(),
          'page': '$page',
          'limit': '$pageSize',
        },
      ).toString();
      final raw = await _client.get(path);
      final map = _asMap(raw);
      final rows = map['items'] is List
          ? map['items'] as List
          : raw is List
          ? raw
          : const <dynamic>[];
      items.addAll(
        rows.whereType<Map>().map(
          (row) => _LedgerItem.fromJson(Map<String, dynamic>.from(row)),
        ),
      );
      final total = _int(map['total']);
      if (rows.length < pageSize || (total != null && items.length >= total)) {
        break;
      }
    }
    return items;
  }

  Future<void> _selectPeriod(_FinancePeriod period) async {
    if (period == _FinancePeriod.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2024),
        lastDate: DateTime(now.year + 1, 12, 31),
        initialDateRange: _customRange ??
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
    setState(() => _period = period);
    await _load();
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
                    _locale.t('finance.title'),
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
                        _chip(_FinancePeriod.today, 'finance.today'),
                        _chip(_FinancePeriod.yesterday, 'finance.yesterday'),
                        _chip(_FinancePeriod.week, 'finance.week'),
                        _chip(_FinancePeriod.month, 'finance.month'),
                        _chip(_FinancePeriod.custom, 'finance.custom'),
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

  Widget _chip(_FinancePeriod period, String key) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      selected: _period == period,
      label: Text(_locale.t(key)),
      onSelected: (_) => _selectPeriod(period),
    ),
  );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_errorKey != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 46),
              const SizedBox(height: 12),
              Text(_locale.t(_errorKey!), textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _load,
                child: Text(_locale.t('common.retry')),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        children: [
          if (_refreshing) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: _locale.t('finance.accrued'),
                  value: '${_money(_summary.accrued)} ₸',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Metric(
                  label: _locale.t('finance.pending'),
                  value: '${_money(_summary.pending)} ₸',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: _locale.t('finance.paid'),
                  value: '${_money(_summary.paid)} ₸',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Metric(
                  label: _locale.t('finance.delivered'),
                  value: '${_summary.delivered}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            _locale.t('finance.history'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (_ledger.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Text(
                _locale.t('finance.empty'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF667085)),
              ),
            )
          else
            ..._ledger.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _LedgerTile(entry: entry),
              ),
            ),
        ],
      ),
    );
  }
}

class _FinanceSummary {
  const _FinanceSummary({
    this.accrued = 0,
    this.pending = 0,
    this.paid = 0,
    this.delivered = 0,
  });
  final int accrued;
  final int pending;
  final int paid;
  final int delivered;

  factory _FinanceSummary.fromJson(Map<String, dynamic> json) {
    final stats = _asMap(json['stats']);
    int read(String key) => _int(json[key]) ?? _int(stats[key]) ?? 0;
    return _FinanceSummary(
      accrued: read('accruedPayoutAmount'),
      pending: read('pendingPayoutAmount'),
      paid: read('paidPayoutAmount'),
      delivered: read('deliveredOrdersCount'),
    );
  }
}

class _LedgerItem {
  const _LedgerItem({required this.type, required this.amount, this.createdAt});
  final String type;
  final int amount;
  final DateTime? createdAt;
  factory _LedgerItem.fromJson(Map<String, dynamic> json) => _LedgerItem(
    type: (json['type'] ?? '').toString().trim(),
    amount: _int(json['amount']) ?? 0,
    createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE4E8EF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Color(0xFF667085))),
      ],
    ),
  );
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.entry});
  final _LedgerItem entry;
  @override
  Widget build(BuildContext context) {
    final positive = entry.type != 'PAYOUT';
    final date = entry.createdAt?.toLocal();
    final dateText = date == null
        ? ''
        : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E8EF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.type.isEmpty ? '—' : entry.type, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (dateText.isNotEmpty) Text(dateText, style: const TextStyle(color: Color(0xFF667085), fontSize: 12)),
              ],
            ),
          ),
          Text(
            '${positive ? '+' : '-'}${_money(entry.amount.abs())} ₸',
            style: TextStyle(
              color: positive ? const Color(0xFF2F8731) : const Color(0xFFB42318),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}
int? _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '');
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
