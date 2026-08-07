import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wasalny_rider/core/constants/app_constants.dart';
import 'package:wasalny_rider/core/services/api_service.dart';
import 'package:wasalny_rider/core/services/auth_service.dart';
import 'package:wasalny_rider/core/theme/app_theme.dart';

/// شاشة إعدادات التطبيق (خفيفة).
///
/// - اللغة: عربي افتراضي (ثابت حالياً).
/// - الإشعارات: مفتاح محلي عبر SharedPreferences + مزامنة اختيارية مع
///   `PUT /notifications/preferences` في الباك.
/// - مشاركة التطبيق + تسجيل الخروج.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _notifPrefsKey = 'notifications_enabled';

  bool _notificationsEnabled = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    var local = prefs.getBool(_notifPrefsKey) ?? true;
    // نفضل قيمة الباك إن توفرت، مع بقاء المحلي احتياطياً.
    try {
      final remote = await ApiService.instance.getNotificationPreferences();
      local = remote;
      await prefs.setBool(_notifPrefsKey, local);
    } catch (_) {
      // لا نكسر الشاشة إذا فشل جلب التفضيلات من الباك.
    }
    if (mounted) {
      setState(() => _notificationsEnabled = local);
    }
  }

  Future<void> _setNotifications(bool value) async {
    setState(() {
      _notificationsEnabled = value;
      _syncing = true;
    });
    // مزامنة محلية أولاً (تبقى سليمة حتى بدون شبكة).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifPrefsKey, value);
    // مزامنة اختيارية مع الباك (Best-effort).
    final ok = await ApiService.instance.updateNotificationPreferences(value);
    if (!ok) {
      _showSyncWarning();
    }
    if (!mounted) return;
    setState(() => _syncing = false);
  }

  void _showSyncWarning() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم الحفظ محلياً، تعذرت المزامنة مع الخادم الآن'),
        backgroundColor: AppColors.warning,
      ),
    );
  }

  Future<void> _shareApp() async {
    const message =
        'جرّب تطبيق وصلني 🚕\nاطلب رحلة بسهولة — سيارة أو موتوسيكل أو سكوتر\nحمّل التطبيق من هنا:\n${AppConstants.appShareUrl}';
    await Share.share(message, subject: 'وصلني');
  }

  Future<void> _logout() async {
    await AuthService.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        title: const Text('الإعدادات'),
        backgroundColor: AppColors.darkBg,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // اللغة
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.language_rounded,
                  color: AppColors.primaryGreen,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('اللغة', style: AppTextStyles.titleSmall),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'العربية (الافتراضية)',
                        style: AppTextStyles.labelSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // الإشعارات
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_active_rounded,
                  color: AppColors.primaryGreen,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الإشعارات', style: AppTextStyles.titleSmall),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        _syncing
                            ? 'جارٍ المزامنة...'
                            : 'تفعيل استقبال الإشعارات',
                        style: AppTextStyles.labelSmall,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _notificationsEnabled,
                  onChanged: _syncing ? null : _setNotifications,
                  activeTrackColor: AppColors.primaryGreen,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // مشاركة التطبيق
          _menuItem(
            icon: Icons.share_rounded,
            label: 'شارك التطبيق',
            onTap: _shareApp,
          ),

          const SizedBox(height: AppSpacing.xl),

          // تسجيل الخروج
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
