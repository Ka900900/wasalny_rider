import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/theme/app_theme.dart';

/// Trip history screen with two tabs: upcoming trips and past trips.
///
/// Uses an active [TabBar] and dynamic list cards. The sample data below can
/// later be replaced with `ApiService.instance.getRideHistory()`.
class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  // Sample data — replace with ApiService.getRideHistory() when the backend
  // response shape is finalised.
  final List<_Trip> _upcoming = const [
    _Trip(
      destination: 'مطار القاهرة الدولي',
      date: 'الجمعة ٢ أغسطس',
      time: '١٨:٠٠',
      fare: 75,
      status: 'مؤكدة',
    ),
    _Trip(
      destination: 'وسط البلد',
      date: 'السبت ٣ أغسطس',
      time: '٠٩:٣٠',
      fare: 35,
      status: 'في الانتظار',
    ),
  ];

  final List<_Trip> _past = const [
    _Trip(
      destination: 'التجمع الخامس',
      date: 'الخميس ١ أغسطس',
      time: '١٤:٢٠',
      fare: 55,
      status: 'مكتملة',
      rating: 5,
    ),
    _Trip(
      destination: 'مدينة نصر',
      date: 'الأربعاء ٣١ يوليو',
      time: '١٠:٠٥',
      fare: 40,
      status: 'مكتملة',
      rating: 4,
    ),
    _Trip(
      destination: 'المعادي',
      date: 'الثلاثاء ٣٠ يوليو',
      time: '١٩:٤٥',
      fare: 60,
      status: 'مكتملة',
      rating: 5,
    ),
    _Trip(
      destination: 'الدقي',
      date: 'الإثنين ٢٩ يوليو',
      time: '٠٨:١٥',
      fare: 30,
      status: 'ملغاة',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        appBar: AppBar(
          title: const Text('رحلاتي'),
          backgroundColor: AppColors.darkBg,
          bottom: TabBar(
            indicatorColor: AppColors.primaryGreen,
            labelColor: AppColors.primaryGreen,
            unselectedLabelColor: AppColors.textMuted,
            tabs: const [
              Tab(text: 'الرحلات القادمة'),
              Tab(text: 'الرحلات السابقة'),
            ],
          ),
        ),
        body: TabBarView(children: [_buildList(_upcoming), _buildList(_past)]),
      ),
    );
  }

  Widget _buildList(List<_Trip> trips) {
    if (trips.isEmpty) {
      return const Center(child: Text('لا توجد رحلات'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: trips.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) => _TripCard(trip: trips[index]),
    );
  }
}

class _Trip {
  const _Trip({
    required this.destination,
    required this.date,
    required this.time,
    required this.fare,
    required this.status,
    this.rating,
  });

  final String destination;
  final String date;
  final String time;
  final double fare;
  final String status;
  final int? rating;
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});

  final _Trip trip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: const Icon(
              Icons.directions_car_rounded,
              color: AppColors.primaryGreen,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trip.destination, style: AppTextStyles.titleMedium),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${trip.date} · ${trip.time}',
                  style: AppTextStyles.bodySmall,
                ),
                if (trip.rating != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Text('${trip.rating}', style: AppTextStyles.labelMedium),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${trip.fare} جنيه',
                style: AppTextStyles.titleSmall?.copyWith(
                  color: AppColors.primaryGreen,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                trip.status,
                style: AppTextStyles.labelSmall?.copyWith(
                  color: _statusColor(trip.status),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'مكتملة':
        return AppColors.primaryGreen;
      case 'ملغاة':
        return AppColors.error;
      default:
        return AppColors.info;
    }
  }
}
