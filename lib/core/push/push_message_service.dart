import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../events/courier_order_events.dart';

typedef PushIntentHandler = void Function(PushNavigationIntent intent);

const String courierOrdersChannelId = 'courier_orders_v2';
const String courierOrdersSound = 'courier_order';
const String defaultPushChannelId = 'jetkiz_default_channel';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    DartPluginRegistrant.ensureInitialized();
    await Firebase.initializeApp();
    _pushLog(
      'background message received id=${message.messageId ?? '-'} notification=${message.notification != null}',
    );

    // notification + data is rendered by Android itself while the app is in
    // background/terminated. Showing another local notification would create a
    // duplicate. A data-only courier assignment needs an explicit local one.
    if (message.notification != null) return;

    final data = _normalizePushData(message.data);
    if (!_looksLikeCourierOrder(data)) {
      _pushLog('background data-only message ignored: not a courier order');
      return;
    }

    final plugin = FlutterLocalNotificationsPlugin();
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await plugin.initialize(
      initSettings,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        courierOrdersChannelId,
        'Заказы курьера',
        description: 'Уведомления о заказах для курьера',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(courierOrdersSound),
        enableVibration: true,
      ),
    );

    final orderNumber = _readPushString(data, const ['orderNumber', 'number']);
    final title =
        _readPushString(data, const ['title', 'notificationTitle', 'pushTitle']) ??
        'Новый заказ';
    final body =
        _readPushString(data, const [
          'body',
          'notificationBody',
          'pushBody',
          'message',
        ]) ??
        (orderNumber == null
            ? 'Вам назначен новый заказ'
            : 'Вам назначен заказ №$orderNumber');

    await plugin.show(
      _stableNotificationId(message),
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          courierOrdersChannelId,
          'Заказы курьера',
          channelDescription: 'Уведомления о заказах для курьера',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(courierOrdersSound),
          enableVibration: true,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.message,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: 'courier_order.mp3',
        ),
      ),
      payload: jsonEncode(data),
    );
    _pushLog('background local courier notification displayed');
  } catch (error) {
    _pushLog('background handler failed: ${_safePushError(error)}');
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final payload = response.payload?.trim();
  if (payload == null || payload.isEmpty) return;
  unawaited(_savePendingNotificationPayload(payload));
}

