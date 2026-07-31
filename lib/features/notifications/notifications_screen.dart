import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/theme/app_theme.dart';

/// Notifications screen.
///
/// Renders an active [ListView] of notifications with:
/// - tap → marks the item as read,
/// - swipe (dismiss) → removes the item.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<_Notification> _notifications = [
    const _Notification(
      title: 'وصل سائقك',
      body: 'السائق أحمد في طريقه إليك. يرجى الاستعداد.',
      icon: Icons.directions_car_rounded,
      read: false,
    ),
    const _Notification(
      title: 'تأكيد الرحلة',
      body: 'تم تأكيد رحلتك إلى مطار القاهرة.',
      icon: Icons.check_circle_rounded,
      read: false,
    ),
    const _Notification(
      title: 'عرض ترويجي',
      body: 'خصم 20% على رحلتك القادمة مع وصلني VIP.',
      icon: Icons.local_offer_rounded,
      read: true,
    ),
    const _Notification(
      title: 'تحديث التطبيق',
      body: 'تم تحديث تطبيق وصلني إلى الإصدار الجديد.',
      icon: Icons.system_update_rounded,
      read: true,
    ),
  ];

  void _dismiss(int index) {
    setState(() => _notifications.removeAt(index));
  }

  void _markRead(int index) {
    final item = _notifications[index];
    if (item.read) return;
    setState(() => _notifications[index] = item.copyWith(read: true));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم تحديد الإشعار كمقروء')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        title: const Text('الإشعارات'),
        backgroundColor: AppColors.darkBg,
      ),
      body: _notifications.isEmpty
          ? const Center(child: Text('لا توجد إشعارات'))
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final item = _notifications[index];
                return Dismissible(
                  key: ValueKey('notif-$index-${item.title}'),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _dismiss(index),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: AppColors.white,
                    ),
                  ),
                  child: _buildNotificationCard(index, item),
                );
              },
            ),
    );
  }

  Widget _buildNotificationCard(int index, _Notification item) {
    return InkWell(
      onTap: () => _markRead(index),
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
          children: [
            Icon(item.icon, color: AppColors.primaryGreen),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: AppTextStyles.titleSmall),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(item.body, style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            if (!item.read)
              Container(
                width: 10,
                height: 10,
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
    required this.title,
    required this.body,
    required this.icon,
    required this.read,
  });

  final String title;
  final String body;
  final IconData icon;
  final bool read;

  _Notification copyWith({bool? read}) => _Notification(
    title: title,
    body: body,
    icon: icon,
    read: read ?? this.read,
  );
}
