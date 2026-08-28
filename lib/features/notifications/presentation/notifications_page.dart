import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/features/notifications/data/courier_notifications_api.dart';
import 'package:jetkiz_courier_app/features/notifications/domain/courier_notification_item.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/order_details_page.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/orders_page.dart';
import 'package:jetkiz_courier_app/features/profile/presentation/profile_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final CourierNotificationsApi _api;

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isMarkingAll = false;

  String _error = '';
  List<CourierNotificationItem> _items = <CourierNotificationItem>[];
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _api = CourierNotificationsApi();
    _load();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (mounted) {
      setState(() {
        if (silent) {
          _isRefreshing = true;
        } else {
          _isLoading = true;
          _error = '';
        }
      });
    }

    try {
      final result = await _api.getNotifications(page: 1, limit: 100);

      if (!mounted) return;

      setState(() {
        _items = result.items;
        _unreadCount = result.unreadCount;
        _error = '';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Не удалось загрузить уведомления';
      });
    } finally {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    if (_isMarkingAll || _items.isEmpty || _unreadCount <= 0) return;

    setState(() {
      _isMarkingAll = true;
    });

    try {
      await _api.markAllRead();

      if (!mounted) return;

      setState(() {
        _items = _items.map((item) => item.copyWith(isRead: true)).toList();
        _unreadCount = 0;
      });

      _showSnackBar('Все уведомления прочитаны');
    } catch (_) {
      _showSnackBar('Не удалось отметить уведомления');
    } finally {
      if (!mounted) return;

      setState(() {
        _isMarkingAll = false;
      });
    }
  }

  Future<void> _openNotification(CourierNotificationItem item) async {
    if (!item.isRead) {
      setState(() {
        _items = _items
            .map(
              (current) => current.id == item.id
                  ? current.copyWith(isRead: true)
                  : current,
            )
            .toList();
        _unreadCount = _unreadCount > 0 ? _unreadCount - 1 : 0;
      });

      try {
        await _api.markRead(item.id);
      } catch (_) {
        // Mark-read failure must not block navigation.
      }
    }

    if (!mounted) return;

    await _navigateByNotification(item);
  }

  Future<void> _navigateByNotification(CourierNotificationItem item) async {
    final orderId = (item.orderId ?? '').trim();
    final screen = (item.screen ?? '').trim().toLowerCase();
    final route = (item.route ?? '').trim().toLowerCase();
    final action = (item.action ?? '').trim().toLowerCase();
    final type = item.type.toUpperCase();

    final shouldOpenOrder = orderId.isNotEmpty &&
        (screen == 'order' ||
            route == 'orders' ||
            action == 'open_order' ||
            type.contains('ORDER'));

    if (shouldOpenOrder) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrderDetailsPage(orderId: orderId),
        ),
      );
      return;
    }

    if (screen == 'orders' || route == 'orders') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const OrdersPage(),
        ),
      );
      return;
    }

    if (screen == 'profile' || route == 'profile') {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const ProfilePage(),
        ),
      );
      return;
    }

    if (orderId.isNotEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrderDetailsPage(orderId: orderId),
        ),
      );
      return;
    }

    _showSnackBar('Уведомление открыто');
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '';

    final local = value.toLocal();
    final diff = DateTime.now().difference(local);

    if (diff.inMinutes < 1) return 'только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
    if (diff.inHours < 24) return '${diff.inHours} ч назад';

    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day.$month $hour:$minute';
  }

  IconData _iconFor(CourierNotificationItem item) {
    final type = item.type.toUpperCase();
    final screen = (item.screen ?? '').toLowerCase();

    if (type.contains('ORDER') || screen == 'order') {
      return Icons.receipt_long_rounded;
    }

    if (type.contains('CAMPAIGN') || type.contains('PROMO')) {
      return Icons.campaign_rounded;
    }

    if (screen == 'profile') {
      return Icons.person_rounded;
    }

    return Icons.notifications_rounded;
  }

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF8F8FA);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        surfaceTintColor: bg,
        elevation: 0,
        title: const Text(
          'Уведомления',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _isMarkingAll ? null : _markAllRead,
              child: _isMarkingAll
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Прочитать все',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          IconButton(
            onPressed:
                _isRefreshing || _isLoading ? null : () => _load(silent: true),
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF489F2A),
        ),
      );
    }

    if (_error.isNotEmpty && _items.isEmpty) {
      return _ErrorState(
        message: _error,
        onRetry: () => _load(),
      );
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        color: const Color(0xFF489F2A),
        onRefresh: () => _load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 140),
            _EmptyState(),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF489F2A),
      onRefresh: () => _load(silent: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = _items[index];

          return _NotificationTile(
            item: item,
            icon: _iconFor(item),
            createdAtText: _formatDate(item.createdAt),
            onTap: () => _openNotification(item),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.icon,
    required this.createdAtText,
    required this.onTap,
  });

  final CourierNotificationItem item;
  final IconData icon;
  final String createdAtText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isUnread = !item.isRead;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isUnread
                  ? const Color(0xFF489F2A)
                  : const Color(0xFFE4E8EF),
              width: isUnread ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isUnread
                      ? const Color(0xFFEAF7E7)
                      : const Color(0xFFF2F4F7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: isUnread
                      ? const Color(0xFF489F2A)
                      : const Color(0xFF667085),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isUnread ? FontWeight.w800 : FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    if (item.body.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                          color: Color(0xFF667085),
                        ),
                      ),
                    ],
                    if (createdAtText.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        createdAtText,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF98A2B3),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isUnread) ...[
                const SizedBox(width: 8),
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: const BoxDecoration(
                    color: Color(0xFF489F2A),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF98A2B3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 54,
              color: Color(0xFF489F2A),
            ),
            SizedBox(height: 18),
            Text(
              'Уведомлений пока нет',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Новые заказы и системные сообщения появятся здесь.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF667085),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: Color(0xFFD92D20),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                onRetry();
              },
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}
