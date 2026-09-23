import 'package:flutter/foundation.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/core/storage/token_storage.dart';
import 'package:jetkiz_courier_app/features/auth/data/auth_api.dart';
import 'package:jetkiz_courier_app/features/auth/data/auth_repository.dart';
import 'package:jetkiz_courier_app/features/auth/domain/auth_usecase.dart';

class CourierAuthSmokeResult {
  const CourierAuthSmokeResult({required this.success, required this.message});

  final bool success;
  final String message;
}

Future<CourierAuthSmokeResult?> runCourierAuthSmokeIfRequested() async {
  const enabled = bool.fromEnvironment('E2E_AUTH_SMOKE');
  if (!enabled) return null;

  const phone = String.fromEnvironment('E2E_COURIER_PHONE');
  const password = String.fromEnvironment('E2E_COURIER_PASSWORD');

  if (phone.trim().isEmpty || password.isEmpty) {
    const message = 'Missing E2E courier credentials';
    debugPrint('JETKIZ_E2E_AUTH_FAILED: $message');
    return const CourierAuthSmokeResult(success: false, message: message);
  }

  final useCase = AuthUseCase(AuthRepository(AuthApi()));
  ApiClient? authenticatedApi;

  try {
    final result = await useCase.loginCourier(phone.trim(), password);

    if (result.passwordChangeRequired) {
      const message = 'Courier account requires password change';
      debugPrint('JETKIZ_E2E_AUTH_FAILED: $message');
      return const CourierAuthSmokeResult(success: false, message: message);
    }

    final session = result.session;
    if (session == null) {
      const message = 'Courier login returned no session';
      debugPrint('JETKIZ_E2E_AUTH_FAILED: $message');
      return const CourierAuthSmokeResult(success: false, message: message);
    }

    await TokenStorage().saveTokens(session.accessToken, session.refreshToken);

    authenticatedApi = ApiClient();
    await authenticatedApi.get('/auth/me');
    await authenticatedApi.get('/couriers/me');

    const message = 'Production courier login and session verification passed';
    debugPrint('JETKIZ_E2E_AUTH_OK');
    return const CourierAuthSmokeResult(success: true, message: message);
  } catch (error, stackTrace) {
    final message = '${error.runtimeType}: $error';
    debugPrint('JETKIZ_E2E_AUTH_FAILED: $message');
    if (kDebugMode) {
      debugPrintStack(stackTrace: stackTrace);
    }
    return CourierAuthSmokeResult(success: false, message: message);
  } finally {
    authenticatedApi?.dispose();
    useCase.dispose();
  }
}
