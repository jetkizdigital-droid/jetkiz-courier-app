import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/core/push/push_registration_service.dart';
import 'package:jetkiz_courier_app/core/storage/token_storage.dart';
import 'package:jetkiz_courier_app/features/auth/presentation/login_page.dart';
import 'package:jetkiz_courier_app/features/home/home_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  static VoidCallback? onAuthenticationStarted;
  static VoidCallback? onCourierAuthenticated;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final TokenStorage _tokenStorage = TokenStorage();
  final ApiClient _api = ApiClient();

  late final PushRegistrationService _pushRegistration;

  bool _isLoading = true;
  bool _showLogin = false;
  String _error = '';

  @override
  void initState() {
    super.initState();

    AuthGate.onAuthenticationStarted?.call();

    _pushRegistration = PushRegistrationService(apiClient: _api);

    _bootstrap();
  }

  @override
  void dispose() {
    unawaited(_pushRegistration.dispose());
    _api.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _isLoading = true;
      _showLogin = false;
      _error = '';
    });

    try {
      final hasSession = await _tokenStorage.hasSession();

      if (!hasSession) {
        _openLogin();
        return;
      }

      final meRaw = await _api.get('/auth/me');
      final me = _asMap(meRaw);

      if (!_isCourierUser(me)) {
        await _tokenStorage.clear();
        _openLogin();
        return;
      }

      await _api.get('/couriers/me');

      await _registerDeviceAndPushSilently();

      if (!mounted) return;

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));

      WidgetsBinding.instance.addPostFrameCallback((_) {
        AuthGate.onCourierAuthenticated?.call();
      });
    } on ApiException catch (e) {
      if (e.isAuthenticationFailure) {
        await _tokenStorage.clear();
        _openLogin();
        return;
      }

      _showRetryableError(_messageFor(e));
    } catch (_) {
      _showRetryableError(
        'Не удалось проверить сессию. Проверьте подключение и повторите.',
      );
    }
  }

  void _showRetryableError(String message) {
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _showLogin = false;
      _error = message;
    });
  }

  String _messageFor(ApiException error) {
    switch (error.kind) {
      case ApiErrorKind.timeout:
        return 'Сервер не ответил вовремя. Попробуйте ещё раз.';
      case ApiErrorKind.network:
        return 'Нет соединения с сервером. Проверьте интернет и повторите.';
      case ApiErrorKind.server:
        return 'Сервер временно недоступен. Попробуйте ещё раз.';
      default:
        return 'Не удалось проверить сессию. Попробуйте ещё раз.';
    }
  }

  Future<void> _registerDeviceAndPushSilently() async {
    try {
      await _pushRegistration.initializeAndRegister();
    } catch (_) {
      // Не блокируем вход из-за push/device регистрации.
      // При следующем запуске AuthGate попробует снова.
    }
  }

  void _openLogin() {
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _showLogin = true;
      _error = '';
    });
  }

  bool _isCourierUser(Map<String, dynamic> me) {
    final roles = _asMap(me['roles']);

    if (_readBool(roles['isCourier'])) {
      return true;
    }

    if (me['courierProfile'] is Map) {
      return true;
    }

    final role = (me['role'] ?? '').toString().trim().toUpperCase();
    if (role == 'COURIER') {
      return true;
    }

    final capabilities = me['capabilities'];
    if (capabilities is List) {
      return capabilities
          .map((item) => item.toString().trim().toUpperCase())
          .contains('COURIER');
    }

    return false;
  }

  bool _readBool(dynamic value) {
    if (value is bool) return value;

    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    if (_showLogin) {
      return const LoginPage();
    }

    if (_error.isNotEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F8FA),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 48,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _bootstrap,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Повторить'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return const Scaffold(
      backgroundColor: Color(0xFFF8F8FA),
      body: SafeArea(child: Center(child: CircularProgressIndicator())),
    );
  }
}
