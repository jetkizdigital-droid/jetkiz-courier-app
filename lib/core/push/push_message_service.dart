import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../events/courier_order_events.dart';

typedef PushIntentHandler = void Function(PushNavigationIntent intent);

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase мог уже быть initialized.
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final payload = response.payload?.trim();

  if (payload == null || payload.isEmpty) {
    return;
  }

  unawaited(_savePendingNotificationPayload(payload));
}

Future<void> _savePendingNotificationPayload(String payload) async {
  try {
    DartPluginRegistrant.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PushMessageService.pendingIntentKey, payload);
  } catch (_) {
    // Background isolate must never crash the app because of a bad tap payload.
  }
}

class PushMessageService {
  PushMessageService({
    FirebaseMessaging? firebaseMessaging,
    FlutterLocalNotificationsPlugin? localNotifications,
    bool firebaseAvailable = true,
  }) : _firebaseMessaging = firebaseAvailable
           ? firebaseMessaging ?? FirebaseMessaging.instance
           : null,
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin(),
       _firebaseAvailable = firebaseAvailable;

  static const String defaultChannelId = 'jetkiz_default_channel';
  static const String pendingIntentKey = 'courier_pending_notification_intent';

  // Новый канал нужен, потому что Android почти не меняет звук уже созданного канала.
  static const String courierOrdersChannelId = 'courier_orders_v2';

  // Файл должен лежать тут:
  // android/app/src/main/res/raw/courier_order.mp3
  // В коде указываем имя БЕЗ расширения.
  static const String courierOrdersSound = 'courier_order';

  final FirebaseMessaging? _firebaseMessaging;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final bool _firebaseAvailable;

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;

  PushIntentHandler? _onIntent;
  bool _initialized = false;
  String? _lastHandledPayload;

  Future<void> initialize({PushIntentHandler? onIntent}) async {
    _onIntent = onIntent;

    if (_initialized) {
      await handleInitialMessage();
      return;
    }

    await _initLocalNotifications();
    await handlePendingNotificationIntent();

    if (_firebaseAvailable) {
      await _initFirebaseListeners();
      await handleInitialMessage();
    }

    _initialized = true;
  }

  void setIntentHandler(PushIntentHandler? handler) {
    _onIntent = handler;
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        defaultChannelId,
        'Jetkiz',
        description: 'Общие уведомления Jetkiz',
        importance: Importance.high,
        playSound: true,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        courierOrdersChannelId,
        'Заказы курьера',
        description: 'Уведомления о заказах для курьера',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(courierOrdersSound),
      ),
    );
  }

  Future<void> _initFirebaseListeners() async {
    if (!_firebaseAvailable) {
      return;
    }

    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();

    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );

    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleOpenedMessage,
    );
  }

  Future<void> handleInitialMessage() async {
    final firebaseMessaging = _firebaseMessaging;

    if (!_firebaseAvailable || firebaseMessaging == null) {
      return;
    }

    try {
      final message = await firebaseMessaging.getInitialMessage();

      if (message == null) {
        return;
      }

      _emitIntentFromRemoteMessage(message);
    } catch (_) {
      // Не валим запуск приложения из-за push intent.
    }
  }

  Future<void> handlePendingNotificationIntent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = prefs.getString(pendingIntentKey)?.trim();

      if (payload == null || payload.isEmpty) {
        return;
      }

      await prefs.remove(pendingIntentKey);
      _emitIntentFromPayload(payload);
    } catch (_) {
      // Pending local notification intent is best-effort.
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    _emitOrderEvent(_normalizeData(message.data));
    await _showLocalNotification(message);
  }

  void _handleOpenedMessage(RemoteMessage message) {
    _emitIntentFromRemoteMessage(message);
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final data = _normalizeData(message.data);

    final title =
        _readString(data, const ['title', 'notificationTitle', 'pushTitle']) ??
        message.notification?.title ??
        'Jetkiz';

    final body =
        _readString(data, const [
          'body',
          'notificationBody',
          'pushBody',
          'message',
        ]) ??
        message.notification?.body ??
        '';

    if (title.trim().isEmpty && body.trim().isEmpty) {
      return;
    }

    final channelId = _resolveChannelId(message, data);
    final payload = jsonEncode(data);

    final androidDetails = AndroidNotificationDetails(
      channelId,
      _channelName(channelId),
      channelDescription: _channelDescription(channelId),
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: channelId == courierOrdersChannelId
          ? const RawResourceAndroidNotificationSound(courierOrdersSound)
          : null,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.message,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      _notificationId(message),
      title,
      body,
      details,
      payload: payload,
    );
  }

  void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;

    if (payload == null || payload.trim().isEmpty) {
      return;
    }

    _emitIntentFromPayload(payload);
  }

  void _emitIntentFromPayload(String payload) {
    final normalizedPayload = payload.trim();

    if (normalizedPayload.isEmpty || normalizedPayload == _lastHandledPayload) {
      return;
    }

    try {
      final decoded = jsonDecode(normalizedPayload);

      if (decoded is Map<String, dynamic>) {
        _lastHandledPayload = normalizedPayload;
        _emitIntentFromData(decoded);
        return;
      }

      if (decoded is Map) {
        _lastHandledPayload = normalizedPayload;
        _emitIntentFromData(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Ignore broken payloads safely.
    }
  }

  void _emitIntentFromRemoteMessage(RemoteMessage message) {
    final data = _normalizeData(message.data);
    _emitIntentFromData(data);
  }

  void _emitIntentFromData(Map<String, dynamic> data) {
    _emitOrderEvent(data);

    final intent = PushNavigationIntent.fromData(data);

    if (intent == null) {
      return;
    }

    _onIntent?.call(intent);
  }

  void _emitOrderEvent(Map<String, dynamic> data) {
    CourierOrderEvents.emitFromPush(
      data.map((key, value) => MapEntry(key.toString(), value?.toString() ?? '')),
    );
  }

  String _resolveChannelId(RemoteMessage message, Map<String, dynamic> data) {
    final raw =
        _readString(data, const [
          'channelId',
          'androidChannelId',
          'android_channel_id',
        ]) ??
        message.notification?.android?.channelId;

    final channelId = raw?.trim();

    if (channelId == courierOrdersChannelId) {
      return courierOrdersChannelId;
    }

    // Backward compatibility: если backend ещё отправит старый канал,
    // foreground local notification всё равно покажем через новый канал со звуком.
    if (channelId == 'courier_orders_v1') {
      return courierOrdersChannelId;
    }

    return defaultChannelId;
  }

  String _channelName(String channelId) {
    if (channelId == courierOrdersChannelId) {
      return 'Заказы курьера';
    }

    return 'Jetkiz';
  }

  String _channelDescription(String channelId) {
    if (channelId == courierOrdersChannelId) {
      return 'Уведомления о заказах для курьера';
    }

    return 'Общие уведомления Jetkiz';
  }

  int _notificationId(RemoteMessage message) {
    final source =
        message.messageId ??
        message.sentTime?.millisecondsSinceEpoch.toString() ??
        DateTime.now().microsecondsSinceEpoch.toString();

    return source.hashCode & 0x7fffffff;
  }

  Map<String, dynamic> _normalizeData(Map<String, dynamic> data) {
    return data.map((key, value) => MapEntry(key.toString(), value));
  }

  String? _readString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];

      if (value == null) {
        continue;
      }

      final text = value.toString().trim();

      if (text.isNotEmpty) {
        return text;
      }
    }

    return null;
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();

    _foregroundSubscription = null;
    _openedSubscription = null;
    _onIntent = null;
    _initialized = false;
  }
}

