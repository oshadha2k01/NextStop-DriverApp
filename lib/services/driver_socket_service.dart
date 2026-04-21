import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/api_config.dart';

class DriverSocketService {
  io.Socket? _socket;
  final StreamController<Map<String, dynamic>> _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _statusController =
      StreamController<String>.broadcast();

  Stream<Map<String, dynamic>> get notifications => _notificationController.stream;
  Stream<String> get status => _statusController.stream;

  void connect({
    required String busId,
    String? token,
  }) {
    disconnect();

    _statusController.add('connecting');

    _socket = io.io(
      ApiConfig.socketUrl,
      io.OptionBuilder()
          .disableAutoConnect()
          .setPath(ApiConfig.socketPath)
          .setTransports(['websocket'])
          .enableReconnection()
          .setReconnectionAttempts(20)
          .setReconnectionDelay(2000)
          .setAuth({'token': token ?? ''})
          .setExtraHeaders({
            if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          })
          .build(),
    );

    _socket!.onConnect((_) {
      _statusController.add('connected');
      _socket!.emit('driver_join', {'busId': busId});
    });

    _socket!.on('driver_joined', (data) {
      _statusController.add('joined');
      debugPrint('driver_joined: $data');
    });

    _socket!.on('passenger_boarding', (payload) {
      debugPrint('passenger_boarding raw: $payload');
      final notification = _asMap(payload);
      if (notification != null) {
        _notificationController.add(notification);
      } else if (payload != null) {
        _notificationController.add({
          'message': payload.toString(),
          'rawPayload': payload,
        });
      }
    });

    _socket!.onReconnect((_) {
      _statusController.add('reconnected');
      _socket?.emit('driver_join', {'busId': busId});
    });

    _socket!.onDisconnect((_) {
      _statusController.add('disconnected');
    });

    _socket!.onConnectError((error) {
      _statusController.add('error');
      debugPrint('Driver socket connect error: $error');
    });

    _socket!.onError((error) {
      _statusController.add('error');
      debugPrint('Driver socket error: $error');
    });

    _socket!.connect();
  }

  Map<String, dynamic>? _asMap(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    if (payload is Map) {
      return Map<String, dynamic>.from(payload);
    }
    return null;
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  void dispose() {
    disconnect();
    _notificationController.close();
    _statusController.close();
  }
}