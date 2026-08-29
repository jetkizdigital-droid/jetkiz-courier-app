class CourierFinanceResponse {
  const CourierFinanceResponse({
    required this.periodKey,
    required this.summary,
    required this.ledger,
  });

  final String periodKey;
  final CourierFinanceSummary summary;
  final List<CourierFinanceLedgerItem> ledger;

  factory CourierFinanceResponse.fromParts({
    required String periodKey,
    required Map<String, dynamic> summaryJson,
    required List<dynamic> ledgerJson,
  }) {
    final ledgerItems = ledgerJson
        .whereType<Map>()
        .map(
          (e) =>
              CourierFinanceLedgerItem.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();

    return CourierFinanceResponse(
      periodKey: periodKey,
      summary: CourierFinanceSummary.fromJson(summaryJson, ledgerItems),
      ledger: ledgerItems,
    );
  }

  int get availableToWithdraw => summary.availableToWithdraw;
  int get paidAmount => summary.paidAmount;
  int get assignedButUnpaidAmount => summary.assignedButUnpaidAmount;
  int get grossIncome => summary.grossIncome;
  int get commissionAmount => summary.commissionAmount;
  int get payoutAmount => summary.payoutAmount;
  int get deliveredOrdersCount => summary.deliveredOrdersCount;
  int get bonusesAmount => summary.bonusesAmount;
  int get deductionsAmount => summary.deductionsAmount;
}

class CourierFinanceSummary {
  const CourierFinanceSummary({
    required this.totalIncome,
    required this.totalPayout,
    required this.balance,
    required this.todayOrders,
    required this.todayCompleted,
    required this.todayEarnings,
    required this.grossAmount,
    required this.commissionAmount,
    required this.accruedPayoutAmount,
    required this.pendingPayoutAmount,
    required this.paidPayoutAmount,
    required this.unpaidButAssignedAmount,
    required this.deliveredOrdersCount,
    required this.bonusesAmount,
    required this.deductionsAmount,
  });

  final int totalIncome;
  final int totalPayout;
  final int balance;
  final int todayOrders;
  final int todayCompleted;
  final int todayEarnings;

  final int grossAmount;
  final int commissionAmount;
  final int accruedPayoutAmount;
  final int pendingPayoutAmount;
  final int paidPayoutAmount;
  final int unpaidButAssignedAmount;
  final int deliveredOrdersCount;
  final int bonusesAmount;
  final int deductionsAmount;

  int get availableToWithdraw {
    if (pendingPayoutAmount > 0) return pendingPayoutAmount;
    return balance < 0 ? 0 : balance;
  }

  int get paidAmount {
    if (paidPayoutAmount > 0) return paidPayoutAmount;
    return totalPayout < 0 ? 0 : totalPayout;
  }

  int get assignedButUnpaidAmount {
    if (unpaidButAssignedAmount > 0) return unpaidButAssignedAmount;
    return 0;
  }

  int get grossIncome {
    if (grossAmount > 0) return grossAmount;
    if (accruedPayoutAmount > 0) return accruedPayoutAmount;
    return totalIncome;
  }

  int get payoutAmount {
    if (accruedPayoutAmount > 0) return accruedPayoutAmount;
    return totalIncome;
  }

  factory CourierFinanceSummary.fromJson(
    Map<String, dynamic> json,
    List<CourierFinanceLedgerItem> ledger,
  ) {
    final ledgerStats = _buildLedgerStats(ledger);

    final totalIncome = _readInt(
      json,
      const ['totalIncome'],
      fallbackKeys: const [
        'income',
        'stats.totalIncome',
        'summary.totalIncome',
      ],
    );

    final totalPayout = _readInt(
      json,
      const ['totalPayout'],
      fallbackKeys: const [
        'payout',
        'stats.totalPayout',
        'summary.totalPayout',
      ],
    );

    final balance = _readInt(
      json,
      const ['balance'],
      fallbackKeys: const [
        'availableBalance',
        'stats.balance',
        'summary.balance',
      ],
    );

    final grossAmount = _readInt(
      json,
      const ['grossAmount'],
      fallbackKeys: const [
        'grossIncome',
        'summary.grossAmount',
        'summary.grossIncome',
        'totals.courierFeeGrossAmount',
      ],
    );

    final commissionAmount = _readInt(
      json,
      const ['commissionAmount'],
      fallbackKeys: const [
        'summary.commissionAmount',
        'totals.commissionAmount',
      ],
    );

    final accruedPayoutAmount = _readInt(
      json,
      const ['accruedPayoutAmount'],
      fallbackKeys: const [
        'summary.accruedPayoutAmount',
        'totals.accruedPayoutAmount',
      ],
    );

    final pendingPayoutAmount = _readInt(
      json,
      const ['pendingPayoutAmount'],
      fallbackKeys: const [
        'summary.pendingPayoutAmount',
        'totals.pendingPayoutAmount',
      ],
    );

    final paidPayoutAmount = _readInt(
      json,
      const ['paidPayoutAmount'],
      fallbackKeys: const [
        'summary.paidPayoutAmount',
        'totals.paidPayoutAmount',
      ],
    );

    final unpaidButAssignedAmount = _readInt(
      json,
      const ['unpaidButAssignedAmount'],
      fallbackKeys: const [
        'summary.unpaidButAssignedAmount',
        'totals.unpaidButAssignedAmount',
      ],
    );

    final deliveredOrdersCount = _readInt(
      json,
      const ['deliveredOrdersCount'],
      fallbackKeys: const [
        'summary.deliveredOrdersCount',
        'stats.deliveredOrdersCount',
      ],
    );

    return CourierFinanceSummary(
      totalIncome: totalIncome > 0 ? totalIncome : ledgerStats.netAccrued,
      totalPayout: totalPayout > 0 ? totalPayout : ledgerStats.payouts,
      balance: balance != 0 ? balance : ledgerStats.balance,
      todayOrders: _readInt(
        json,
        const ['todayOrders'],
        fallbackKeys: const ['ordersToday', 'stats.todayOrders'],
      ),
      todayCompleted: _readInt(
        json,
        const ['todayCompleted'],
        fallbackKeys: const ['completedToday', 'stats.todayCompleted'],
      ),
      todayEarnings: _readInt(
        json,
        const ['todayEarnings'],
        fallbackKeys: const ['earningsToday', 'stats.todayEarnings'],
      ),
      grossAmount: grossAmount > 0
          ? grossAmount
          : ledgerStats.grossOrderPayouts,
      commissionAmount: commissionAmount > 0
          ? commissionAmount
          : ledgerStats.commissionEstimate,
      accruedPayoutAmount: accruedPayoutAmount > 0
          ? accruedPayoutAmount
          : ledgerStats.netAccrued,
      pendingPayoutAmount: pendingPayoutAmount > 0
          ? pendingPayoutAmount
          : (balance != 0 ? balance : ledgerStats.balance).clamp(0, 1 << 30),
      paidPayoutAmount: paidPayoutAmount > 0
          ? paidPayoutAmount
          : (totalPayout > 0 ? totalPayout : ledgerStats.payouts),
      unpaidButAssignedAmount: unpaidButAssignedAmount,
      deliveredOrdersCount: deliveredOrdersCount > 0
          ? deliveredOrdersCount
          : ledgerStats.orderPayoutCount,
      bonusesAmount: ledgerStats.bonuses,
      deductionsAmount: ledgerStats.deductions,
    );
  }

  static _LedgerStats _buildLedgerStats(List<CourierFinanceLedgerItem> ledger) {
    var payouts = 0;
    var bonuses = 0;
    var deductions = 0;
    var grossOrderPayouts = 0;
    var netAccrued = 0;
    var orderPayoutCount = 0;

    for (final item in ledger) {
      final type = item.type.trim().toUpperCase();
      final amount = item.amount;

      if (type == 'ORDER_PAYOUT') {
        orderPayoutCount += 1;
        if (amount > 0) {
          grossOrderPayouts += amount;
          netAccrued += amount;
        }
        continue;
      }

      if (type == 'BONUS') {
        if (amount > 0) bonuses += amount;
        netAccrued += amount;
        continue;
      }

      if (type == 'PAYOUT') {
        payouts += amount.abs();
        continue;
      }

      if (type == 'DEDUCTION') {
        deductions += amount.abs();
        netAccrued += amount;
        continue;
      }

      if (type == 'MANUAL_ADJUSTMENT') {
        if (amount >= 0) {
          bonuses += amount;
        } else {
          deductions += amount.abs();
        }
        netAccrued += amount;
        continue;
      }

      if (amount >= 0) {
        netAccrued += amount;
      } else {
        deductions += amount.abs();
        netAccrued += amount;
      }
    }

    final balance = netAccrued - payouts;
    final commissionEstimate = grossOrderPayouts > netAccrued
        ? (grossOrderPayouts - netAccrued).clamp(0, 1 << 30)
        : 0;

    return _LedgerStats(
      payouts: payouts,
      bonuses: bonuses,
      deductions: deductions,
      grossOrderPayouts: grossOrderPayouts,
      netAccrued: netAccrued < 0 ? 0 : netAccrued,
      balance: balance < 0 ? 0 : balance,
      orderPayoutCount: orderPayoutCount,
      commissionEstimate: commissionEstimate,
    );
  }

  static int _readInt(
    Map<String, dynamic> json,
    List<String> path, {
    List<String> fallbackKeys = const [],
  }) {
    final value = _readValue(json, path, fallbackKeys: fallbackKeys);
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static dynamic _readValue(
    Map<String, dynamic> json,
    List<String> path, {
    List<String> fallbackKeys = const [],
  }) {
    dynamic current = json;

    for (final part in path) {
      if (current is Map<String, dynamic> && current.containsKey(part)) {
        current = current[part];
      } else if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        current = null;
        break;
      }
    }

    if (current != null) return current;

    for (final key in fallbackKeys) {
      final value = _readByKeyPath(json, key);
      if (value != null) return value;
    }

    return null;
  }

  static dynamic _readByKeyPath(Map<String, dynamic> json, String keyPath) {
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
}

class CourierFinanceLedgerItem {
  const CourierFinanceLedgerItem({
    required this.id,
    required this.type,
    required this.amount,
    required this.createdAt,
    this.orderId,
    this.orderNumber,
    this.note,
  });

  final String id;
  final String type;
  final int amount;
  final DateTime createdAt;
  final String? orderId;
  final int? orderNumber;
  final String? note;

  bool get isPositive => amount >= 0;

  factory CourierFinanceLedgerItem.fromJson(Map<String, dynamic> json) {
    return CourierFinanceLedgerItem(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      amount: _readInt(json, const ['amount'], fallbackKeys: const ['sum']),
      createdAt:
          _parseDateTime(
            _readValue(json, const ['createdAt'], fallbackKeys: const ['date']),
          ) ??
          DateTime.now(),
      orderId: _readNullableString(
        json,
        const ['orderId'],
        fallbackKeys: const ['order.id'],
      ),
      orderNumber: _readNullableInt(
        json,
        const ['orderNumber'],
        fallbackKeys: const ['order.number'],
      ),
      note: _readNullableString(
        json,
        const ['note'],
        fallbackKeys: const ['title', 'description'],
      ),
    );
  }

  static int _readInt(
    Map<String, dynamic> json,
    List<String> path, {
    List<String> fallbackKeys = const [],
  }) {
    final value = _readValue(json, path, fallbackKeys: fallbackKeys);
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _readNullableInt(
    Map<String, dynamic> json,
    List<String> path, {
    List<String> fallbackKeys = const [],
  }) {
    final value = _readValue(json, path, fallbackKeys: fallbackKeys);
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value.toString());
  }

  static String? _readNullableString(
    Map<String, dynamic> json,
    List<String> path, {
    List<String> fallbackKeys = const [],
  }) {
    final value = _readValue(json, path, fallbackKeys: fallbackKeys);
    final s = value?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static dynamic _readValue(
    Map<String, dynamic> json,
    List<String> path, {
    List<String> fallbackKeys = const [],
  }) {
    dynamic current = json;

    for (final part in path) {
      if (current is Map<String, dynamic> && current.containsKey(part)) {
        current = current[part];
      } else if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        current = null;
        break;
      }
    }

    if (current != null) return current;

    for (final key in fallbackKeys) {
      final value = _readByKeyPath(json, key);
      if (value != null) return value;
    }

    return null;
  }

  static dynamic _readByKeyPath(Map<String, dynamic> json, String keyPath) {
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

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}

class _LedgerStats {
  const _LedgerStats({
    required this.payouts,
    required this.bonuses,
    required this.deductions,
    required this.grossOrderPayouts,
    required this.netAccrued,
    required this.balance,
    required this.orderPayoutCount,
    required this.commissionEstimate,
  });

  final int payouts;
  final int bonuses;
  final int deductions;
  final int grossOrderPayouts;
  final int netAccrued;
  final int balance;
  final int orderPayoutCount;
  final int commissionEstimate;
}
