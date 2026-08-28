import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/features/finance/domain/courier_finance_models.dart';

class CourierFinanceApi {
  const CourierFinanceApi(this._apiClient);

  final ApiClient _apiClient;

  Future<CourierFinanceResponse> getFinance({
    String period = '30d',
    String? startDate,
    String? endDate,
  }) async {
    final resolvedPeriod = _normalizePeriod(period);
    final range = _resolveRange(
      resolvedPeriod,
      startDate: startDate,
      endDate: endDate,
    );

    final commonQuery = <String, String>{
      'from': range.from.toUtc().toIso8601String(),
      'to': range.to.toUtc().toIso8601String(),
    };

    final summaryPath = _buildPath(
      '/couriers/me/finance/summary',
      commonQuery,
    );

    final ledgerPath = _buildPath(
      '/couriers/me/finance/ledger',
      {
        ...commonQuery,
        'page': '1',
        'limit': '200',
      },
    );

    final results = await Future.wait<dynamic>([
      _apiClient.get(summaryPath),
      _apiClient.get(ledgerPath),
    ]);

    final summaryJson = _asMap(results[0]);
    final ledgerResponse = results[1];
    final ledgerItems =
        _extractList(ledgerResponse, const ['items']) ??
        _extractList(ledgerResponse, const ['data', 'items']) ??
        _extractList(ledgerResponse, const ['ledger']) ??
        _extractList(ledgerResponse, const ['data', 'ledger']) ??
        (ledgerResponse is List ? ledgerResponse : const []);

    return CourierFinanceResponse.fromParts(
      periodKey: resolvedPeriod,
      summaryJson: summaryJson,
      ledgerJson: ledgerItems,
    );
  }

  _FinanceRange _resolveRange(
    String period, {
    String? startDate,
    String? endDate,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endOfToday = today
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));

    switch (period) {
      case 'today':
        return _FinanceRange(today, endOfToday);
      case 'yesterday':
        final yesterday = today.subtract(const Duration(days: 1));
        return _FinanceRange(
          yesterday,
          today.subtract(const Duration(milliseconds: 1)),
        );
      case '7d':
        return _FinanceRange(
          today.subtract(const Duration(days: 6)),
          endOfToday,
        );
      case 'custom':
        final start = _parseLocalDate(startDate);
        final end = _parseLocalDate(endDate);

        if (start == null || end == null) {
          throw ArgumentError(
            'startDate and endDate are required for custom period',
          );
        }

        final normalizedStart = DateTime(start.year, start.month, start.day);
        final normalizedEnd = DateTime(end.year, end.month, end.day)
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1));

        if (normalizedEnd.isBefore(normalizedStart)) {
          throw ArgumentError('endDate must not be before startDate');
        }

        return _FinanceRange(normalizedStart, normalizedEnd);
      case '30d':
      default:
        return _FinanceRange(
          today.subtract(const Duration(days: 29)),
          endOfToday,
        );
    }
  }

  DateTime? _parseLocalDate(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;

    final direct = DateTime.tryParse(raw);
    if (direct != null) return direct;

    final match = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(raw);
    if (match == null) return null;

    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final year = int.tryParse(match.group(3)!);
    if (day == null || month == null || year == null) return null;

    return DateTime(year, month, day);
  }

  String _normalizePeriod(String value) {
    switch (value.trim().toLowerCase()) {
      case 'today':
        return 'today';
      case 'yesterday':
        return 'yesterday';
      case 'week':
      case '7d':
        return '7d';
      case 'custom':
        return 'custom';
      case 'month':
      case '30d':
      default:
        return '30d';
    }
  }

  String _buildPath(String basePath, Map<String, String> query) {
    return Uri(path: basePath, queryParameters: query).toString();
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<dynamic>? _extractList(dynamic json, List<String> path) {
    dynamic current = json;

    for (final part in path) {
      if (current is Map<String, dynamic> && current.containsKey(part)) {
        current = current[part];
      } else if (current is Map && current.containsKey(part)) {
        current = current[part];
      } else {
        return null;
      }
    }

    return current is List ? current : null;
  }
}

class _FinanceRange {
  const _FinanceRange(this.from, this.to);

  final DateTime from;
  final DateTime to;
}
