import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/services/api_service.dart';
import 'package:wasalny_rider/core/theme/app_theme.dart';

/// Passenger profile screen.
///
/// Fetches the user's details from `GET /user/profile`, shows a menu of
/// actions and a working "تسجيل الخروج" button that clears the stored JWT
/// token and redirects to the login screen.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await ApiService.instance.getProfile();
      if (mounted) {
        setState(() {
          _profile = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _fullName {
    final p = _profile;
    if (p == null) return 'مستخدم';
    final first = p['firstName'] as String? ?? '';
    final last = p['lastName'] as String? ?? '';
    final name = '$first $last'.trim();
    if (name.isNotEmpty) return name;
    return p['email'] as String? ?? 'مستخدم';
  }

  String get _email => _profile?['email'] as String? ?? '';
  String get _phone =>
      _profile?['phoneNumber'] as String? ?? 'لم تتم إضافة رقم هاتف';

  Future<void> _logout() async {
    ApiService.instance.clearToken();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('هذه الميزة ستتوفر قريبًا')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        title: const Text('الملف الشخصي'),
        backgroundColor: AppColors.darkBg,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            // Header card
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColors.primaryContainer,
                    child: Text(
                      _fullName.isEmpty ? '؟' : _fullName[0],
                      style: AppTextStyles.titleLarge?.copyWith(
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_fullName, style: AppTextStyles.titleLarge),
                        const SizedBox(height: AppSpacing.xxs),
                        if (_email.isNotEmpty)
                          Text(_email, style: AppTextStyles.bodySmall),
                        if (_phone.isNotEmpty)
                          Text(_phone, style: AppTextStyles.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Loading indicator while fetching the profile
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: CircularProgressIndicator(color: AppColors.primaryGreen),
              ),

            // Menu items
            _menuItem(
              icon: Icons.history_rounded,
              label: 'رحلاتي',
              onTap: () => Navigator.pushNamed(context, '/history'),
            ),
            _menuItem(
              icon: Icons.notifications_rounded,
              label: 'الإشعارات',
              onTap: () => Navigator.pushNamed(context, '/notifications'),
            ),
            _menuItem(
              icon: Icons.payments_rounded,
              label: 'طرق الدفع',
              onTap: _showComingSoon,
            ),
            _menuItem(
              icon: Icons.settings_rounded,
              label: 'الإعدادات',
              onTap: _showComingSoon,
            ),
            _menuItem(
              icon: Icons.info_outline_rounded,
              label: 'عن التطبيق',
              onTap: _showComingSoon,
            ),

            const SizedBox(height: AppSpacing.xl),

            // Logout
            SizedBox(
              width: double.infinity,
              height: AppSpacing.buttonHeightLg,
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout_rounded),
                label: Text(
                  'تسجيل الخروج',
                  style: AppTextStyles.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryGreen, size: AppSpacing.iconMd),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: Text(label, style: AppTextStyles.titleSmall)),
            const Icon(Icons.chevron_left_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
