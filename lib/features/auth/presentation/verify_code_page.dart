import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jetkiz_courier_app/core/push/push_registration_service.dart';

import 'auth_controller.dart';
import 'auth_gate.dart';

class VerifyCodePage extends StatefulWidget {
  const VerifyCodePage({
    super.key,
    required this.phone,
  });

  final String phone;

  @override
  State<VerifyCodePage> createState() => _VerifyCodePageState();
}

class _VerifyCodePageState extends State<VerifyCodePage> {
  final List<TextEditingController> _controllers =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());

  late final AuthController _authController;
  late final PushRegistrationService _pushRegistration;

  String _error = '';

  bool get _canSubmit =>
      _controllers.every((controller) => controller.text.trim().length == 1) &&
      !_authController.isLoading;

  String get _code => _controllers.map((e) => e.text).join();

  @override
  void initState() {
    super.initState();

    _authController = AuthController();
    _authController.addListener(_onControllerChanged);

    _pushRegistration = PushRegistrationService();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNodes.first.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _authController.removeListener(_onControllerChanged);
    _authController.dispose();

    unawaited(_pushRegistration.dispose());

    for (final controller in _controllers) {
      controller.dispose();
    }

    for (final node in _focusNodes) {
      node.dispose();
    }

    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _error = '';
    });

    final ok = await _authController.verifyCode(widget.phone, _code);

    if (!mounted) return;

    if (ok) {
      await _registerDeviceAndPushSilently();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
      return;
    }

    setState(() {
      _error = _authController.error.isNotEmpty
          ? _authController.error
          : 'Неверный код';
    });
  }

  Future<void> _registerDeviceAndPushSilently() async {
    try {
      await _pushRegistration.initializeAndRegister();
    } catch (_) {
      // Не блокируем вход из-за регистрации push/device.
      // AuthGate после входа попробует регистрацию повторно.
    }
  }

  Future<void> _resend() async {
    for (final controller in _controllers) {
      controller.clear();
    }

    setState(() {
      _error = '';
    });

    _focusNodes.first.requestFocus();

    final ok = await _authController.requestCode(widget.phone);

    if (!mounted) return;

    if (!ok) {
      final message = _authController.error.isNotEmpty
          ? _authController.error
          : 'Не удалось отправить код повторно';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  void _onChanged(String value, int index) {
    if (value.length > 1) {
      final last = value[value.length - 1];
      _controllers[index].text = last;
      _controllers[index].selection = const TextSelection.collapsed(offset: 1);
    }

    if (_error.isNotEmpty) {
      setState(() {
        _error = '';
      });
    } else {
      setState(() {});
    }

    if (_controllers[index].text.isNotEmpty) {
      if (index < _focusNodes.length - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    }

    if (_controllers.every((controller) => controller.text.length == 1)) {
      _submit();
    }
  }

  void _onBackspace(int index) {
    if (_controllers[index].text.isNotEmpty) {
      _controllers[index].clear();
      setState(() {
        _error = '';
      });
      return;
    }

    if (index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();

      setState(() {
        _error = '';
      });
    }
  }

  Widget _buildOtpCell(int index) {
    const green = Color(0xFF3FAE2A);
    const border = Color(0xFFE7E7EC);
    const error = Color(0xFFDC2626);

    final hasError = _error.isNotEmpty;

    return SizedBox(
      width: 52,
      height: 64,
      child: Focus(
        onKeyEvent: (_, event) {
          if (event.logicalKey.keyLabel.toLowerCase() == 'backspace') {
            _onBackspace(index);
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          textInputAction: index == _controllers.length - 1
              ? TextInputAction.done
              : TextInputAction.next,
          maxLength: 1,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: Colors.white,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: hasError ? error : border,
                width: 2,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: hasError ? error : border,
                width: 2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: hasError ? error : green,
                width: 2,
              ),
            ),
          ),
          onChanged: (value) => _onChanged(value, index),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF3FAE2A);
    const darkGreen = Color(0xFF2E7D32);
    const subtitle = Color(0xFF8E8E93);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    size: 28,
                    color: Colors.black,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Введите код',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Код отправлен на ${widget.phone}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: subtitle,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 48),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildOtpCell(0),
                            const SizedBox(width: 12),
                            _buildOtpCell(1),
                            const SizedBox(width: 12),
                            _buildOtpCell(2),
                            const SizedBox(width: 12),
                            _buildOtpCell(3),
                          ],
                        ),
                        const SizedBox(height: 24),
                        if (_error.isNotEmpty)
                          Text(
                            _error,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 60,
                          child: ElevatedButton(
                            onPressed: _canSubmit ? _submit : null,
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: green,
                              disabledBackgroundColor: const Color(0xFFE5E5E5),
                              foregroundColor: Colors.white,
                              disabledForegroundColor: Colors.black45,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ).copyWith(
                              backgroundColor:
                                  WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.disabled)) {
                                  return const Color(0xFFE5E5E5);
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
                                    'Подтвердить',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextButton(
                          onPressed: _authController.isLoading ? null : _resend,
                          child: const Text(
                            'Отправить код повторно',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: green,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}