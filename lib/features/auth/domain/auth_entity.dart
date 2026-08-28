class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
  });

  final String accessToken;
  final String refreshToken;
}

class CourierLoginResult {
  const CourierLoginResult._({
    required this.passwordChangeRequired,
    required this.phone,
    this.temporaryPasswordExpiresAt,
    this.session,
  });

  const CourierLoginResult.authenticated({
    required AuthSession session,
  }) : this._(
         passwordChangeRequired: false,
         phone: '',
         session: session,
       );

  const CourierLoginResult.passwordChangeRequired({
    required String phone,
    DateTime? temporaryPasswordExpiresAt,
  }) : this._(
         passwordChangeRequired: true,
         phone: phone,
         temporaryPasswordExpiresAt: temporaryPasswordExpiresAt,
       );

  final bool passwordChangeRequired;
  final String phone;
  final DateTime? temporaryPasswordExpiresAt;
  final AuthSession? session;
}