class PushNavigationIntent {
  const PushNavigationIntent({
    required this.type,
    required this.raw,
    this.orderId,
    this.orderNumber,
    this.status,
    this.route,
    this.screen,
    this.action,
  });

  final PushNavigationIntentType type;
  final Map<String, dynamic> raw;

  final String? orderId;
  final int? orderNumber;
  final String? status;
  final String? route;
  final String? screen;
  final String? action;

  bool get hasOrder => orderId != null && orderId!.trim().isNotEmpty;

  factory PushNavigationIntent.order({
    required String orderId,
    required Map<String, dynamic> raw,
    int? orderNumber,
    String? status,
    String? route,
    String? screen,
    String? action,
  }) {
    return PushNavigationIntent(
      type: PushNavigationIntentType.order,
      raw: raw,
      orderId: orderId,
      orderNumber: orderNumber,
      status: status,
      route: route,
      screen: screen,
      action: action,
    );
  }

  static PushNavigationIntent? fromData(Map<String, dynamic> data) {
    final normalized = _normalizeKeys(data);

    final orderId = _readString(normalized, const [
      'orderId',
      'order_id',
      'orderID',
      'targetOrderId',
      'targetId',
    ]);

    final route = _readString(normalized, const ['route', 'targetRoute']);

    final screen = _readString(normalized, const ['screen', 'targetScreen']);

    final action = _readString(normalized, const ['action', 'tapAction']);

    final status = _readString(normalized, const ['status', 'orderStatus']);

    final orderNumber = _readInt(normalized, const ['orderNumber', 'number']);

    final type = _readString(normalized, const [
      'type',
      'notificationType',
    ])?.toUpperCase();

    final looksLikeOrderPush =
        orderId != null ||
        route == 'orders' ||
        route == 'order' ||
        screen == 'order' ||
        action == 'open_order' ||
        (type != null && type.contains('ORDER'));

    if (!looksLikeOrderPush) {
      return PushNavigationIntent(
        type: PushNavigationIntentType.notificationsList,
        raw: normalized,
        route: route,
        screen: screen,
        action: action,
      );
    }

    if (orderId == null || orderId.trim().isEmpty) {
      return PushNavigationIntent(
        type: PushNavigationIntentType.ordersList,
        raw: normalized,
        orderNumber: orderNumber,
        status: status,
        route: route,
        screen: screen,
        action: action,
      );
    }

    return PushNavigationIntent.order(
      orderId: orderId,
      raw: normalized,
      orderNumber: orderNumber,
      status: status,
      route: route,
      screen: screen,
      action: action,
    );
  }

  static Map<String, dynamic> _normalizeKeys(Map<String, dynamic> data) {
    return data.map((key, value) => MapEntry(key.toString(), value));
  }

  static String? _readString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];

      if (value == null) {
        continue;
      }

      final text = value.toString().trim();

      if (text.isNotEmpty) {
        return text;
      }
    }

    return null;
  }

  static int? _readInt(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];

      if (value == null) {
        continue;
      }

      if (value is int) {
        return value;
      }

      if (value is num) {
        return value.toInt();
      }

      final parsed = int.tryParse(value.toString().trim());

      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }
}

enum PushNavigationIntentType { order, ordersList, notificationsList }
