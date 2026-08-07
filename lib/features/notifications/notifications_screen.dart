import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/services/api_service.dart';
import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/core/utils/logger.dart';

/// شاشة الإشعارات.
///
/// تجلب الإشعارات من الـ Backend فقط عبر `GET /captain/notifications`.
/// الباك الحالي يقيد هذا المسار بدور CAPTAIN/DRIVER (الراكب يحصل على 403)،
/// لذلك عند أي فشل نعرض الحالة الفارغة «لا توجد إشعارات» — بلا أي بيانات
/// وهمية. عند توفر endpoint خاص بالراكب سيظهر تلقائياً.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  bool _failed = false;
  List<_Notification> _notifications = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final resp = await ApiService.instance.getNotifications();
      final items = (resp['notifications'] as List?) ?? const [];
      final parsed = items
          .whereType<Map>()
          .map((n) => _Notification.fromJson(Map<String, dynamic>.from(n)))
          .toList();
      if (!mounted) return;
      setState(() {
        _notifications = parsed;
        _loading = false;
      });
    } catch (e) {
      // أي فشل (بما فيه 403 لعدم توفر endpoint للراكب) → قائمة فارغة، لا موك.
      logWarning('NotificationsScreen', 'getNotifications failed: $e');
      if (!mounted) return;
      setState(() {
        _notifications = const [];
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _markRead(_Notification item) async {
    if (item.read || item.id == null) return;
    // تحديث محلي فوري + محاولة مزامنة مع الباك (Best-effort).
    setState(() {
      _notifications = _notifications
          .map((n) => n.id == item.id ? n.copyWith(read: true) : n)
          .toList();
    });
    await ApiService.instance.markNotificationRead(item.id!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        title: const Text('الإشعارات'),
        backgroundColor: AppColors.darkBg,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }
    if (_notifications.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.notifications_off_rounded,
                size: 56,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('لا توجد إشعارات', style: AppTextStyles.titleMedium),
              if (_failed) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'خدمة الإشعارات غير متاحة بعد',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelSmall,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh, color: AppColors.primaryGreen),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primaryGreen,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: _notifications.length,
        itemBuilder: (context, index) => _buildCard(_notifications[index]),
      ),
    );
  }

  Widget _buildCard(_Notification item) {
    return InkWell(
      onTap: () => _markRead(item),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: item.read
              ? AppColors.cardBg
              : AppColors.primaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(item.icon, color: AppColors.primaryGreen),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: AppTextStyles.titleSmall),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(item.body, style: AppTextStyles.bodySmall),
                  ],
                  if (item.timeLabel.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(item.timeLabel, style: AppTextStyles.labelSmall),
                  ],
                ],
              ),
            ),
            if (!item.read)
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 6),
                decoration: const BoxDecoration(
                  color: AppColors.primaryGreen,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Notification {
  const _Notification({
    this.id,
    required this.title,
    required this.body,
    required this.icon,
    required this.read,
    this.timeLabel = '',
  });

  final String? id;
  final String title;
  final String body;
  final IconData icon;
  final bool read;
  final String timeLabel;

  factory _Notification.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] as String? ?? '').toUpperCase();
    final icon = _iconForType(rawType);
    final read = json['isRead'] as bool? ?? false;
    var timeLabel = '';
    final raw = json['createdAt'];
    if (raw is String && raw.isNotEmpty) {
      final dt = DateTime.tryParse(raw)?.toLocal();
      if (dt != null) {
        final h = dt.hour.toString().padLeft(2, '0');
        final m = dt.minute.toString().padLeft(2, '0');
        timeLabel = '${dt.day}/${dt.month}/${dt.year} · $h:$m';
      }
    }
    return _Notification(
      id: json['id'] as String?,
      title: json['title'] as String? ?? 'إشعار',
      body: json['body'] as String? ?? '',
      icon: icon,
      read: read,
      timeLabel: timeLabel,
    );
  }

  static IconData _iconForType(String type) {
    switch (type) {
      case 'RIDE':
        return Icons.directions_car_rounded;
      case 'PROMO':
      case 'OFFER':
        return Icons.local_offer_rounded;
      case 'WALLET':
        return Icons.account_balance_wallet_rounded;
      case 'SYSTEM':
        return Icons.system_update_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  _Notification copyWith({bool? read}) => _Notification(
    id: id,
    title: title,
    body: body,
    icon: icon,
    read: read ?? this.read,
    timeLabel: timeLabel,
  );
}
