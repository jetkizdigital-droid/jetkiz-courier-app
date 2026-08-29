class AlmatyDateRange {
  const AlmatyDateRange(this.from, this.to);

  static const Duration _utcOffset = Duration(hours: 5);

  final DateTime from;
  final DateTime to;

  static AlmatyDateRange today() {
    final localNow = DateTime.now().toUtc().add(_utcOffset);
    final date = DateTime.utc(localNow.year, localNow.month, localNow.day);
    return _day(date);
  }

  static AlmatyDateRange yesterday() {
    final localNow = DateTime.now().toUtc().add(_utcOffset);
    final date = DateTime.utc(
      localNow.year,
      localNow.month,
      localNow.day,
    ).subtract(const Duration(days: 1));
    return _day(date);
  }

  static AlmatyDateRange lastDays(int days) {
    final normalizedDays = days < 1 ? 1 : days;
    final todayRange = today();
    final localToday = todayRange.from.toUtc().add(_utcOffset);
    final startLocalDate = DateTime.utc(
      localToday.year,
      localToday.month,
      localToday.day,
    ).subtract(Duration(days: normalizedDays - 1));
    return AlmatyDateRange(_startUtc(startLocalDate), todayRange.to);
  }

  static AlmatyDateRange custom(DateTime start, DateTime end) {
    final startDate = DateTime.utc(start.year, start.month, start.day);
    final endDate = DateTime.utc(end.year, end.month, end.day);
    if (endDate.isBefore(startDate)) {
      throw ArgumentError('end must not be before start');
    }
    return AlmatyDateRange(_startUtc(startDate), _endUtc(endDate));
  }

  Map<String, String> toQuery() => {
    'from': from.toUtc().toIso8601String(),
    'to': to.toUtc().toIso8601String(),
  };

  static AlmatyDateRange _day(DateTime localDate) =>
      AlmatyDateRange(_startUtc(localDate), _endUtc(localDate));

  static DateTime _startUtc(DateTime localDate) => DateTime.utc(
    localDate.year,
    localDate.month,
    localDate.day,
  ).subtract(_utcOffset);

  static DateTime _endUtc(DateTime localDate) => _startUtc(
    localDate.add(const Duration(days: 1)),
  ).subtract(const Duration(milliseconds: 1));
}
