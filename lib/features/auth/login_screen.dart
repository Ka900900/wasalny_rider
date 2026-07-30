import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/services/auth_service.dart';
import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/features/auth/otp_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;

  late final AnimationController _animController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _animController,
            curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
          ),
        );
    _animController.forward();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _sendOTP() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Normalize phone number: ensure it starts with +
    String phone = _phoneController.text.trim();
    if (!phone.startsWith('+')) {
      phone = '+2$phone'; // Default to Egypt country code
    }

    await AuthService.instance.verifyPhoneNumber(
      phone,
      // onCodeSent
      (verificationId) {
        if (!mounted) return;
        setState(() => _isLoading = false);

        // Navigate to OTP screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                OTPScreen(verificationId: verificationId, phoneNumber: phone),
          ),
        );
      },
      // onError
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
    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: FadeTransition(
              opacity: _fadeIn,
              child: SlideTransition(
                position: _slideUp,
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Icon(
                        Icons.directions_car_rounded,
                        size: 80,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      Text(
                        'Waslny',
                        style: Theme.of(context).textTheme.displayMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Rider',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.textSecondary,
                          letterSpacing: 2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xxxl),
                      Text(
                        'تسجيل الدخول',
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'أدخل رقم هاتفك لاستلام رمز التحقق',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xxxl),

                      // Phone input
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.left,
                        decoration: InputDecoration(
                          labelText: 'رقم الهاتف',
                          hintText: '01012345678',
                          prefixIcon: const Icon(Icons.phone_android_rounded),
                          prefix: const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Text(
                              '+2',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'يرجى إدخال رقم الهاتف';
                          }
                          // Basic validation: at least 10 digits
                          final digits = value.trim().replaceAll(
                            RegExp(r'\D'),
                            '',
                          );
                          if (digits.length < 10) {
                            return 'رقم الهاتف يجب أن يتكون من 10 أرقام على الأقل';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Error message
                      if (_errorMessage != null)
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.errorContainer,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: AppColors.error,
                                size: 20,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.error),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_errorMessage != null)
                        const SizedBox(height: AppSpacing.lg),

                      // Send OTP button
                      SizedBox(
                        width: double.infinity,
                        height: AppSpacing.buttonHeightLg,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _sendOTP,
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
                                  'إرسال رمز التحقق',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: AppColors.textOnPrimary,
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
        ),
      ),
    );
  }
}
