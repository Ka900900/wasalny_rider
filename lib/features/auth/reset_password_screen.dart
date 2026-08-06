import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/network/api_exceptions.dart';
import 'package:wasalny_rider/core/services/api_service.dart';
import 'package:wasalny_rider/core/theme/app_theme.dart';

/// وسائط الانتقال إلى شاشة إعادة تعيين كلمة المرور.
class ResetPasswordArgs {
  const ResetPasswordArgs({this.email, this.devCode});

  /// البريد الإلكتروني الذي طلب إعادة التعيين منه (اختياري).
  final String? email;

  /// رمز إعادة التعيين الذي أعاده الخادم في بيئة التطوير (اختياري) —
  /// يُعبأ تلقائياً في حقل الرمز أثناء الاختبار.
  final String? devCode;
}

/// شاشة تعيين كلمة مرور جديدة بعد استلام رمز إعادة التعيين.
///
/// - يُدخل المستخدم الرمز الذي وصله (code) + كلمة مرور جديدة (مع تأكيدها).
/// - نرسلها عبر `POST /auth/reset-password`.
/// - عند النجاح تظهر رسالة تأكيد ثم نعود لشاشة تسجيل الدخول.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.email, this.devCode});

  /// البريد الإلكتروني (اختياري) — يُستخدم للعرض فقط في هذه الشاشة.
  final String? email;

  /// رمز إعادة التعيين (اختياري) — إذا وُجد يُعبأ تلقائياً في حقل الرمز
  /// (مفيد أثناء الاختبار في بيئة التطوير حيث يعيد الخادم `devCode`).
  final String? devCode;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _resetDone = false;

  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // في بيئة التطوير، إذا أعاد الخادم رمزاً (devCode) نعبّئه تلقائياً.
    final devCode = widget.devCode;
    if (devCode != null && devCode.isNotEmpty) {
      _codeController.text = devCode;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);
    try {
      await ApiService.instance.resetPassword(
        code: _codeController.text,
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _resetDone = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(_mapError(e));
    }
  }

  /// العودة إلى شاشة تسجيل الدخول بعد نجاح إعادة التعيين.
  ///
  /// نستبدل كل الـ stack (splash + forgot + reset) بشاشة تسجيل الدخول
  /// مباشرة، فلا تبقى شاشات قديمة خلفها ولا نحتاج `popUntil` مسبقاً.
  void _goToLogin() {
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
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
        title: const Text('تعيين كلمة مرور جديدة'),
        backgroundColor: AppColors.primaryBg,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxl,
            vertical: AppSpacing.xl,
          ),
          child: _resetDone ? _buildSuccessView() : _buildFormView(),
        ),
      ),
    );
  }

  // ── نموذج إدخال الرمز + كلمة المرور الجديدة ──────────────
  Widget _buildFormView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Icon(Icons.key, color: AppColors.primary, size: 64),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'تعيين كلمة مرور جديدة',
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'أدخل الرمز الذي وصلك عبر البريد، ثم اختر كلمة مرور جديدة.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium,
        ),
        if (widget.email != null && widget.email!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.email!,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelMedium?.copyWith(
              color: AppColors.primary,
            ),
          ),
        ],
        if (widget.devCode != null && widget.devCode!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.successContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.success,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    'تم تعبئة رمز التطوير تلقائياً',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.labelMedium?.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.huge),

        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // حقل الرمز
              TextFormField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textInputAction: TextInputAction.next,
                style: const TextStyle(color: AppColors.textPrimary),
                validator: (v) {
                  final code = v?.trim() ?? '';
                  if (code.isEmpty) return 'أدخل رمز إعادة التعيين';
                  if (code.length < 6) return 'الرمز مكوّن من 6 أرقام';
                  return null;
                },
                decoration: InputDecoration(
                  labelText: 'رمز إعادة التعيين',
                  counterText: '',
                  prefixIcon: Icon(
                    Icons.pin_outlined,
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
                    borderSide: BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // كلمة المرور الجديدة
              TextFormField(
                controller: _passwordController,
                obscureText: !_obscurePassword,
                textInputAction: TextInputAction.next,
                style: const TextStyle(color: AppColors.textPrimary),
                validator: (v) {
                  if (v == null || v.length < 6) {
                    return 'كلمة المرور 6 أحرف على الأقل';
                  }
                  return null;
                },
                decoration: InputDecoration(
                  labelText: 'كلمة المرور الجديدة',
                  prefixIcon: Icon(
                    Icons.lock_outline,
                    color: AppColors.textMuted,
                  ),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: AppColors.textMuted,
                    ),
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
                    borderSide: BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // تأكيد كلمة المرور
              TextFormField(
                controller: _confirmController,
                obscureText: !_obscureConfirm,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                style: const TextStyle(color: AppColors.textPrimary),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'أكد كلمة المرور';
                  }
                  if (v != _passwordController.text) {
                    return 'كلمتا المرور غير متطابقتين';
                  }
                  return null;
                },
                decoration: InputDecoration(
                  labelText: 'تأكيد كلمة المرور',
                  prefixIcon: Icon(
                    Icons.lock_reset,
                    color: AppColors.textMuted,
                  ),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                      color: AppColors.textMuted,
                    ),
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
                    borderSide: BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),

        // زر الحفظ
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
                : const Icon(Icons.check_circle_outline),
            label: Text(
              'حفظ كلمة المرور',
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
      ],
    );
  }

  // ── عرض النجاح بعد إعادة التعيين ───────────────────────────
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
            Icons.check_circle_outline,
            color: AppColors.success,
            size: 44,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'تم تحديث كلمة المرور',
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'تم تغيير كلمة مرورك بنجاح. يمكنك الآن تسجيل الدخول بكلمة المرور '
          'الجديدة.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.huge),

        // زر العودة لتسجيل الدخول
        SizedBox(
          height: AppSpacing.buttonHeightLg,
          child: FilledButton.icon(
            onPressed: _goToLogin,
            icon: const Icon(Icons.login),
            label: Text(
              'تسجيل الدخول',
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
      ],
    );
  }
}
