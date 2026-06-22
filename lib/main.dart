import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:jetkiz_courier_app/core/firebase/firebase_bootstrap.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/core/push/push_message_service.dart';
import 'package:jetkiz_courier_app/features/auth/presentation/auth_gate.dart';
import 'package:jetkiz_courier_app/features/notifications/presentation/notifications_page.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/order_details_page.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/orders_page.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

late final PushMessageService pushMessageService;

PushNavigationIntent? _pendingPushIntent;
bool _courierAuthenticated = false;
bool _routingToAuthGate = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var firebaseAvailable = false;

  try {
    await Firebase.initializeApp();
    firebaseAvailable = true;
  } catch (_) {
    debugPrint('Firebase initialization failed; push is disabled.');
  }

  FirebaseBootstrap.isAvailable = firebaseAvailable;

  if (firebaseAvailable) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  pushMessageService = PushMessageService(firebaseAvailable: firebaseAvailable);

  AuthGate.onAuthenticationStarted = _handleAuthenticationStarted;
  AuthGate.onCourierAuthenticated = _handleCourierAuthenticated;

  await pushMessageService.initialize(onIntent: _handlePushIntent);

  runApp(const MyApp());
}

void _handlePushIntent(PushNavigationIntent intent) {
  _pendingPushIntent = intent;
  _openPendingPushIfReady();
}

void _handleAuthenticationStarted() {
  _courierAuthenticated = false;
}

void _handleCourierAuthenticated() {
  _courierAuthenticated = true;
  _openPendingPushIfReady();
}

void _handleSessionExpired() {
  _courierAuthenticated = false;

  final navigator = appNavigatorKey.currentState;

  if (navigator == null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleSessionExpired();
    });
    return;
  }

  if (_routingToAuthGate) return;
  _routingToAuthGate = true;

  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AuthGate()),
    (route) => false,
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    _routingToAuthGate = false;
  });
}

void _openPendingPushIfReady() {
  if (!_courierAuthenticated) return;

  final intent = _pendingPushIntent;
  final navigator = appNavigatorKey.currentState;

  if (intent == null || navigator == null) {
    return;
  }

  _pendingPushIntent = null;

  final orderId = intent.orderId?.trim();

  if (orderId != null && orderId.isNotEmpty) {
    navigator.push(
      MaterialPageRoute(builder: (_) => OrderDetailsPage(orderId: orderId)),
    );
    return;
  }

  if (intent.type == PushNavigationIntentType.ordersList) {
    navigator.push(MaterialPageRoute(builder: (_) => const OrdersPage()));
    return;
  }

  navigator.push(MaterialPageRoute(builder: (_) => const NotificationsPage()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<void>? _sessionExpiredSubscription;

  @override
  void initState() {
    super.initState();
    _sessionExpiredSubscription = ApiClient.sessionExpired.listen((_) {
      _handleSessionExpired();
    });
  }

  @override
  void dispose() {
    unawaited(_sessionExpiredSubscription?.cancel());
    unawaited(pushMessageService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(useMaterial3: true),
      home: const AuthGate(),
    );
  }
}
