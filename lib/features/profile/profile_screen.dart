import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'package:wasalny_rider/core/constants/app_constants.dart';
import 'package:wasalny_rider/core/services/api_service.dart';
import 'package:wasalny_rider/core/services/auth_service.dart';
import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/core/utils/logger.dart';
import 'package:wasalny_rider/core/utils/price_formatter.dart';

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
  bool _uploadingAvatar = false;
  double? _walletBalance;

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
    // رصيد المحفظة من الباك فقط (يعرضه بجانب «المحفظة» إن توفر).
    try {
      final w = await ApiService.instance.getWalletBalance();
      final bal = w['balance'];
      if (mounted && bal != null) {
        setState(() => _walletBalance = parsePrice(bal));
      }
    } catch (e) {
      logWarning('ProfileScreen', 'getWalletBalance failed: $e');
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

  String? get _avatarUrl {
    final u = _profile?['avatarUrl'] as String?;
    if (u == null || u.isEmpty) return null;
    return u;
  }

  /// يلتقط صورة من المعرض أو الكاميرا، يرفعها إلى `/upload/profile` ثم يحدّث
  /// الملف الشخصي بالرابط الجديد `PUT /user/profile/update`.
  Future<void> _changeAvatar() async {
    if (_uploadingAvatar) return;
    final source = await _pickAvatarSource();
    if (source == null || !mounted) return;
    final picker = ImagePicker();
    try {
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (picked == null) return;
      setState(() => _uploadingAvatar = true);
      final upload = await ApiService.instance.uploadProfileImage(picked.path);
      final imageUrl = upload['imageUrl'] as String?;
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('upload returned no imageUrl');
      }
      await ApiService.instance.updateProfile(avatarUrl: imageUrl);
      await _loadProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث الصورة الشخصية'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      logError('ProfileScreen', 'changeAvatar failed: $e', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر رفع الصورة، حاول مرة أخرى'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<ImageSource?> _pickAvatarSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.darkBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXxl),
        ),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('تغيير الصورة الشخصية', style: AppTextStyles.titleLarge),
              const SizedBox(height: AppSpacing.lg),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: AppColors.primaryGreen,
                ),
                title: Text('من المعرض', style: AppTextStyles.titleSmall),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_camera_rounded,
                  color: AppColors.primaryGreen,
                ),
                title: Text('التقاط صورة', style: AppTextStyles.titleSmall),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    // End the Firebase session AND clear the stored JWT before leaving.
    await AuthService.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  /// يشارك رابط التطبيق عبر نافذة المشاركة الخاصة بالجهاز.
  Future<void> _shareApp() async {
    const message =
        'جرّب تطبيق وصلني 🚕\nاطلب رحلة بسهولة — سيارة أو موتوسيكل أو سكوتر\nحمّل التطبيق من هنا:\n${AppConstants.appShareUrl}';
    await Share.share(message, subject: 'وصلني');
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
                  GestureDetector(
                    onTap: _changeAvatar,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: AppColors.primaryContainer,
                          backgroundImage: _avatarUrl != null
                              ? NetworkImage(_avatarUrl!)
                              : null,
                          child: _avatarUrl == null
                              ? Text(
                                  _fullName.isEmpty ? '؟' : _fullName[0],
                                  style: AppTextStyles.titleLarge?.copyWith(
                                    color: AppColors.primaryGreen,
                                  ),
                                )
                              : null,
                        ),
                        if (_uploadingAvatar)
                          const Positioned.fill(
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppColors.primaryGreen,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.photo_camera_rounded,
                              size: 14,
                              color: AppColors.textOnPrimary,
                            ),
                          ),
                        ),
                      ],
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
              icon: Icons.account_balance_wallet_rounded,
              label: 'المحفظة',
              trailing: _walletBalance != null
                  ? Text(
                      formatEGP(_walletBalance!),
                      style: AppTextStyles.titleSmall?.copyWith(
                        color: AppColors.primaryGreen,
                      ),
                    )
                  : null,
              onTap: () => Navigator.pushNamed(context, '/wallet'),
            ),
            _menuItem(
              icon: Icons.settings_rounded,
              label: 'الإعدادات',
              onTap: () => Navigator.pushNamed(context, '/settings'),
            ),
            _menuItem(
              icon: Icons.share_rounded,
              label: 'شارك التطبيق',
              onTap: _shareApp,
            ),
            _menuItem(
              icon: Icons.info_outline_rounded,
              label: 'عن التطبيق',
              onTap: () => Navigator.pushNamed(context, '/about'),
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
    Widget? trailing,
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
            ?trailing,
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.chevron_left_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
