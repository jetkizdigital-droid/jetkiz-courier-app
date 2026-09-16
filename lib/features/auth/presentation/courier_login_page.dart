import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/formatters/kazakhstan_phone.dart';
import 'package:jetkiz_courier_app/core/localization/courier_locale.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_controller.dart';
import 'auth_gate.dart';
import 'courier_change_password_page.dart';

class CourierLoginPage extends StatefulWidget {
  const CourierLoginPage({super.key});

  @override
  State<CourierLoginPage> createState() => _CourierLoginPageState();
}

class _CourierLoginPageState extends State<CourierLoginPage> {
  static final Uri _offerUri = Uri.parse('https://jetkiz.asia/offer');

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  late final AuthController _controller;

  bool _obscure = true;
  bool _accepted = false;

  CourierLocaleController get _locale => CourierLocaleController.instance;

  @override
  void initState() {
    super.initState();
    _controller = AuthController()..addListener(_onAuthChanged);
    _locale.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    _locale.removeListener(_onLocaleChanged);
    _controller.removeListener(_onAuthChanged);
    _controller.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  bool get _canSubmit =>
      normalizeKazakhstanPhone(_phoneController.text) != null &&
      _passwordController.text.isNotEmpty &&
      _accepted &&
      !_controller.isLoading;

  void _onPhoneChanged(String value) {
    final formatted = formatKazakhstanPhoneInput(value);
    if (formatted != value) {
      _phoneController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    if (_controller.error.isNotEmpty) _controller.error = '';
    setState(() {});
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final phone = normalizeKazakhstanPhone(_phoneController.text);
    if (phone == null) return;

    FocusScope.of(context).unfocus();
    final password = _passwordController.text;
    final result = await _controller.login(phone, password);
    if (!mounted) return;

    if (result == null) {
      _show(_locale.translateKnownMessage(_controller.error));
      return;
    }

    if (result.passwordChangeRequired) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CourierChangePasswordPage(
            phone: result.phone.isEmpty ? phone : result.phone,
            currentPassword: password,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (_) => false,
    );
  }

  Future<void> _openOffer() async {
    final opened = await launchUrl(
      _offerUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) _show(_locale.t('auth.offerOpenFailed'));
  }

  Future<void> _setLanguage(String language) async {
    await _locale.selectBeforeLogin(language);
  }

  void _show(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF3FAE2A);
    const border = Color(0xFFD0D5DD);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'ru', label: Text('RU')),
                        ButtonSegment(value: 'kk', label: Text('ҚАЗ')),
                      ],
                      selected: {_locale.languageCode},
                      onSelectionChanged: (selection) {
                        if (selection.isNotEmpty) {
                          _setLanguage(selection.first);
                        }
                      },
                      showSelectedIcon: false,
                    ),
                  ),
                  const SizedBox(height: 34),
                  Align(
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
                  Text(
                    _locale.t('auth.title'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _locale.t('auth.subtitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F8FA),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        const Text(
                          '+7',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 24,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          color: border,
                        ),
                        Expanded(
                          child: TextField(
                            key: const Key('e2e.login.phone'),
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [
                              AutofillHints.telephoneNumber,
                            ],
                            onChanged: _onPhoneChanged,
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
                    key: const Key('e2e.login.password'),
                    controller: _passwordController,
                    obscureText: _obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: _locale.t('auth.password'),
                      filled: true,
                      fillColor: const Color(0xFFF8F8FA),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        key: const Key('e2e.login.accept'),
                        value: _accepted,
                        activeColor: green,
                        onChanged: (value) {
                          setState(() => _accepted = value == true);
                        },
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                color: Color(0xFF344054),
                                fontSize: 14,
                                height: 1.35,
                              ),
                              children: [
                                TextSpan(text: _locale.t('auth.agree')),
                                TextSpan(
                                  text: _locale.t('auth.offer'),
                                  style: const TextStyle(
                                    color: Color(0xFF175CD3),
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.underline,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = _openOffer,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      key: const Key('e2e.login.submit'),
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
                              _locale.t('auth.signIn'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
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
