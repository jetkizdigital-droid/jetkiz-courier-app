import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/localization/courier_locale.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/features/notifications/data/courier_notifications_api.dart';
import 'package:jetkiz_courier_app/features/notifications/domain/courier_notification_item.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/courier_order_details_page.dart';

class CourierNotificationsPage extends StatefulWidget {
  const CourierNotificationsPage({super.key});

  @override
  State<CourierNotificationsPage> createState() =>
      _CourierNotificationsPageState();
}

class _CourierNotificationsPageState extends State<CourierNotificationsPage> {
  late final CourierNotificationsApi _api;
  bool _loading = true;
  bool _refreshing = false;
  bool _markingAll = false;
  String? _errorKey;
  List<CourierNotificationItem> _items = const [];

  CourierLocaleController get _locale => CourierLocaleController.instance;

  @override
  void initState() {
    super.initState();
    _api = CourierNotificationsApi();
    unawaited(_load());
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
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
      final items = <CourierNotificationItem>[];
      const pageSize = 50;
      for (var page = 1; page <= 10; page++) {
        final result = await _api.getNotifications(page: page, limit: pageSize);
        items.addAll(result.items);
        if (result.items.length < pageSize) break;
      }
      if (!mounted) return;
      setState(() => _items = items);
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

  Future<void> _markAll() async {
    if (_markingAll || _items.every((item) => item.isRead)) return;
    setState(() => _markingAll = true);
    try {
      await _api.markAllRead();
      if (!mounted) return;
      setState(() {
        _items = _items.map((item) => item.copyWith(isRead: true)).toList();
      });
    } on ApiException catch (error) {
      _show(_locale.t(_errorFor(error)));
    } catch (_) {
      _show(_locale.t('error.generic'));
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _open(CourierNotificationItem item) async {
    if (!item.isRead && item.id.trim().isNotEmpty) {
      try {
        await _api.markRead(item.id);
        if (mounted) {
          setState(() {
            _items = _items
                .map(
                  (current) => current.id == item.id
                      ? current.copyWith(isRead: true)
                      : current,
                )
                .toList();
          });
        }
      } catch (_) {
        // Reading the target order is more important than the badge update.
      }
    }

    final orderId = item.orderId?.trim() ?? '';
    if (orderId.isEmpty || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CourierOrderDetailsPage(orderId: orderId),
      ),
    );
  }

  String _localizedTitle(CourierNotificationItem item) {
    if (!_locale.isKazakh) return item.title;
    final value = item.data['titleKk']?.toString().trim() ?? '';
    return value.isEmpty ? item.title : value;
  }

  String _localizedBody(CourierNotificationItem item) {
    if (!_locale.isKazakh) return item.body;
    final value = item.data['bodyKk']?.toString().trim() ?? '';
    return value.isEmpty ? item.body : value;
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_locale.t('notifications.title')),
        actions: [
          TextButton(
            onPressed: _markingAll ? null : _markAll,
            child: _markingAll
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_locale.t('notifications.markAll')),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorKey != null && _items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.notifications_off_outlined, size: 46),
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
            )
          : RefreshIndicator(
              onRefresh: () => _load(silent: true),
              child: _items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 140),
                        Icon(
                          Icons.notifications_none_rounded,
                          size: 52,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _locale.t('notifications.empty'),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return _NotificationTile(
                          item: item,
                          title: _localizedTitle(item),
                          body: _localizedBody(item),
                          onTap: () => _open(item),
                        );
                      },
                    ),
            ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final CourierNotificationItem item;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = item.createdAt?.toLocal();
    final dateText = date == null
        ? ''
        : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Material(
      color: item.isRead ? Colors.white : const Color(0xFFF0F9EE),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                item.isRead
                    ? Icons.notifications_none_rounded
                    : Icons.notifications_active_rounded,
                color: item.isRead
                    ? const Color(0xFF667085)
                    : const Color(0xFF3FAE2A),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty
                          ? CourierLocaleController.instance.t(
                              'notifications.default',
                            )
                          : title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(body),
                    ],
                    if (dateText.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        dateText,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if ((item.orderId ?? '').trim().isNotEmpty)
                const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
