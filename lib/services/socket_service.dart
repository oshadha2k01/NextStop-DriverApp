import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/api_config.dart';
import 'auth_service.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  bool _isConnected = false;

  bool get isConnected => _isConnected;
  IO.Socket? get socket => _socket;

  Future<void> connect() async {
    if (_isConnected && _socket != null) return;

    final token = await AuthService().getToken();

    _socket = IO.io(
      ApiConfig.socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setPath(ApiConfig.socketPath)
          .disableAutoConnect()
          .setAuth({'token': token ?? ''})
          .build(),
    );

    _socket!.onConnect((_) {
      _isConnected = true;
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
    });

    _socket!.onConnectError((error) {
      _isConnected = false;
    });

    _socket!.connect();
  }

  void on(String event, Function(dynamic) callback) {
    _socket?.on(event, callback);
  }

  void emit(String event, [dynamic data]) {
    _socket?.emit(event, data);
  }

  void off(String event) {
    _socket?.off(event);
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
  }
}
