import 'package:flutter/material.dart';

import '../core/keypad_input.dart';
import '../core/phone.dart';
import '../firebase/auth_service.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/keypad.dart';

/// Phone OTP sign-in with the on-screen keypad (principle 4: no text keyboard).
/// On success the auth stream changes and the app moves on by itself.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _phone = '';
  String _code = '';
  OtpRequest? _request;
  bool _busy = false;
  String? _error;

  bool get _codeStage => _request != null;

  void _onKey(String k) {
    setState(() {
      _error = null;
      if (_codeStage) {
        _code = applyKey(_code, k, maxDigits: 6, leadingZeros: true);
      } else {
        _phone = applyKey(_phone, k, maxDigits: 10, leadingZeros: true);
      }
    });
  }

  Future<void> _send() async {
    if (!isNepalMobile(_phone)) {
      setState(() => _error = '९८ वा ९७ बाट सुरु हुने १० अङ्कको नम्बर लेख्नुस्');
      return;
    }
    await _run(() async {
      final req = await widget.auth.sendCode(toE164Nepal(_phone));
      if (mounted && !req.autoVerified) setState(() => _request = req);
    });
  }

  Future<void> _confirm() async {
    if (_code.length != 6) {
      setState(() => _error = '६ अङ्कको कोड लेख्नुस्');
      return;
    }
    await _run(() => widget.auth.confirmCode(_request!, _code));
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.messageNe);
    } catch (_) {
      if (mounted) setState(() => _error = 'लगइन हुन सकेन, फेरि प्रयास गर्नुस्');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _codeStage
        ? List.generate(6, (i) => i < _code.length ? _code[i] : '•').join(' ')
        : (_phone.isEmpty ? '98XXX XXXXX' : formatNepalMobile(_phone));
    final empty = _codeStage ? _code.isEmpty : _phone.isEmpty;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset('assets/brand/bhunte-logo.png', width: 52, height: 52),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'भुन्टे',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: BColors.green),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                _codeStage ? 'SMS मा आएको कोड लेख्नुस्' : 'तपाईंको मोबाइल नम्बर',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              Text(
                _codeStage ? '+977 ${formatNepalMobile(_phone)} मा पठाइयो' : 'यसमा ६ अङ्कको कोड आउँछ',
                style: const TextStyle(fontSize: 16, color: BColors.inkSoft),
              ),
              const SizedBox(height: 14),
              Container(
                height: 72,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: BColors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: BColors.line),
                ),
                child: Row(
                  children: [
                    if (!_codeStage)
                      const Text(
                        '+977 ',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: BColors.inkSoft),
                      ),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          shown,
                          key: const ValueKey('login-entry'),
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: empty ? BColors.disabled : BColors.ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: const TextStyle(fontSize: 16, color: BColors.warnInk, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Keypad(keyHeight: 60, bottomRow: const [Keys.backspace, '0', ''], onKey: _onKey),
              const SizedBox(height: 14),
              BigButton(
                label: _busy ? 'पर्खनुस्…' : (_codeStage ? 'लगइन गर्नुस्' : 'कोड पठाउनुस्'),
                trailingIcon: _busy ? null : Icons.arrow_forward_rounded,
                height: 68,
                color: _busy ? BColors.disabled : BColors.green,
                onPressed: _busy ? null : (_codeStage ? _confirm : _send),
              ),
              if (_codeStage) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _request = null;
                                _code = '';
                                _error = null;
                              }),
                        child: const Text('नम्बर बदल्नुस्', style: TextStyle(fontSize: 17)),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: _busy ? null : _send,
                        child: const Text('कोड फेरि पठाउनुस्', style: TextStyle(fontSize: 17)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
