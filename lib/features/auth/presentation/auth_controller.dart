import 'package:flutter/foundation.dart';
import 'package:jetkiz_courier_app/core/network/apiClient.dart';
import 'package:jetkiz_courier_app/core/storage/token_storage.dart';

import '../data/auth_api.dart';
import '../data/auth_repository.dart';
import '../domain/auth_entity.dart';
import '../domain/auth_usecase.dart';

class AuthController extends ChangeNotifier {
  AuthController() : _useCase = AuthUseCase(AuthRepository(AuthApi()));

  final AuthUseCase _useCase;

  bool isLoading = false;
  String error = '';

  Future<CourierLoginResult?> login(String phone, String password) async {
    if (isLoading) return null;

    try {
      error = '';
      isLoading = true;
      notifyListeners();

      final result = await _useCase.loginCourier(phone, password);
      final session = result.session;

      if (!result.passwordChangeRequired && session != null) {
        await TokenStorage().saveTokens(
          session.accessToken,
          session.refreshToken,
        );
      }

      return result;
    } catch (e) {
      error = _messageFor(e);
      return null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> changeTemporaryPassword({
    required String phone,
    required String currentPassword,
    required String newPassword,
  }) async {
    if (isLoading) return false;

    try {
      error = '';
      isLoading = true;
      notifyListeners();

      final session = await _useCase.changeTemporaryPassword(
        phone: phone,
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

      await TokenStorage().saveTokens(
        session.accessToken,
        session.refreshToken,
      );

      return true;
    } catch (e) {
      error = _messageFor(e);
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  String _messageFor(Object error) {
    if (error is ApiException) {
      final raw = error.message.toLowerCase();

      if (error.kind == ApiErrorKind.network) {
        return 'Нет соединения с сервером. Проверьте интернет.';
      }

      if (error.kind == ApiErrorKind.timeout) {
        return 'Сервер не ответил вовремя. Попробуйте ещё раз.';
      }

      if (error.kind == ApiErrorKind.server) {
        return 'Сервис временно недоступен. Попробуйте позже.';
      }

      if (error.statusCode == 429) {
        return 'Слишком много попыток. Подождите немного и попробуйте снова.';
      }

      if (raw.contains('временный пароль истек')) {
        return 'Временный пароль истёк. Попросите администратора выдать новый.';
      }

      if (raw.contains('заблокирован') || raw.contains('отключен')) {
        return 'Аккаунт курьера заблокирован или отключён.';
      }

      if (raw.contains('вход по паролю недоступен')) {
        return 'Вход по паролю не настроен. Обратитесь к администратору.';
      }

      if (raw.contains('пароль уже изменен')) {
        return 'Временный пароль уже был изменён. Войдите с новым паролем.';
      }

      if (raw.contains('не короче 8 символов')) {
        return 'Новый пароль должен содержать не менее 8 символов.';
      }

      if (raw.contains('слишком простой')) {
        return 'Пароль слишком простой. Придумайте более надёжный пароль.';
      }

      if (raw.contains('должен отличаться')) {
        return 'Новый пароль должен отличаться от временного.';
      }

      if (error.statusCode == 400) {
        return 'Проверьте введённые данные и попробуйте снова.';
      }

      if (error.statusCode == 401 || error.statusCode == 403) {
        return 'Неверный номер телефона или пароль.';
      }
    }

    if (error is FormatException) {
      return 'Сервер вернул некорректный ответ. Попробуйте позже.';
    }

    return 'Не удалось выполнить вход. Попробуйте ещё раз.';
  }

  @override
  void dispose() {
    _useCase.dispose();
    super.dispose();
  }
}
