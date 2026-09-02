import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/localization/courier_locale.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/core/storage/token_storage.dart';
import 'package:jetkiz_courier_app/features/navigation/presentation/courier_shell.dart';

import 'courier_login_page.dart';

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

  bool _isLoading = true;
  bool _showLogin = false;
  String? _errorKey;

  CourierLocaleController get _locale => CourierLocaleController.instance;

  @override
  void initState() {
    super.initState();
    AuthGate.onAuthenticationStarted?.call();
    _bootstrap();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _showLogin = false;
        _errorKey = null;
      });
    }

    try {
      final hasSession = await _tokenStorage.hasSession();
      if (!hasSession) {
        _openLogin();
        return;
      }

      final me = _asMap(await _api.get('/auth/me'));
      if (!_isCourierUser(me)) {
        await _tokenStorage.clear();
        _openLogin();
        return;
      }

      await _api.get('/couriers/me');
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CourierShell()),
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        AuthGate.onCourierAuthenticated?.call();
      });
    } on ApiException catch (error) {
      // Only ApiClient.sessionExpired is a definitive local-session revocation:
      // it is emitted after the refresh endpoint itself rejected the current
      // refresh token. A standalone 401 can be a request/rotation race and must
      // never erase a valid courier session.
      if (error.kind == ApiErrorKind.sessionExpired) {
        _openLogin();
        return;
      }
      _showRetryableError(_keyFor(error));
    } catch (_) {
      _showRetryableError('error.generic');
    }
  }

  String _keyFor(ApiException error) {
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

  void _showRetryableError(String key) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _showLogin = false;
      _errorKey = key;
    });
  }

  void _openLogin() {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _showLogin = true;
      _errorKey = null;
    });
  }

  bool _isCourierUser(Map<String, dynamic> me) {
    final roles = _asMap(me['roles']);
    if (_readBool(roles['isCourier'])) return true;
    if (me['courierProfile'] is Map) return true;

    final role = (me['role'] ?? '').toString().trim().toUpperCase();
    if (role == 'COURIER') return true;

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
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    if (_showLogin) return const CourierLoginPage();

    final errorKey = _errorKey;
    if (errorKey != null) {
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
                    Icons.cloud_off_rounded,
                    size: 48,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _locale.t(errorKey),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _bootstrap,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_locale.t('common.retry')),
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
