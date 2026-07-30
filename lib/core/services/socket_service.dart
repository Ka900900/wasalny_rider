import 'dart:developer';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Singleton service for managing a WebSocket connection to the Waslny
/// backend. The rider connects with `role: 'RIDER'` to receive live
/// updates about ride status, driver location, etc.
class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  io.Socket? socket;

  /// Callback when the driver's location is updated in real-time.
  void Function(double lat, double lng)? onDriverLocationUpdate;

  /// Callback when the ride status changes (accepted, arrived, started, completed).
  void Function(String status, Map<String, dynamic> data)? onRideStatusChanged;

  /// Initialize the socket connection to the server.
  void initSocket(String userId, String token) {
    if (socket != null && socket!.connected) return;

    const String socketUrl =
        "https://wasalny-backend-production.up.railway.app";

    log('جاري الاتصال بسيرفر السوكيت: $socketUrl');

    socket = io.io(
      socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setQuery({
            'userId': userId,
            'role': 'RIDER', // Rider role for the backend
          })
          .setAuth({'token': token})
          .build(),
    );

    socket!.connect();

    socket!.onConnect((_) {
      log('🟢 تم الاتصال بسيرفر السوكيت بنجاح!');
      socket!.emit('join_rider', {'userId': userId});
    });

    socket!.onDisconnect((_) => log('🔴 تم قطع الاتصال بالسوكيت'));
    socket!.onConnectError((data) => log('⚠️ خطأ في الاتصال بالسوكيت: $data'));
    socket!.onError((data) => log('❌ خطأ في السوكيت: $data'));

    // Listen for driver location updates
    socket!.on('driver.location', (data) {
      if (data is Map) {
        try {
          final map = Map<String, dynamic>.from(data);
          final lat = (map['lat'] as num).toDouble();
          final lng = (map['lng'] as num).toDouble();
          onDriverLocationUpdate?.call(lat, lng);
        } catch (e) {
          log('⚠️ خطأ في تحليل موقع الكابتن: $e');
        }
      }
    });

    // Listen for ride status changes
    socket!.on('ride.status', (data) {
      if (data is Map) {
        try {
          final map = Map<String, dynamic>.from(data);
          final status = map['status'] as String? ?? '';
          onRideStatusChanged?.call(status, map);
        } catch (e) {
          log('⚠️ خطأ في تحليل حالة الرحلة: $e');
        }
      }
    });
  }

  /// Request a ride (emit event to the server).
  void requestRide(Map<String, dynamic> rideData) {
    if (socket == null || !socket!.connected) {
      log('⚠️ السوكيت غير متصل. لا يمكن طلب الرحلة.');
      return;
    }
    socket!.emit('ride.request', rideData);
    log('📤 تم إرسال طلب الرحلة عبر السوكيت');
  }

  /// Cancel a ride via socket.
  void cancelRide(String rideId) {
    if (socket == null || !socket!.connected) {
      log('⚠️ السوكيت غير متصل. لا يمكن إلغاء الرحلة.');
      return;
    }
    socket!.emit('ride.cancel', {'rideId': rideId});
    log('📤 تم إرسال إلغاء الرحلة عبر السوكيت');
  }

  /// Disconnect the socket.
  void disconnect() {
    if (socket != null) {
      socket!.disconnect();
      socket = null;
      log('🔌 تم إغلاق السوكيت يدوياً.');
    }
  }
}
