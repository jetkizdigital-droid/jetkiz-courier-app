import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/features/auth/presentation/auth_gate.dart';

import 'auth_controller.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({
    super.key,
    required this.phone,
    required this.currentPassword,
    this.temporaryPasswordExpiresAt,
  });

  final String phone;
  final String currentPassword;
  final DateTime? temporaryPasswordExpiresAt;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  late final AuthController _authController;
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String _localError = '';

  @override
  void initState() {
    super.initState();
    _authController = AuthController();
    _authController.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _authController.removeListener(_onControllerChanged);
    _authController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  bool get _canSubmit {
    return _passwordController.text.length >= 8 &&
        _confirmController.text.isNotEmpty &&
        !_authController.isLoading;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final password = _passwordController.text;
    final confirmation = _confirmController.text;

    if (password != confirmation) {
      setState(() {
        _localError = 'Пароли не совпадают.';
      });
      return;
    }

    if (password == widget.currentPassword) {
      setState(() {
        _localError = 'Новый пароль должен отличаться от временного.';
      });
      return;
    }

    setState(() {
      _localError = '';
    });

    final ok = await _authController.changeTemporaryPassword(
      phone: widget.phone,
      currentPassword: widget.currentPassword,
      newPassword: password,
    );

    if (!mounted) return;

    if (!ok) {
      setState(() {
        _localError = _authController.error;
      });
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF3FAE2A);
    const subtitle = Color(0xFF667085);
    const border = Color(0xFFD0D5DD);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Новый пароль',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF7E7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.lock_reset_rounded,
                      color: green,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Смените временный пароль',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Администратор выдал временный пароль. Перед началом работы установите свой пароль — не короче 8 символов.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                      color: subtitle,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _PasswordField(
                    controller: _passwordController,
                    label: 'Новый пароль',
                    obscure: _obscurePassword,
                    onToggleVisibility: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                    onChanged: (_) {
                      if (_localError.isNotEmpty) {
                        setState(() => _localError = '');
                      } else {
                        setState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  _PasswordField(
                    controller: _confirmController,
                    label: 'Повторите пароль',
                    obscure: _obscureConfirm,
                    onToggleVisibility: () {
                      setState(() {
                        _obscureConfirm = !_obscureConfirm;
                      });
                    },
                    onChanged: (_) {
                      if (_localError.isNotEmpty) {
                        setState(() => _localError = '');
                      } else {
                        setState(() {});
                      }
                    },
                  ),
                  if (_localError.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      _localError,
                      style: const TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 58,
                    child: ElevatedButton(
                      onPressed: _canSubmit ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: green,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFE5E7EB),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _authController.isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Сохранить и войти',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Если временный пароль истёк, попросите администратора JETKIZ выдать новый.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: subtitle,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(height: 1, color: border),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscure,
    required this.onToggleVisibility,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggleVisibility;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      onChanged: onChanged,
      onSubmitted: (_) {},
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: Colors.black,
      ),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF8F8FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF3FAE2A), width: 2),
        ),
        suffixIcon: IconButton(
          onPressed: onToggleVisibility,
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          ),
        ),
      ),
    );
  }
}
