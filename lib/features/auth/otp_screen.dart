import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';

import 'package:wasalny_rider/core/services/auth_service.dart';
import 'package:wasalny_rider/core/services/api_service.dart';
import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/core/utils/logger.dart';
import 'package:wasalny_rider/features/home/home_screen.dart';

class OTPScreen extends StatefulWidget {
  final String verificationId;
  final String phoneNumber;

  const OTPScreen({
    super.key,
    required this.verificationId,
    required this.phoneNumber,
  });

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  int _resendSeconds = 60;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _canResend = false;
    _resendSeconds = 60;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        _resendSeconds--;
        if (_resendSeconds <= 0) {
          _canResend = true;
        }
      });
      return _resendSeconds > 0 && mounted;
    });
  }

  Future<void> _verifyOTP() async {
    final code = _otpController.text.trim();
    if (code.length < 6) {
      setState(() => _errorMessage = 'يرجى إدخال رمز التحقق كاملاً');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Verify OTP with Firebase
      final firebaseToken = await AuthService.instance.verifyOTP(
        widget.verificationId,
        code,
      );

      if (!mounted) return;

      // 2. Exchange Firebase token for app JWT via backend
      logInfo('OTPScreen', 'Exchanging Firebase token for app JWT…');
      await ApiService.instance.signInWithFirebase(firebaseToken);

      if (!mounted) return;

      logInfo('OTPScreen', '✅ Login successful!');

      // 3. Navigate to home
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RiderHomeScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage =
            e.message ?? 'رمز التحقق غير صحيح. يرجى المحاولة مرة أخرى.';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ. يرجى المحاولة مرة أخرى.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resendCode() async {
    if (!_canResend) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await AuthService.instance.verifyPhoneNumber(
      widget.phoneNumber,
      (verificationId) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _startResendTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إعادة إرسال رمز التحقق')),
        );
      },
      (error) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = error;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final defaultPinTheme = PinTheme(
      width: 56,
      height: 56,
      textStyle: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.sms_rounded,
                    size: 40,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                Text(
                  'رمز التحقق',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'تم إرسال رمز التحقق إلى',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  widget.phoneNumber,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: AppColors.primary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xxxl),

                // OTP Input
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Pinput(
                    controller: _otpController,
                    length: 6,
                    defaultPinTheme: defaultPinTheme,
                    focusedPinTheme: defaultPinTheme.copyDecorationWith(
                      border: Border.all(color: AppColors.primary, width: 2),
                    ),
                    submittedPinTheme: defaultPinTheme.copyDecorationWith(
                      border: Border.all(color: AppColors.success),
                      color: AppColors.successContainer,
                    ),
                    onCompleted: (_) => _verifyOTP(),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                // Error message
                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.errorContainer,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.error),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Verify button
                SizedBox(
                  width: double.infinity,
                  height: AppSpacing.buttonHeightLg,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOTP,
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.textOnPrimary,
                            ),
                          )
                        : Text(
                            'تأكيد',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: AppColors.textOnPrimary),
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Resend
                TextButton(
                  onPressed: _canResend && !_isLoading ? _resendCode : null,
                  child: Text(
                    _canResend
                        ? 'إعادة إرسال الرمز'
                        : 'إعادة الإرسال بعد $_resendSeconds ثانية',
                    style: TextStyle(
                      color: _canResend
                          ? AppColors.primary
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
