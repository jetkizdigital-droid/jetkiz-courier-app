import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:jetkiz_courier_app/core/firebase/firebase_bootstrap.dart';
import 'package:jetkiz_courier_app/core/localization/courier_locale.dart';
import 'package:jetkiz_courier_app/core/location/courier_location_service.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/core/push/push_message_service.dart';
import 'package:jetkiz_courier_app/features/auth/presentation/auth_gate.dart';
import 'package:jetkiz_courier_app/features/navigation/presentation/courier_shell.dart';
import 'package:jetkiz_courier_app/features/notifications/presentation/courier_notifications_page.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/courier_order_details_page.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
late final PushMessageService pushMessageService;

PushNavigationIntent? _pendingPushIntent;
bool _courierAuthenticated = false;
bool _routingToAuthGate = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CourierLocaleController.instance.load();

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
  unawaited(CourierLocationService().stopTracking());

  final navigator = appNavigatorKey.currentState;
  if (navigator == null) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _handleSessionExpired(),
    );
    return;
  }
  if (_routingToAuthGate) return;
  _routingToAuthGate = true;
  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AuthGate()),
    (_) => false,
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _routingToAuthGate = false;
  });
}

void _openPendingPushIfReady() {
  if (!_courierAuthenticated) return;
  final intent = _pendingPushIntent;
  final navigator = appNavigatorKey.currentState;
  if (intent == null || navigator == null) return;

  _pendingPushIntent = null;
  final orderId = intent.orderId?.trim();
  if (orderId != null && orderId.isNotEmpty) {
    navigator.push(
      MaterialPageRoute(
        builder: (_) => CourierOrderDetailsPage(orderId: orderId),
      ),
    );
    return;
  }
  if (intent.type == PushNavigationIntentType.ordersList) {
    navigator.push(
      MaterialPageRoute(builder: (_) => const CourierShell(initialIndex: 1)),
    );
    return;
  }
  navigator.push(
    MaterialPageRoute(builder: (_) => const CourierNotificationsPage()),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<void>? _sessionExpiredSubscription;

  CourierLocaleController get _locale => CourierLocaleController.instance;

  @override
  void initState() {
    super.initState();
    _locale.addListener(_localeChanged);
    _sessionExpiredSubscription = ApiClient.sessionExpired.listen((_) {
      _handleSessionExpired();
    });
  }

  void _localeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _locale.removeListener(_localeChanged);
    unawaited(_sessionExpiredSubscription?.cancel());
    unawaited(pushMessageService.dispose());
    unawaited(CourierLocationService().shutdown());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF3FAE2A);
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      locale: _locale.locale,
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: green),
        scaffoldBackgroundColor: const Color(0xFFF8F8FA),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.white,
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}
