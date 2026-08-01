import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/network/api_exceptions.dart';
import 'package:wasalny_rider/core/services/api_service.dart';
import 'package:wasalny_rider/core/theme/app_theme.dart';

/// شاشة «نسيت كلمة المرور؟»
///
/// - يكتب المستخدم بريده الإلكتروني.
/// - نطلب رمز إعادة التعيين عبر `POST /auth/forgot-password`.
/// - عند النجاح تظهر رسالة تأكيد (ومعها رمز التطوير إن وُجد) ثم ننتقل إلى
///   شاشة تعيين كلمة مرور جديدة `ResetPasswordScreen`.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  bool _isLoading = false;
  bool _emailSent = false;
  String? _devCode;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);
    try {
      final result = await ApiService.instance.forgotPassword(
        email: _emailController.text,
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _emailSent = true;
        // في بيئة التطوير فقط يعيد الخادم الكود ليظهر للمستخدم.
        final code = result['devCode'];
        _devCode = code is String && code.isNotEmpty ? code : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_mapError(e));
    }
  }

  /// الانتقال إلى شاشة تعيين كلمة المرور الجديدة.
  void _goToResetPassword() {
    Navigator.pushNamed(
      context,
      '/reset-password',
      arguments: _emailController.text.trim(),
    );
  }

  /// العودة إلى شاشة تسجيل الدخول.
  void _goToLogin() {
    Navigator.pop(context);
  }

  String _mapError(Object error) {
    if (error is ApiException) return error.message;
    if (error is DioException) {
      return ApiException.fromDioException(error).message;
    }
    return error.toString();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      appBar: AppBar(
        title: const Text('استعادة كلمة المرور'),
        backgroundColor: AppColors.primaryBg,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxl,
            vertical: AppSpacing.xl,
          ),
          child: _emailSent ? _buildSuccessView() : _buildRequestView(),
        ),
      ),
    );
  }

  // ── عرض إدخال البريد الإلكتروني ───────────────────────────
  Widget _buildRequestView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Icon(Icons.lock_reset, color: AppColors.primary, size: 64),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'نسيت كلمة المرور؟',
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'أدخل بريدك الإلكتروني وسنرسل لك رمزاً لإعادة تعيين كلمة المرور.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.huge),

        Form(
          key: _formKey,
          child: TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            style: const TextStyle(color: AppColors.textPrimary),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'أدخل البريد الإلكتروني';
              }
              final email = v.trim();
              final valid = RegExp(
                r'^[\w\.\-+]+@[\w\-]+(\.[\w\-]+)+$',
              ).hasMatch(email);
              return valid ? null : 'صيغة البريد الإلكتروني غير صحيحة';
            },
            decoration: InputDecoration(
              labelText: 'البريد الإلكتروني',
              prefixIcon: Icon(
                Icons.email_outlined,
                color: AppColors.textMuted,
              ),
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
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),

        // زر إرسال الرمز
        SizedBox(
          height: AppSpacing.buttonHeightLg,
          child: FilledButton.icon(
            onPressed: _isLoading ? null : _submit,
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.textOnPrimary,
                    ),
                  )
                : const Icon(Icons.send),
            label: Text(
              'إرسال الرمز',
              style: AppTextStyles.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // رجوع لتسجيل الدخول
        TextButton(
          onPressed: _isLoading ? null : _goToLogin,
          child: Text(
            'تذكرت كلمة المرور؟ سجّل الدخول',
            style: AppTextStyles.bodyMedium?.copyWith(color: AppColors.primary),
          ),
        ),
      ],
    );
  }

  // ── عرض النجاح بعد إرسال الرمز ─────────────────────────────
  Widget _buildSuccessView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Container(
          width: 88,
          height: 88,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.successContainer,
            boxShadow: [
              BoxShadow(
                color: AppColors.success.withValues(alpha: 0.25),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            color: AppColors.success,
            size: 44,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'تم إرسال الرمز',
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'إذا كان البريد مسجلاً لدينا، فقد وصلتك رسالة تحتوي رمز إعادة '
          'تعيين كلمة المرور. تحقق من صندوق الوارد.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium,
        ),

        // عرض رمز التطوير (فقط عند إرجاع الخادم له في بيئة التطوير)
        if (_devCode != null) ...[
          const SizedBox(height: AppSpacing.xl),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.card.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Text(
                  'رمز إعادة التعيين (وضع التطوير)',
                  style: AppTextStyles.labelMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                SelectableText(
                  _devCode!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headlineMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.huge),

        // زر متابعة لإدخال الرمز وكلمة المرور الجديدة
        SizedBox(
          height: AppSpacing.buttonHeightLg,
          child: FilledButton.icon(
            onPressed: _goToResetPassword,
            icon: const Icon(Icons.key),
            label: Text(
              'إدخال الرمز وتعيين كلمة المرور',
              style: AppTextStyles.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // إعادة إرسال / رجوع
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(
              onPressed: () => setState(() => _emailSent = false),
              child: Text(
                'تغيير البريد',
                style: AppTextStyles.bodyMedium?.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
            TextButton(
              onPressed: _goToLogin,
              child: Text(
                'تسجيل الدخول',
                style: AppTextStyles.bodyMedium?.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
