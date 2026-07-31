import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/network/api_exceptions.dart';
import 'package:wasalny_rider/core/services/api_service.dart';
import 'package:wasalny_rider/core/services/auth_service.dart';
import 'package:wasalny_rider/core/theme/app_theme.dart';

/// Google's brand red — used as the fallback icon color for the Google logo
/// (the rider theme does not define a `googleRed` color).
const Color _googleRed = Color(0xFFDB4437);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  bool _isRegisterMode = false;
  bool _obscurePassword = true;

  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

  late final AnimationController _animController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;
  late final Animation<double> _carFloat;

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
    _carFloat = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 1.0, curve: Curves.easeInOutSine),
      ),
    );
    _animController.forward();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      // 1. Sign in with Google → Firebase → Backend
      await AuthService.instance.signInWithGoogle();
      if (!mounted) return;

      // 2. Complete the shared post-auth flow (phone check → home)
      await _completePostAuth();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_mapFirebaseError(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_mapError(e));
    }
  }

  /// Validates the form and dispatches to login or register.
  void _submitForm() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isRegisterMode) {
      _register();
    } else {
      _login();
    }
  }

  /// Signs in with email + password via `POST /auth/login`.
  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      await ApiService.instance.loginWithEmailPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;
      await _completePostAuth();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_mapFirebaseError(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_mapError(e));
    }
  }

  /// Creates a new rider account via `POST /auth/register` (auto-login).
  Future<void> _register() async {
    setState(() => _isLoading = true);
    try {
      await ApiService.instance.registerWithEmailPassword(
        email: _emailController.text,
        password: _passwordController.text,
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        phoneNumber: _phoneController.text,
      );
      if (!mounted) return;
      await _completePostAuth();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_mapFirebaseError(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_mapError(e));
    }
  }

  /// Shared post-auth steps: ensure the backend profile has a real phone
  /// number (prompt if missing), then navigate straight to `/home`.
  Future<void> _completePostAuth() async {
    final profileData = await ApiService.instance.getProfile();
    final backendPhone = profileData['phoneNumber'] as String?;
    final needsPhoneEntry =
        backendPhone == null ||
        backendPhone.isEmpty ||
        backendPhone.startsWith('firebase:');

    if (mounted && needsPhoneEntry) {
      final realPhone = await _showPhoneEntryDialog();
      if (realPhone != null && realPhone.isNotEmpty && mounted) {
        await ApiService.instance.updatePhoneNumber(phoneNumber: realPhone);
      }
    }

    if (mounted) {
      // The rider has no vehicle/verification flow — go straight home
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    }
  }

  /// Maps backend / network errors to user-friendly Arabic messages.
  String _mapError(Object error) {
    if (error is ApiException) return error.message;
    if (error is DioException) {
      return ApiException.fromDioException(error).message;
    }
    return error.toString();
  }

  String _mapFirebaseError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'cancelled':
          return 'تم إلغاء تسجيل الدخول.';
        case 'account-exists-with-different-credential':
          return 'يوجد حساب آخر بنفس البريد الإلكتروني.';
        case 'invalid-credential':
          return 'فشل التحقق من بيانات جوجل. حاول مرة أخرى.';
        case 'user-disabled':
          return 'تم تعطيل حسابك. تواصل مع الدعم.';
        case 'too-many-requests':
          return 'تم تجاوز عدد المحاولات المسموح بها. حاول لاحقًا.';
        case 'network-request-failed':
          return 'تحقق من اتصال الإنترنت ثم أعد المحاولة.';
        default:
          return error.message ?? 'فشل تسجيل الدخول بحساب جوجل.';
      }
    }
    return error.toString();
  }

  /// Shows a dialog asking the user to enter their real phone number.
  /// Returns the phone number string if confirmed, or null if cancelled.
  Future<String?> _showPhoneEntryDialog() async {
    final phoneController = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('رقم الهاتف'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'يجب إدخال رقم هاتف حقيقي لإتمام التسجيل.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  hintText: '+20 1XX XXX XXXX',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final phone = phoneController.text.trim();
                if (phone.isEmpty) return;
                // Basic validation: must be a valid phone (9-15 digits)
                final clean = phone.replaceAll(RegExp(r'[\s\-]'), '');
                if (!RegExp(r'^\+?\d{9,15}$').hasMatch(clean)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('صيغة رقم الهاتف غير صحيحة'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }
                Navigator.of(context).pop(phone);
              },
              child: const Text('تأكيد'),
            ),
          ],
        );
      },
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.8,
            colors: [
              AppColors.primary.withValues(alpha: 0.08),
              AppColors.primaryBg,
              AppColors.primaryBg,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated logo
                  AnimatedBuilder(
                    animation: _carFloat,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(
                          0,
                          -8 * math.sin(_carFloat.value * math.pi * 2),
                        ),
                        child: Opacity(opacity: _fadeIn.value, child: child),
                      );
                    },
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/app_logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // Welcome title
                  FadeTransition(
                    opacity: _fadeIn,
                    child: SlideTransition(
                      position: _slideUp,
                      child: Column(
                        children: [
                          Text(
                            'أهلاً بك',
                            style: AppTextStyles.displayMedium?.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'سجل دخولك لبدء طلب الرحلات',
                            style: AppTextStyles.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.huge),

                  // Auth section: Google + email/password
                  FadeTransition(
                    opacity: _fadeIn,
                    child: SlideTransition(
                      position: _slideUp,
                      child: Column(
                        children: [
                          _buildGoogleButton(),
                          const SizedBox(height: AppSpacing.xl),

                          // Divider
                          const Row(
                            children: [
                              Expanded(child: Divider(color: AppColors.border)),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                ),
                                child: Text(
                                  'أو',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Expanded(child: Divider(color: AppColors.border)),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),

                          // Login / Register toggle
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                value: false,
                                label: Text('تسجيل الدخول'),
                                icon: Icon(Icons.login),
                              ),
                              ButtonSegment(
                                value: true,
                                label: Text('حساب جديد'),
                                icon: Icon(Icons.person_add),
                              ),
                            ],
                            selected: {_isRegisterMode},
                            onSelectionChanged: _isLoading
                                ? null
                                : (selection) => setState(
                                    () => _isRegisterMode = selection.first,
                                  ),
                            showSelectedIcon: false,
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.resolveWith((
                                states,
                              ) {
                                return states.contains(WidgetState.selected)
                                    ? AppColors.primaryContainer
                                    : AppColors.card;
                              }),
                              foregroundColor: WidgetStateProperty.resolveWith((
                                states,
                              ) {
                                return states.contains(WidgetState.selected)
                                    ? AppColors.primary
                                    : AppColors.textMuted;
                              }),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),

                          // Email / password form
                          AnimatedSize(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            child: Form(
                              key: _formKey,
                              child: Column(
                                children: [
                                  if (_isRegisterMode) ...[
                                    _buildTextField(
                                      controller: _firstNameController,
                                      label: 'الاسم الأول',
                                      icon: Icons.person_outline,
                                      validator: (v) =>
                                          (v == null || v.trim().isEmpty)
                                          ? 'أدخل الاسم الأول'
                                          : null,
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    _buildTextField(
                                      controller: _lastNameController,
                                      label: 'الاسم الأخير',
                                      icon: Icons.person_outline,
                                      validator: (v) =>
                                          (v == null || v.trim().isEmpty)
                                          ? 'أدخل الاسم الأخير'
                                          : null,
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                  ],
                                  _buildTextField(
                                    controller: _emailController,
                                    label: 'البريد الإلكتروني',
                                    icon: Icons.email_outlined,
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'أدخل البريد الإلكتروني';
                                      }
                                      final email = v.trim();
                                      final valid = RegExp(
                                        r'^[\w\.\-+]+@[\w\-]+(\.[\w\-]+)+$',
                                      ).hasMatch(email);
                                      return valid
                                          ? null
                                          : 'صيغة البريد الإلكتروني غير صحيحة';
                                    },
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  _buildTextField(
                                    controller: _passwordController,
                                    label: 'كلمة المرور',
                                    icon: Icons.lock_outline,
                                    obscure: !_obscurePassword,
                                    suffix: IconButton(
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                    validator: (v) =>
                                        (v == null || v.length < 6)
                                        ? 'كلمة المرور 6 أحرف على الأقل'
                                        : null,
                                  ),
                                  if (_isRegisterMode) ...[
                                    const SizedBox(height: AppSpacing.md),
                                    _buildTextField(
                                      controller: _phoneController,
                                      label: 'رقم الهاتف (اختياري)',
                                      icon: Icons.phone_outlined,
                                      keyboardType: TextInputType.phone,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),

                          // Submit button
                          _buildSubmitButton(),
                          const SizedBox(height: AppSpacing.xxl),

                          // Terms
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.card.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusMd,
                              ),
                            ),
                            child: Text(
                              'بالمتابعة، أنت توافق على شروط الخدمة وسياسة الخصوصية',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.labelSmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
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

  /// Google "G" logo widget with fallback icon.
  static Widget _googleLogo({double size = 24}) {
    return Image.network(
      'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
      width: size,
      height: size,
      errorBuilder: (_, _, _) =>
          Icon(Icons.g_mobiledata, size: size + 4, color: _googleRed),
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      width: double.infinity,
      height: AppSpacing.buttonHeightLg,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _signInWithGoogle,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _isLoading
              ? const SizedBox(
                  key: ValueKey('loading'),
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.primary,
                  ),
                )
              : _googleLogo(),
        ),
        label: Text(
          'تسجيل الدخول باستخدام Google',
          style: AppTextStyles.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 2,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            side: BorderSide(color: Colors.grey.shade300),
          ),
        ),
      ),
    );
  }

  /// Reusable styled input field for the login / register form.
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.textMuted),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }

  /// Primary submit button (login / register).
  Widget _buildSubmitButton() {
    final isRegister = _isRegisterMode;
    return SizedBox(
      width: double.infinity,
      height: AppSpacing.buttonHeightLg,
      child: FilledButton.icon(
        onPressed: _isLoading ? null : _submitForm,
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.textOnPrimary,
                ),
              )
            : Icon(isRegister ? Icons.person_add_alt_1 : Icons.login),
        label: Text(
          isRegister ? 'إنشاء حساب' : 'تسجيل الدخول',
          style: AppTextStyles.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
        ),
      ),
    );
  }
}
