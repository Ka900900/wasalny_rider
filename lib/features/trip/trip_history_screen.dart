import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/services/api_service.dart';
import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/core/utils/logger.dart';
import 'package:wasalny_rider/core/utils/price_formatter.dart';

/// Trip history screen with two tabs: upcoming trips and past trips.
///
/// Data comes from the backend `GET /rides/history` — the displayed prices
/// are the real backend `price` values, not local samples.
class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  static const List<String> _arMonths = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  List<_Trip> _upcoming = const [];
  List<_Trip> _past = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await ApiService.instance.getRideHistory();
      final rides = resp['rides'];
      final upcoming = <_Trip>[];
      final past = <_Trip>[];
      if (rides is List) {
        for (final item in rides) {
          if (item is! Map) continue;
          final trip = _tripFromMap(item);
          if (_isUpcoming(trip.status)) {
            upcoming.add(trip);
          } else {
            past.add(trip);
          }
        }
      }
      // التاريخ لا يعيد الرحلة الجارية (PENDING/ACCEPTED/...) — نجلبها من
      // `/rides/current` حتى تظهر في تبويب «الرحلات القادمة».
      try {
        final current = await ApiService.instance.getCurrentRide();
        final ride = current['ride'];
        if (ride is Map && ride['id'] != null) {
          final trip = _tripFromMap(ride);
          if (_isUpcoming(trip.status) &&
              !upcoming.any((t) => t.id == trip.id)) {
            upcoming.insert(0, trip);
          }
        }
      } catch (e) {
        logWarning('TripHistoryScreen', 'getCurrentRide failed: $e');
      }
      if (!mounted) return;
      setState(() {
        _upcoming = upcoming;
        _past = past;
        _loading = false;
      });
    } catch (e) {
      logError('TripHistoryScreen', 'getRideHistory failed: $e', e);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل الرحلات. تحقق من اتصالك ثم أعد المحاولة.';
      });
    }
  }

  /// يحوّل كائن رحلة من الـ Backend إلى [_Trip] (يتعامل مع نفس الحقول
  /// سواء جاءت من `/rides/history` أو `/rides/current`).
  _Trip _tripFromMap(Map<dynamic, dynamic> item) {
    final status = (item['status'] as String?) ?? '';
    final dest = item['destinationAddress'];
    final id = item['id'];
    return _Trip(
      id: id is String && id.isNotEmpty ? id : '',
      destination: dest is String && dest.isNotEmpty
          ? dest
          : 'وجهة غير محددة',
      dateTime: _formatDate(_parseDate(item['createdAt'])),
      fare: parsePrice(item['price']),
      status: status,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  /// هل الرحلة قادمة (قيد التنفيذ) أم سابقة (مكتملة/ملغاة)؟
  static bool _isUpcoming(String status) {
    switch (status) {
      case 'COMPLETED':
      case 'CANCELLED':
      case 'CANCELED':
      case 'REJECTED':
        return false;
      default:
        // PENDING, ACCEPTED, ASSIGNED, ARRIVED, STARTED, ...
        return true;
    }
  }

  /// تنسيق التاريخ إلى شكل عربي واضح، مثل: «6 أغسطس 2026 · 17:09».
  static String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    final m = _arMonths[local.month - 1];
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '${local.day} $m ${local.year} · $h:$min';
  }

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
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _loadHistory,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    return TabBarView(children: [_buildList(_upcoming), _buildList(_past)]);
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
    required this.id,
    required this.destination,
    required this.dateTime,
    required this.fare,
    required this.status,
  });

  final String id;
  final String destination;
  final String dateTime;
  final double fare;
  final String status;
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});

  final _Trip trip;

  /// عنوان عربي لحالة الرحلة القادم من الـ Backend.
  String get _statusLabel => switch (trip.status) {
    'COMPLETED' => 'مكتملة',
    'CANCELLED' || 'CANCELED' => 'ملغاة',
    'REJECTED' => 'مرفوضة',
    'PENDING' => 'قيد الانتظار',
    'ACCEPTED' || 'ASSIGNED' => 'تم تأكيدها',
    'ARRIVED' || 'STARTED' => 'جارية',
    _ => trip.status,
  };

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
                Text(trip.dateTime, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatEGP(trip.fare),
                style: AppTextStyles.titleSmall?.copyWith(
                  color: AppColors.primaryGreen,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _statusLabel,
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
      case 'COMPLETED':
        return AppColors.primaryGreen;
      case 'CANCELLED':
      case 'CANCELED':
      case 'REJECTED':
        return AppColors.error;
      case 'PENDING':
        return AppColors.warning;
      default:
        return AppColors.info;
    }
  }
}
