import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/localization/courier_locale.dart';

import 'auth_controller.dart';
import 'auth_gate.dart';

class CourierChangePasswordPage extends StatefulWidget {
  const CourierChangePasswordPage({
    super.key,
    required this.phone,
    required this.currentPassword,
  });

  final String phone;
  final String currentPassword;

  @override
  State<CourierChangePasswordPage> createState() =>
      _CourierChangePasswordPageState();
}

class _CourierChangePasswordPageState extends State<CourierChangePasswordPage> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _repeat = TextEditingController();
  late final AuthController _controller;
  bool _obscurePassword = true;
  bool _obscureRepeat = true;

  CourierLocaleController get _locale => CourierLocaleController.instance;

  @override
  void initState() {
    super.initState();
    _controller = AuthController()..addListener(_changed);
    _locale.addListener(_changed);
  }

  @override
  void dispose() {
    _locale.removeListener(_changed);
    _controller.removeListener(_changed);
    _controller.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  bool get _canSubmit =>
      _password.text.length >= 8 &&
      _repeat.text.isNotEmpty &&
      !_controller.isLoading;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    if (_password.text != _repeat.text) {
      _show(_locale.t('auth.passwordMismatch'));
      return;
    }
    if (_password.text.length < 8) {
      _show(_locale.t('auth.passwordTooShort'));
      return;
    }

    FocusScope.of(context).unfocus();
    final success = await _controller.changeTemporaryPassword(
      phone: widget.phone,
      currentPassword: widget.currentPassword,
      newPassword: _password.text,
    );
    if (!mounted) return;

    if (!success) {
      _show(_locale.translateKnownMessage(_controller.error));
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (_) => false,
    );
  }

  void _show(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_reset_rounded, size: 58),
                  const SizedBox(height: 20),
                  Text(
                    _locale.t('auth.changePasswordTitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _locale.t('auth.changePasswordSubtitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    controller: _password,
                    obscureText: _obscurePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: _locale.t('auth.newPassword'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _repeat,
                    obscureText: _obscureRepeat,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: _locale.t('auth.repeatPassword'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _obscureRepeat = !_obscureRepeat),
                        icon: Icon(
                          _obscureRepeat
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: _canSubmit ? _submit : null,
                      child: _controller.isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _locale.t('auth.changePassword'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
