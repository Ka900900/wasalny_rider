import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:wasalny_rider/core/services/api_service.dart';
import 'package:wasalny_rider/core/services/socket_service.dart';
import 'package:wasalny_rider/core/theme/app_theme.dart';
import 'package:wasalny_rider/core/utils/logger.dart';

/// Statuses that mean a real driver was matched (case-insensitive).
/// Backend uses ACCEPTED (uppercase); we always normalize to lowercase.
const Set<String> _driverFoundStatuses = {
  'accepted',
  'assigned',
  'driver_assigned',
  'arrived',
  'driver_arrived',
  'started',
  'in_progress',
  'ongoing',
};

/// Statuses that mean keep waiting (PENDING from backend = still searching).
const Set<String> _waitingStatuses = {
  'pending',
  'searching',
  'requested',
  'created',
  'new',
};

/// Statuses that mean the ride was cancelled / rejected server-side.
const Set<String> _cancelledStatuses = {'cancelled', 'canceled', 'rejected'};

/// Result returned by [FindingDriverDialog] when a driver accepts the ride.
///
/// Carries the captain's data (extracted from the socket payload / ride
/// polling) so the caller can pass it to the active-trip screen for the call
/// and chat buttons.
class DriverAssignment {
  const DriverAssignment({
    required this.rideId,
    this.driverId,
    this.driverName,
    this.driverPhone,
    this.driverCar,
  });

  /// The backend ride id.
  final String rideId;

  /// The captain (driver) id — used as the chat receiver.
  final String? driverId;

  /// Captain display name.
  final String? driverName;

  /// Captain phone number.
  final String? driverPhone;

  /// Captain car description (model / plate).
  final String? driverCar;
}

/// Modal dialog shown while the app searches for a real nearby driver.
///
/// Listens to [SocketService.onRideStatusChanged] for live status updates and
/// falls back to polling [ApiService.getCurrentRide] every 4 seconds. Pops
/// with a [DriverAssignment] when a driver accepts the ride, or `null` on
/// user cancel or server-side cancellation. The "إلغاء الطلب" button calls
/// both [ApiService.cancelRide] and [SocketService.cancelRide].
class FindingDriverDialog extends StatefulWidget {
  const FindingDriverDialog({super.key, required this.rideId});

  /// The backend ride id to watch for status changes.
  final String rideId;

  @override
  State<FindingDriverDialog> createState() => _FindingDriverDialogState();
}