Future<void> _savePendingNotificationPayload(String payload) async {
  try {
    DartPluginRegistrant.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PushMessageService.pendingIntentKey, payload);
    _pushLog('background local notification tap saved');
  } catch (error) {
    _pushLog('failed to save background notification tap: ${_safePushError(error)}');
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

  static const String defaultChannelId = defaultPushChannelId;
  static const String pendingIntentKey = 'courier_pending_notification_intent';
  static const String courierOrdersChannelId =
      ::courierOrdersChannelId;
  static const String courierOrdersSound = ::courierOrdersSound;

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
      _pushLog('message service initialized with Firebase');
    } else {
      _pushLog('message service initialized without Firebase');
    }

    _initialized = true;
  }

  void setIntentHandler(PushIntentHandler? handler) {
    _onIntent = handler;
  }

  Future<void> _initLocalNotifications() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
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
        defaultPushChannelId,
        'JETKIZ',
        description: 'Общие уведомления JETKIZ',
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
        enableVibration: true,
      ),
    );
    _pushLog('Android notification channels ensured');
  }

  Future<void> _initFirebaseListeners() async {
    if (!_firebaseAvailable) return;

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
    if (!_firebaseAvailable || firebaseMessaging == null) return;

    try {
      final message = await firebaseMessaging.getInitialMessage();
      if (message == null) return;
      _pushLog('initial notification tap received');
      _emitIntentFromRemoteMessage(message);
    } catch (error) {
      _pushLog('getInitialMessage failed: ${_safePushError(error)}');
    }
  }

  Future<void> handlePendingNotificationIntent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = prefs.getString(pendingIntentKey)?.trim();
      if (payload == null || payload.isEmpty) return;
      await prefs.remove(pendingIntentKey);
      _pushLog('pending local notification tap restored');
      _emitIntentFromPayload(payload);
    } catch (error) {
      _pushLog('pending notification intent failed: ${_safePushError(error)}');
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final data = _normalizePushData(message.data);
    _pushLog(
      'foreground message received id=${message.messageId ?? '-'} courierOrder=${_looksLikeCourierOrder(data)}',
    );
    _emitOrderEvent(data);
    await _showLocalNotification(message);
  }

  void _handleOpenedMessage(RemoteMessage message) {
    _pushLog('system notification tapped');
    _emitIntentFromRemoteMessage(message);
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final data = _normalizePushData(message.data);
    final courierOrder = _looksLikeCourierOrder(data);
    final orderNumber = _readPushString(data, const ['orderNumber', 'number']);

    final title =
        _readPushString(data, const ['title', 'notificationTitle', 'pushTitle']) ??
        message.notification?.title ??
        (courierOrder ? 'Новый заказ' : 'JETKIZ');

    final body =
        _readPushString(data, const [
          'body',
          'notificationBody',
          'pushBody',
          'message',
        ]) ??
        message.notification?.body ??
        (courierOrder
            ? (orderNumber == null
                  ? 'Вам назначен новый заказ'
                  : 'Вам назначен заказ №$orderNumber')
            : '');

    if (title.trim().isEmpty && body.trim().isEmpty) return;

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

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: courierOrder ? 'courier_order.mp3' : null,
    );

    await _localNotifications.show(
      _stableNotificationId(message),
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
    _pushLog('foreground local notification displayed channel=$channelId');
  }

  void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.trim().isEmpty) return;
    _pushLog('foreground local notification tapped');
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
    } catch (error) {
      _pushLog('notification payload decode failed: ${_safePushError(error)}');
    }
  }

  void _emitIntentFromRemoteMessage(RemoteMessage message) {
    _emitIntentFromData(_normalizePushData(message.data));
  }

  void _emitIntentFromData(Map<String, dynamic> data) {
    _emitOrderEvent(data);
    final intent = PushNavigationIntent.fromData(data);
    if (intent == null) return;
    _onIntent?.call(intent);
  }

  void _emitOrderEvent(Map<String, dynamic> data) {
    CourierOrderEvents.emitFromPush(
      data.map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      ),
    );
  }

  String _resolveChannelId(RemoteMessage message, Map<String, dynamic> data) {
    if (_looksLikeCourierOrder(data)) return courierOrdersChannelId;

    final raw =
        _readPushString(data, const [
          'channelId',
          'androidChannelId',
          'android_channel_id',
        ]) ??
        message.notification?.android?.channelId;
    final channelId = raw?.trim();

    if (channelId == courierOrdersChannelId || channelId == 'courier_orders_v1') {
      return courierOrdersChannelId;
    }
    return defaultPushChannelId;
  }

  String _channelName(String channelId) =>
      channelId == courierOrdersChannelId ? 'Заказы курьера' : 'JETKIZ';

  String _channelDescription(String channelId) =>
      channelId == courierOrdersChannelId
      ? 'Уведомления о заказах для курьера'
      : 'Общие уведомления JETKIZ';

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
    final normalized = _normalizePushData(data);
    final orderId = _readPushString(normalized, const [
      'orderId',
      'order_id',
      'orderID',
      'targetOrderId',
      'targetId',
    ]);
    final route = _readPushString(normalized, const ['route', 'targetRoute']);
    final screen = _readPushString(normalized, const ['screen', 'targetScreen']);
    final action = _readPushString(normalized, const ['action', 'tapAction']);
    final status = _readPushString(normalized, const ['status', 'orderStatus']);
    final orderNumber = _readPushInt(normalized, const ['orderNumber', 'number']);
    final type = _readPushString(normalized, const [
      'type',
      'notificationType',
    ])?.toUpperCase();

    final looksLikeOrderPush =
        orderId != null ||
        route == 'orders' ||
        route == 'order' ||
        screen == 'order' ||
        screen == 'order_details' ||
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
}

enum PushNavigationIntentType { order, ordersList, notificationsList }

Map<String, dynamic> _normalizePushData(Map data) {
  return data.map((key, value) => MapEntry(key.toString(), value));
}

String? _readPushString(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

int? _readPushInt(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value == null) continue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value.toString().trim());
    if (parsed != null) return parsed;
  }
  return null;
}

bool _looksLikeCourierOrder(Map<String, dynamic> data) {
  final app = _readPushString(data, const ['app'])?.toLowerCase();
  final type = _readPushString(data, const ['type', 'notificationType'])
      ?.toLowerCase();
  final action = _readPushString(data, const ['action', 'tapAction'])
      ?.toLowerCase();
  final screen = _readPushString(data, const ['screen', 'targetScreen'])
      ?.toLowerCase();
  final orderId = _readPushString(data, const ['orderId', 'order_id']);

  return app == 'courier' ||
      type == 'courier_order' ||
      action == 'open_order' ||
      screen == 'order_details' ||
      orderId != null;
}

int _stableNotificationId(RemoteMessage message) {
  final source =
      message.messageId ??
      message.sentTime?.millisecondsSinceEpoch.toString() ??
      DateTime.now().microsecondsSinceEpoch.toString();
  return source.hashCode & 0x7fffffff;
}

String _safePushError(Object error) {
  final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length <= 220 ? text : '${text.substring(0, 220)}…';
}

void _pushLog(String message) {
  developer.log('[PUSH] $message', name: 'jetkiz.courier.push');
}
