import '../data/auth_repository.dart';
import 'auth_entity.dart';

class AuthUseCase {
  AuthUseCase(this.repo);

  final AuthRepository repo;

  Future<CourierLoginResult> loginCourier(String phone, String password) {
    return repo.loginCourier(phone, password);
  }

  Future<AuthSession> changeTemporaryPassword({
    required String phone,
    required String currentPassword,
    required String newPassword,
  }) {
    return repo.changeTemporaryPassword(
      phone: phone,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  void dispose() {
    repo.dispose();
  }
}
