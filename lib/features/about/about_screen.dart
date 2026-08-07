import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:wasalny_rider/core/theme/app_theme.dart';

/// شاشة «نبذة عن التطبيق».
///
/// - الاسم: «وصلني راكب»
/// - الإصدار من `package_info_plus` (حقيقي وليس ثابت).
/// - وصف قصير + رابط دعم/بريد إلكتروني.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '—';

  static const String _supportEmail = 'support@wasalny.app';
  static const String _website = 'https://wasalny.app';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = info.buildNumber.isNotEmpty ? ' (${info.buildNumber})' : '';
      if (mounted) {
        setState(() => _version = '${info.version}$build');
      }
    } catch (e) {
      // نترك «—» إذا تعذر قراءة الإصدار.
    }
  }

  Future<void> _mailSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: 'subject=${Uri.encodeQueryComponent('دعم تطبيق وصلني راكب')}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد تطبيق بريد على هذا الجهاز'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  Future<void> _openWebsite() async {
    final uri = Uri.parse(_website);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر فتح الرابط'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        title: const Text('نبذة عن التطبيق'),
        backgroundColor: AppColors.darkBg,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusXxl),
              ),
              child: const Icon(
                Icons.local_taxi_rounded,
                size: 56,
                color: AppColors.primaryGreen,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'وصلني راكب',
            textAlign: TextAlign.center,
            style: AppTextStyles.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'الإصدار $_version',
            textAlign: TextAlign.center,
            style: AppTextStyles.labelSmall,
          ),
          const SizedBox(height: AppSpacing.xl),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Text(
              'وصلني هي منصة نقل ذكية تتيح لك طلب سيارة أو موتوسيكل أو سكوتر '
              'بسهولة وأمان، مع تسعير شفاف ومتابعة مباشرة لرحلتك على الخريطة.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _actionTile(
            icon: Icons.email_rounded,
            label: 'الدعم: $_supportEmail',
            onTap: _mailSupport,
          ),
          const SizedBox(height: AppSpacing.md),
          _actionTile(
            icon: Icons.public_rounded,
            label: 'الموقع: $_website',
            onTap: _openWebsite,
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            '© ${DateTime.now().year} وصلني. جميع الحقوق محفوظة.',
            textAlign: TextAlign.center,
            style: AppTextStyles.labelSmall,
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
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
