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

  /// Callback when a new chat message arrives during an active trip.
  void Function(Map<String, dynamic> message)? onNewMessage;

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

    // Driver location (backend may emit either name).
    socket!.on('driver.location', _handleDriverLocation);
    socket!.on('ride.driver_location', _handleDriverLocation);

    // Ride status (backend may emit any of these event names).
    socket!.on('ride.status', (data) => _handleRideEvent(data, ''));
    socket!.on('ride.status_update', (data) => _handleRideEvent(data, ''));
    socket!.on('ride.accepted', (data) => _handleRideEvent(data, 'accepted'));
    socket!.on('ride.cancelled', (data) => _handleRideEvent(data, 'cancelled'));

    // Chat messages (trip chat between rider & captain).
    socket!.on('new_message', _handleNewMessage);
    socket!.on('receive_message', _handleNewMessage);
  }

  /// Parses driver-location payloads (`lat`/`lng`, `latitude`/`longitude`,
  /// nested `location` / `driver`) and forwards via [onDriverLocationUpdate].
  void _handleDriverLocation(dynamic data) {
    if (data is! Map) return;
    try {
      final map = Map<String, dynamic>.from(data);
      dynamic lat = map['lat'] ?? map['latitude'];
      dynamic lng = map['lng'] ?? map['longitude'];
      if (lat == null || lng == null) {
        final location = map['location'];
        if (location is Map) {
          lat ??= location['lat'] ?? location['latitude'];
          lng ??= location['lng'] ?? location['longitude'];
        }
      }
      if (lat == null || lng == null) {
        final driver = map['driver'];
        if (driver is Map) {
          lat ??= driver['lat'] ?? driver['latitude'];
          lng ??= driver['lng'] ?? driver['longitude'];
        }
      }
      final latNum = lat is num ? lat.toDouble() : double.tryParse('$lat');
      final lngNum = lng is num ? lng.toDouble() : double.tryParse('$lng');
      if (latNum != null && lngNum != null) {
        onDriverLocationUpdate?.call(latNum, lngNum);
      }
    } catch (e) {
      log('⚠️ خطأ في تحليل موقع الكابتن: $e');
    }
  }

  /// Routes any ride-related socket event through [onRideStatusChanged].
  /// Uses [fallbackStatus] when the payload has no explicit status
  /// (e.g. `ride.accepted` often only carries `{rideId, driver}`).
  void _handleRideEvent(dynamic data, String fallbackStatus) {
    if (data is! Map) {
      if (fallbackStatus.isNotEmpty) {
        onRideStatusChanged?.call(fallbackStatus, <String, dynamic>{});
      }
      return;
    }
    try {
      final map = Map<String, dynamic>.from(data);
      String status = fallbackStatus;
      final direct = map['status'];
      if (direct is String && direct.isNotEmpty) {
        status = direct;
      } else {
        final ride = map['ride'];
        if (ride is Map && ride['status'] is String) {
          status = ride['status'] as String;
        } else {
          final nested = map['data'];
          if (nested is Map && nested['status'] is String) {
            status = nested['status'] as String;
          }
        }
      }
      if (status.isNotEmpty) {
        onRideStatusChanged?.call(status, map);
      }
    } catch (e) {
      log('⚠️ خطأ في تحليل حالة الرحلة: $e');
    }
  }

  /// Parses an incoming chat message payload and forwards it via
  /// [onNewMessage]. Handles `{text, senderId, receiverId, tripId, ...}` and
  /// nested `data` / `message` wrapper shapes.
  void _handleNewMessage(dynamic data) {
    if (data is! Map) return;
    try {
      var map = Map<String, dynamic>.from(data);
      // Some backends wrap the message under `data` / `message`.
      final wrapped = map['data'] ?? map['message'];
      if (wrapped is Map) map = Map<String, dynamic>.from(wrapped);
      onNewMessage?.call(map);
    } catch (e) {
      log('⚠️ خطأ في تحليل الرسالة: $e');
    }
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

  /// Join a trip room so chat messages for this ride are received.
  void joinTrip(String tripId) {
    if (socket == null || !socket!.connected) {
      log('⚠️ السوكيت غير متصل. لا يمكن الانضمام للرحلة.');
      return;
    }
    socket!.emit('join_trip', {'tripId': tripId});
    log('📥 تم الانضمام إلى غرفة الرحلة: $tripId');
  }

  /// Send a chat message to the captain during an active trip.
  void sendMessage({
    required String tripId,
    required String receiverId,
    required String text,
  }) {
    if (socket == null || !socket!.connected) {
      log('⚠️ السوكيت غير متصل. لا يمكن إرسال الرسالة.');
      return;
    }
    socket!.emit('send_message', {
      'tripId': tripId,
      'receiverId': receiverId,
      'text': text,
    });
    log('📤 تم إرسال الرسالة إلى $receiverId');
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
