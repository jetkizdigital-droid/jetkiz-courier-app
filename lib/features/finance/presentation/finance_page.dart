import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/features/finance/data/courier_finance_api.dart';
import 'package:jetkiz_courier_app/features/finance/domain/courier_finance_models.dart';
import 'package:jetkiz_courier_app/features/home/home_page.dart';
import 'package:jetkiz_courier_app/features/navigation/navigation_presentation/widgets/courier_bottom_bar.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/orders_page.dart';
import 'package:jetkiz_courier_app/features/profile/presentation/profile_page.dart';

enum FinancePeriod { today, yesterday, week, month, custom }

class FinancePage extends StatefulWidget {
  const FinancePage({super.key});

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> with WidgetsBindingObserver {
  late final ApiClient _client;
  late final CourierFinanceApi _api;

  Timer? _pollTimer;
  FinancePeriod _period = FinancePeriod.month;
  DateTimeRange? _customRange;
  CourierFinanceResponse? _data;
  bool _foreground = true;
  bool _loading = true;
  bool _refreshing = false;
  bool _polling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _client = ApiClient();
    _api = CourierFinanceApi(_client);
    unawaited(_load());
    _pollTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (_foreground) unawaited(_load(silent: true, polling: true));
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

  Future<void> _load({bool silent = false, bool polling = false}) async {
    if (_refreshing || _polling) return;

    if (polling) {
      _polling = true;
    } else if (silent) {
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
      final data = await _api.getFinance(
        period: _periodApiValue(_period),
        startDate: _customRange == null ? null : _date(_customRange!.start),
        endDate: _customRange == null ? null : _date(_customRange!.end),
      );

      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _humanizeError(e));
    } finally {
      _polling = false;
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  String _periodApiValue(FinancePeriod period) {
    switch (period) {
      case FinancePeriod.today:
        return 'today';
      case FinancePeriod.yesterday:
        return 'yesterday';
      case FinancePeriod.week:
        return '7d';
      case FinancePeriod.month:
        return '30d';
      case FinancePeriod.custom:
        return 'custom';
    }
  }

  Future<void> _selectPeriod(FinancePeriod period) async {
    if (period == FinancePeriod.custom) {
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
        locale: const Locale('ru'),
        helpText: 'Период финансов',
        cancelText: 'Отмена',
        confirmText: 'Готово',
        saveText: 'Готово',
      );

      if (picked == null) return;
      setState(() {
        _period = period;
        _customRange = picked;
      });
    } else {
      setState(() {
        _period = period;
        _customRange = null;
      });
    }

    await _load();
  }

  void _onBottomBarTap(int index) {
    if (index == 2) return;

    final Widget page = switch (index) {
      0 => const HomePage(),
      1 => const OrdersPage(),
      3 => const ProfilePage(),
      _ => const FinancePage(),
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
          return 'Сервер не ответил вовремя.';
        case ApiErrorKind.sessionExpired:
        case ApiErrorKind.unauthorized:
          return 'Сессия истекла. Войдите заново.';
        default:
          return 'Не удалось загрузить финансы.';
      }
    }
    return 'Не удалось загрузить финансы.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: CourierBottomBar(
        currentIndex: 2,
        onTap: _onBottomBarTap,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Финансы',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: FinancePeriod.values.map((period) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            selected: period == _period,
                            label: Text(_periodLabel(period)),
                            onSelected: (_) => unawaited(_selectPeriod(period)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  if (_customRange != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${_viewDate(_customRange!.start)} — ${_viewDate(_customRange!.end)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF667085),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = _data;
    if (data == null) {
      return _FinanceState(
        title: 'Не удалось загрузить финансы',
        subtitle: _error ?? 'Попробуйте ещё раз.',
        onRetry: () => unawaited(_load()),
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => _load(silent: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _BalanceHero(
                available: data.availableToWithdraw,
                period: _currentPeriodLabel(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Metric(label: 'Начислено', value: _money(data.payoutAmount)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Metric(
                      label: 'В выплате',
                      value: _money(data.assignedButUnpaidAmount),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _Metric(label: 'Выплачено', value: _money(data.paidAmount)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Metric(
                      label: 'Доставок',
                      value: '${data.deliveredOrdersCount}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text('Расчёт', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              _Breakdown(
                gross: data.grossIncome,
                commission: data.commissionAmount,
                bonuses: data.bonusesAmount,
                deductions: data.deductionsAmount,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'История операций',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '${data.ledger.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF667085),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (data.ledger.isEmpty)
                const _EmptyLedger()
              else
                ...data.ledger.map((item) => _LedgerRow(item: item)),
            ],
          ),
        ),
        if (_refreshing || _polling)
          const Positioned(
            top: 8,
            right: 16,
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (_error != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5F5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF1C4C4)),
              ),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFB42318),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _periodLabel(FinancePeriod period) {
    switch (period) {
      case FinancePeriod.today:
        return 'Сегодня';
      case FinancePeriod.yesterday:
        return 'Вчера';
      case FinancePeriod.week:
        return '7 дней';
      case FinancePeriod.month:
        return '30 дней';
      case FinancePeriod.custom:
        return 'Период';
    }
  }

  String _currentPeriodLabel() => _periodLabel(_period).toLowerCase();

  String _date(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _viewDate(DateTime value) {
    final d = value.day.toString().padLeft(2, '0');
    final m = value.month.toString().padLeft(2, '0');
    return '$d.$m.${value.year}';
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.available, required this.period});
  final int available;
  final String period;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2F8731),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'К выводу',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _money(available),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text('за $period', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE4E8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({
    required this.gross,
    required this.commission,
    required this.bonuses,
    required this.deductions,
  });
  final int gross;
  final int commission;
  final int bonuses;
  final int deductions;

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
        children: [
          _row('До комиссии', gross),
          _row('Комиссия', -commission),
          if (bonuses != 0) _row('Бонусы', bonuses),
          if (deductions != 0) _row('Корректировки', -deductions),
        ],
      ),
    );
  }

  Widget _row(String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF667085)))),
          Text(_money(value), style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.item});
  final CourierFinanceLedgerItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
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
                Text(_ledgerTitle(item), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  _dateTime(item.createdAt),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
                ),
              ],
            ),
          ),
          Text(
            _money(item.amount),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: item.amount >= 0
                  ? const Color(0xFF2F8731)
                  : const Color(0xFFB42318),
            ),
          ),
        ],
      ),
    );
  }

  String _ledgerTitle(CourierFinanceLedgerItem item) {
    final order = item.orderNumber == null ? '' : ' №${item.orderNumber}';
    switch (item.type.toUpperCase()) {
      case 'ORDER_PAYOUT':
        return 'Начисление за заказ$order';
      case 'PAYOUT':
        return 'Выплата';
      case 'BONUS':
        return 'Бонус';
      case 'DEDUCTION':
        return 'Удержание';
      case 'MANUAL_ADJUSTMENT':
        return item.note?.trim().isNotEmpty == true ? item.note!.trim() : 'Корректировка';
      default:
        return item.note?.trim().isNotEmpty == true ? item.note!.trim() : 'Операция';
    }
  }
}

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E8EF)),
      ),
      child: const Text(
        'За выбранный период операций нет.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF667085)),
      ),
    );
  }
}

class _FinanceState extends StatelessWidget {
  const _FinanceState({
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });
  final String title;
  final String subtitle;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 46),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF667085)),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

String _money(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(' ');
    out.write(digits[i]);
  }
  return '${negative ? '-' : ''}$out ₸';
}

String _dateTime(DateTime value) {
  final local = value.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '$d.$m.${local.year} $h:$min';
}