class _FindingDriverDialogState extends State<FindingDriverDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  Timer? _pollTimer;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

    _ensureSocketConnected();
    // الانضمام لغرفة `ride:{rideId}` لاستقبال أحداث حالة الرحلة اللحظية
    // (`ride.accepted` / `ride.status_update`) — البولينغ يبقى احتياطياً.
    SocketService().joinRide(widget.rideId);
    SocketService().onRideStatusChanged = _onRideStatusChanged;
    _startPolling();
  }

  /// Best-effort socket connect so live ride-status events are received
  /// (polling remains the reliable fallback).
  void _ensureSocketConnected() {
    try {
      final api = ApiService.instance;
      final socket = SocketService();
      if (socket.socket == null || !socket.socket!.connected) {
        final userId = api.userId;
        final token = api.getToken();
        if (userId != null && userId.isNotEmpty && token != null) {
          socket.initSocket(userId, token);
        }
      }
    } catch (e) {
      logWarning('FindingDriverDialog', 'socket init failed: $e');
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _pollRideStatus();
    });
  }

  Future<void> _pollRideStatus() async {
    try {
      final data = await ApiService.instance.getCurrentRide();
      if (!mounted || _finished) return;
      final status = _extractStatus(data);
      if (status == null) return;
      _handleStatus(status, data);
    } catch (e) {
      logWarning('FindingDriverDialog', 'poll ride status failed: $e');
    }
  }

  void _onRideStatusChanged(String status, Map<String, dynamic> data) {
    if (_finished) return;
    logInfo('FindingDriverDialog', 'ride status via socket -> $status');
    _handleStatus(status, data);
  }

  void _handleStatus(String status, Map<String, dynamic> data) {
    final normalized = status.trim().toLowerCase();
    // PENDING / pending → keep waiting (do nothing).
    if (_waitingStatuses.contains(normalized)) return;
    // ACCEPTED / accepted → driver found.
    if (_driverFoundStatuses.contains(normalized)) {
      _finish(true, data: data);
      return;
    }
    if (_cancelledStatuses.contains(normalized)) {
      _finish(false);
    }
  }

  /// Extracts the ride status from a `GET /rides/current` response, handling
  /// `status`, `ride.status`, `data.status` and `data.ride.status` shapes.
  String? _extractStatus(Map<String, dynamic> data) {
    final status = data['status'];
    if (status is String) return status;
    final ride = data['ride'];
    if (ride is Map) {
      final s = ride['status'];
      if (s is String) return s;
    }
    final nested = data['data'];
    if (nested is Map) {
      final s = nested['status'];
      if (s is String) return s;
      final nestedRide = nested['ride'];
      if (nestedRide is Map) {
        final rs = nestedRide['status'];
        if (rs is String) return rs;
      }
    }
    return null;
  }

  void _finish(bool found, {Map<String, dynamic>? data}) {
    if (_finished || !mounted) return;
    _finished = true;
    _pollTimer?.cancel();
    if (found) {
      Navigator.of(context).pop(_assignmentFromData(data ?? const {}));
    } else {
      Navigator.of(context).pop(null);
    }
  }

  /// Builds a [DriverAssignment] from the socket / poll payload that carried
  /// the accepted event. Handles both a nested `driver` object and top-level
  /// `driverId`/`driverName`/... fields (flexible against the backend shape).
  DriverAssignment _assignmentFromData(Map<String, dynamic> data) {
    String? driverId;
    String? driverName;
    String? driverPhone;
    String? driverCar;

    final driver = data['driver'];
    if (driver is Map) {
      final d = Map<String, dynamic>.from(driver);
      driverId = _asStr(
        d['id'] ?? d['driverId'] ?? d['userId'] ?? d['captainId'],
      );
      driverName = _asStr(d['name'] ?? d['fullName'] ?? d['driverName']);
      driverPhone = _asStr(d['phone'] ?? d['phoneNumber'] ?? d['driverPhone']);
      driverCar = _asStr(
        d['car'] ?? d['vehicle'] ?? d['carModel'] ?? d['carPlate'],
      );
    }
    driverId ??= _asStr(
      data['driverId'] ?? data['driver_id'] ?? data['captainId'],
    );
    driverName ??= _asStr(data['driverName'] ?? data['captainName']);
    driverPhone ??= _asStr(data['driverPhone'] ?? data['driver_phone']);
    driverCar ??= _asStr(
      data['driverCar'] ?? data['carModel'] ?? data['vehicle'],
    );

    return DriverAssignment(
      rideId: widget.rideId,
      driverId: driverId,
      driverName: driverName,
      driverPhone: driverPhone,
      driverCar: driverCar,
    );
  }

  /// Coerces a JSON value into a non-empty String, else null.
  String? _asStr(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    if (value is num) return value.toString();
    return null;
  }

  Future<void> _cancel() async {
    if (_finished) return;
    _pollTimer?.cancel();
    try {
      await ApiService.instance.cancelRide(widget.rideId);
    } catch (e) {
      logWarning('FindingDriverDialog', 'cancelRide API failed: $e');
    }
    SocketService().cancelRide(widget.rideId);
    _finish(false);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    final socket = SocketService();
    socket.leaveRide(widget.rideId);
    // Only clear the socket callback if it still points at this dialog.
    if (socket.onRideStatusChanged == _onRideStatusChanged) {
      socket.onRideStatusChanged = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: AppColors.darkBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => _buildRadar(),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('جاري البحث عن سائق', style: AppTextStyles.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'يرجى الانتظار حتى نجد لك سائقًا قريبًا',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                height: AppSpacing.buttonHeightMd,
                child: OutlinedButton.icon(
                  onPressed: _cancel,
                  icon: const Icon(Icons.close),
                  label: const Text('إلغاء الطلب'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRadar() {
    return CustomPaint(
      painter: _RadarPainter(
        progress: _pulse.value,
        color: AppColors.primaryGreen,
      ),
      child: Center(
        child: Icon(
          Icons.directions_car_rounded,
          color: AppColors.primaryGreen,
          size: 40,
        ),
      ),
    );
  }
}

/// Paints a pulsing radar: expanding concentric rings plus a sweeping beam.
class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;

    // Expanding pulse rings.
    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1.0;
      final radius = maxRadius * t;
      final alpha = (1 - t) * 0.5;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0));
      canvas.drawCircle(center, radius.clamp(0.0, maxRadius), paint);
    }

    // Radar beam sweep.
    final beamPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: 0.35);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxRadius - 2),
      progress * 2 * math.pi,
      math.pi / 3,
      false,
      beamPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
