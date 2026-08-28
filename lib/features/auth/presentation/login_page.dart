import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/formatters/kazakhstan_phone.dart';
import 'package:jetkiz_courier_app/features/auth/presentation/auth_gate.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_controller.dart';
import 'change_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static final Uri _offerUri = Uri.parse('https://jetkiz.asia/offer');

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  late final AuthController _authController;

  bool _obscurePassword = true;

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
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  bool get _canSubmit {
    return normalizeKazakhstanPhone(_phoneController.text) != null &&
        _passwordController.text.isNotEmpty &&
        !_authController.isLoading;
  }

  void _onPhoneChanged(String value) {
    final formatted = formatKazakhstanPhoneInput(value);

    if (formatted != value) {
      _phoneController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    if (_authController.error.isNotEmpty) {
      _authController.error = '';
    }

    setState(() {});
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    FocusScope.of(context).unfocus();

    final phone = normalizeKazakhstanPhone(_phoneController.text);
    if (phone == null) return;

    final password = _passwordController.text;
    final result = await _authController.login(phone, password);

    if (!mounted) return;

    if (result == null) {
      _showSnackBar(
        _authController.error.isNotEmpty
            ? _authController.error
            : 'Не удалось выполнить вход.',
      );
      return;
    }

    if (result.passwordChangeRequired) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChangePasswordPage(
            phone: result.phone.isEmpty ? phone : result.phone,
            currentPassword: password,
            temporaryPasswordExpiresAt: result.temporaryPasswordExpiresAt,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  Future<void> _openOffer() async {
    final opened = await launchUrl(
      _offerUri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      _showSnackBar('Не удалось открыть пользовательское соглашение.');
    }
  }

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF3FAE2A);
    const darkGreen = Color(0xFF2E7D32);
    const subtitle = Color(0xFF667085);
    const inputBg = Color(0xFFF8F8FA);
    const inputBorder = Color(0xFFD0D5DD);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 52),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            width: 82,
                            height: 82,
                            decoration: BoxDecoration(
                              color: green,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Icon(
                              Icons.delivery_dining_rounded,
                              color: Colors.white,
                              size: 44,
                            ),
                          ),
                        ),
                        const SizedBox(height: 26),
                        const Text(
                          'Вход для курьера',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                            height: 1.12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Введите номер телефона и пароль, который выдал администратор JETKIZ.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: subtitle,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 34),
                        Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color: inputBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: inputBorder),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 16),
                              const Text(
                                '+7',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 24,
                                margin: const EdgeInsets.symmetric(horizontal: 12),
                                color: inputBorder,
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.telephoneNumber],
                                  onChanged: _onPhoneChanged,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: '(700) 000-00-00',
                                    border: InputBorder.none,
                                    isCollapsed: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _submit(),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Пароль',
                            filled: true,
                            fillColor: inputBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: inputBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: inputBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: green, width: 2),
                            ),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                        ),
                        if (_authController.error.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            _authController.error,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFDC2626),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        SizedBox(
                          height: 60,
                          child: ElevatedButton(
                            onPressed: _canSubmit ? _submit : null,
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: green,
                              disabledBackgroundColor: const Color(0xFFE5E7EB),
                              foregroundColor: Colors.white,
                              disabledForegroundColor: const Color(0xFF98A2B3),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ).copyWith(
                              backgroundColor: WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.disabled)) {
                                  return const Color(0xFFE5E7EB);
                                }
                                if (states.contains(WidgetState.pressed)) {
                                  return darkGreen;
                                }
                                return green;
                              }),
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
                                    'Войти',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Нет доступа? Обратитесь к администратору JETKIZ.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: subtitle,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'Продолжая вход, вы принимаете ',
                              style: TextStyle(
                                fontSize: 13,
                                color: subtitle,
                              ),
                            ),
                            TextButton(
                              onPressed: _openOffer,
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF2563EB),
                                padding: const EdgeInsets.symmetric(horizontal: 3),
                                minimumSize: const Size(0, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Пользовательское соглашение',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Color(0xFF2563EB),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
