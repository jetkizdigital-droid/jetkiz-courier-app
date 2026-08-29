import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/localization/courier_locale.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/core/push/push_registration_service.dart';
import 'package:jetkiz_courier_app/features/finance/presentation/courier_finance_page.dart';
import 'package:jetkiz_courier_app/features/home/courier_home_page.dart';
import 'package:jetkiz_courier_app/features/orders/presentation/courier_orders_page.dart';
import 'package:jetkiz_courier_app/features/profile/presentation/courier_profile_page.dart';

class CourierShell extends StatefulWidget {
  const CourierShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<CourierShell> createState() => _CourierShellState();
}

class _CourierShellState extends State<CourierShell>
    with WidgetsBindingObserver {
  late final ApiClient _api;
  late final PushRegistrationService _pushRegistration;
  late int _currentIndex;

  CourierLocaleController get _locale => CourierLocaleController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = ApiClient();
    _pushRegistration = PushRegistrationService(apiClient: _api);
    _currentIndex = widget.initialIndex.clamp(0, 3).toInt();
    _locale.addListener(_localeChanged);
    unawaited(_startAuthenticatedSession());
  }

  Future<void> _startAuthenticatedSession() async {
    try {
      await _locale.syncAuthenticated(_api);
    } catch (_) {
      // Local language remains available if settings sync is unavailable.
    }
    try {
      await _pushRegistration.initializeAndRegister();
    } catch (error) {
      debugPrint('Courier push registration failed: ${error.runtimeType}');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // initializeAndRegister replaces its own token-refresh subscription, so
      // resume is a safe best-effort recovery without listener duplication.
      unawaited(_startAuthenticatedSession());
    }
  }

  void _localeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locale.removeListener(_localeChanged);
    unawaited(_pushRegistration.dispose());
    _api.dispose();
    super.dispose();
  }

  void _setTab(int index) {
    final next = index.clamp(0, 3).toInt();
    if (next == _currentIndex) return;
    setState(() => _currentIndex = next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          CourierHomePage(),
          CourierOrdersPage(),
          CourierFinancePage(),
          CourierProfilePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _setTab,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: _locale.t('nav.home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long_rounded),
            label: _locale.t('nav.orders'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: const Icon(Icons.account_balance_wallet_rounded),
            label: _locale.t('nav.finance'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            selectedIcon: const Icon(Icons.person_rounded),
            label: _locale.t('nav.profile'),
          ),
        ],
      ),
    );
  }
}
