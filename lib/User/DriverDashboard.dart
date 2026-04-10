import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/alert_service.dart';
import '../services/auth_service.dart';
import '../services/driver_socket_service.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({
    super.key,
    required this.driver,
    required this.bus,
  });

  final Map<String, dynamic> driver;
  final Map<String, dynamic> bus;

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  static const Color primaryColor = Color(0xFFFF6B35);
  static const Color backgroundColor = Colors.white;
  static const Color cardColor = Colors.white;
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const LatLng _defaultCenter = LatLng(6.9271, 79.8612);

  final DriverSocketService _socketService = DriverSocketService();
  final AlertService _alertService = AlertService();
  final List<Map<String, dynamic>> _notifications = [];
  final Completer<GoogleMapController> _mapController = Completer<GoogleMapController>();

  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  StreamSubscription<String>? _statusSubscription;

  bool _isConnecting = true;
  String _connectionStatus = 'Connecting to live updates...';
  int _unreadCount = 0;

  LatLng _busLocation = _defaultCenter;
  LatLng? _passengerLocation;
  Map<String, dynamic>? _activeNotification;
  Set<Marker> _markers = {
    const Marker(
      markerId: MarkerId('default_bus'),
      position: _defaultCenter,
      infoWindow: InfoWindow(title: 'Bus location'),
    ),
  };
  Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _primeMapFromBus();
    _connectToPassengerFeed();
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _statusSubscription?.cancel();
    _socketService.dispose();
    _alertService.dispose();
    super.dispose();
  }

  Future<void> _connectToPassengerFeed() async {
    final busId = _readValue(widget.bus, ['_id', 'id', 'busId']);
    final token = await AuthService().getToken();

    _statusSubscription = _socketService.status.listen((status) {
      if (!mounted) return;

      setState(() {
        switch (status) {
          case 'connected':
          case 'joined':
          case 'reconnected':
            _isConnecting = false;
            _connectionStatus = 'Live updates active';
            break;
          case 'disconnected':
            _isConnecting = false;
            _connectionStatus = 'Disconnected from live updates';
            break;
          case 'error':
            _isConnecting = false;
            _connectionStatus = 'Unable to connect to live updates';
            break;
          default:
            _isConnecting = true;
            _connectionStatus = 'Connecting to live updates...';
        }
      });
    });

    _notificationSubscription = _socketService.notifications.listen((payload) async {
      if (!mounted) return;

      setState(() {
        _notifications.insert(0, payload);
        _activeNotification = payload;
        _unreadCount += 1;
        _applyLivePayload(payload);
      });

      await _alertService.playPassengerAlert();
      _focusMapOnLiveEvent();
    });

    if (busId == 'N/A') {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _connectionStatus = 'Bus ID not available for realtime updates';
      });
      return;
    }

    _socketService.connect(
      busId: busId,
      token: token,
    );
  }

  void _primeMapFromBus() {
    final lat = _readDouble(widget.bus, ['lat', 'latitude', 'busLat', 'currentLat']);
    final lng = _readDouble(widget.bus, ['lng', 'longitude', 'busLng', 'currentLng']);

    if (lat != null && lng != null) {
      _busLocation = LatLng(lat, lng);
      _markers = {
        Marker(
          markerId: const MarkerId('bus'),
          position: _busLocation,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: const InfoWindow(title: 'Bus location'),
        ),
      };
    }
  }

  void _applyLivePayload(Map<String, dynamic> payload) {
    final busMap = _asMap(payload['bus']);
    final passengerMap = _asMap(payload['passenger']);

    final busLat = _readDouble(payload, ['busLat', 'busLatitude']) ??
        _readDouble(busMap, ['lat', 'latitude']);
    final busLng = _readDouble(payload, ['busLng', 'busLongitude']) ??
        _readDouble(busMap, ['lng', 'longitude']);

    final passengerLat = _readDouble(payload, ['passengerLat', 'latitude']) ??
        _readDouble(passengerMap, ['lat', 'latitude']);
    final passengerLng = _readDouble(payload, ['passengerLng', 'longitude']) ??
        _readDouble(passengerMap, ['lng', 'longitude']);

    if (busLat != null && busLng != null) {
      _busLocation = LatLng(busLat, busLng);
    }

    if (passengerLat != null && passengerLng != null) {
      _passengerLocation = LatLng(passengerLat, passengerLng);
    }

    _markers = {
      Marker(
        markerId: const MarkerId('bus'),
        position: _busLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: _readValue(widget.bus, ['regNo', 'registrationNumber', 'busNo']),
          snippet: _readValue(widget.bus, ['route', 'routeName', 'routeNo']),
        ),
      ),
      if (_passengerLocation != null)
        Marker(
          markerId: const MarkerId('passenger'),
          position: _passengerLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Passenger boarding point'),
        ),
    };

    if (_passengerLocation != null) {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('boarding_path'),
          color: primaryColor,
          width: 4,
          points: [_busLocation, _passengerLocation!],
        ),
      };
    } else {
      _polylines = {};
    }
  }

  void _focusMapOnLiveEvent() {
    if (_passengerLocation == null) return;

    _mapController.future.then((controller) {
      final passenger = _passengerLocation!;

      if (_busLocation.latitude == passenger.latitude &&
          _busLocation.longitude == passenger.longitude) {
        controller.animateCamera(
          CameraUpdate.newLatLngZoom(_busLocation, 15),
        );
        return;
      }

      controller.animateCamera(
        CameraUpdate.newLatLngBounds(_boundsFor(_busLocation, passenger), 70),
      );
    }).catchError((_) {});
  }

  LatLngBounds _boundsFor(LatLng a, LatLng b) {
    final southWest = LatLng(
      a.latitude < b.latitude ? a.latitude : b.latitude,
      a.longitude < b.longitude ? a.longitude : b.longitude,
    );
    final northEast = LatLng(
      a.latitude > b.latitude ? a.latitude : b.latitude,
      a.longitude > b.longitude ? a.longitude : b.longitude,
    );
    return LatLngBounds(southwest: southWest, northeast: northEast);
  }

  String _readValue(Map<String, dynamic>? source, List<String> keys) {
    if (source == null) return 'N/A';
    for (final key in keys) {
      final value = source[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return 'N/A';
  }

  double? _readDouble(Map<String, dynamic>? source, List<String> keys) {
    if (source == null) return null;
    for (final key in keys) {
      final value = source[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        return double.tryParse(value);
      }
    }
    return null;
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  String _formatNotificationTitle(Map<String, dynamic> payload, int index) {
    return _readValue(payload, [
      'title',
      'passengerName',
      'name',
      'userName',
      'messageType',
    ]) == 'N/A'
        ? 'Passenger Boarding #${index + 1}'
        : _readValue(payload, [
            'title',
            'passengerName',
            'name',
            'userName',
            'messageType',
          ]);
  }

  String _formatNotificationBody(Map<String, dynamic> payload) {
    return _readValue(payload, [
      'message',
      'text',
      'description',
      'details',
      'boardingMessage',
    ]);
  }

  String _formatNotificationMeta(Map<String, dynamic> payload) {
    final distance = _readValue(payload, ['distanceText', 'distance', 'distanceKm']);
    final duration = _readValue(payload, ['durationText', 'duration', 'eta', 'minutes']);
    final stopsAway = _readValue(payload, ['stopsAway', 'stops', 'stopCount']);
    final timestamp = _readValue(payload, ['timestamp', 'time', 'createdAt']);

    final parts = <String>[];
    if (distance != 'N/A') parts.add(distance);
    if (duration != 'N/A') parts.add(duration);
    if (stopsAway != 'N/A') parts.add('$stopsAway stops away');
    if (timestamp != 'N/A') parts.add(timestamp);

    return parts.isEmpty ? 'Passenger boarding update received' : parts.join(' • ');
  }

  IconData _notificationIcon(int index, Map<String, dynamic> payload) {
    final message = _formatNotificationBody(payload).toLowerCase();
    if (message.contains('distance')) return Icons.route_rounded;
    if (message.contains('stop')) return Icons.place_rounded;
    if (message.contains('board')) return Icons.directions_walk_rounded;
    if (message.contains('bus')) return Icons.directions_bus_rounded;

    const icons = <IconData>[
      Icons.notifications_active_rounded,
      Icons.directions_walk_rounded,
      Icons.directions_bus_rounded,
      Icons.place_rounded,
      Icons.route_rounded,
    ];
    return icons[index % icons.length];
  }

  Color _notificationTint(int index) {
    const colors = <Color>[
      Color(0xFFFFF0E8),
      Color(0xFFEAF7FF),
      Color(0xFFEFFAF2),
      Color(0xFFFFF8E8),
      Color(0xFFF3EEFF),
    ];
    return colors[index % colors.length];
  }

  void _markAllRead() {
    setState(() {
      _unreadCount = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final driverName = _readValue(widget.driver, ['name', 'fullName', 'driverName']);
    final driverPhone = _readValue(widget.driver, ['phone', 'phoneNumber', 'mobile']);
    final driverLicense = _readValue(widget.driver, ['licenseNumber', 'licenceNumber', 'licenseNo']);
    final driverShift = _readValue(widget.driver, ['shift', 'shiftName']);
    final driverStatus = _readValue(widget.driver, ['status', 'driverStatus']);

    final busRegNo = _readValue(widget.bus, ['regNo', 'registrationNumber', 'busNo']);
    final busRoute = _readValue(widget.bus, ['route', 'routeName', 'routeNo']);
    final busType = _readValue(widget.bus, ['type', 'busType']);
    final busId = _readValue(widget.bus, ['_id', 'id', 'busId']);

    final latestNotification = _notifications.isNotEmpty ? _notifications.first : null;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                onPressed: _notifications.isEmpty ? null : _markAllRead,
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      _unreadCount > 9 ? '9+' : '$_unreadCount',
                      style: const TextStyle(
                        color: primaryColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B35), Color(0xFFFF8A5B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Assigned Bus',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    busRegNo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Route: $busRoute',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    driverName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isConnecting ? _connectionStatus : 'Bus ID: $busId',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _statusPill(_connectionStatus),
            const SizedBox(height: 18),
            const Text(
              'Live Map',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _mapDashboardCard(busRegNo, busRoute),
            const SizedBox(height: 18),
            const Text(
              'Driver Profile',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _infoCard('Name', driverName),
            _infoCard('Phone', driverPhone),
            _infoCard('License Number', driverLicense),
            _infoCard('Shift', driverShift),
            _infoCard('Status', driverStatus),
            const SizedBox(height: 14),
            const Text(
              'Bus Details',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _infoCard('Bus Number Plate', busRegNo),
            _infoCard('Route', busRoute),
            _infoCard('Bus Type', busType),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Passenger Boarding Messages',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: _notifications.isEmpty
                      ? null
                      : () {
                          setState(() => _notifications.clear());
                        },
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (latestNotification != null) ...[
              _latestNotificationCard(latestNotification),
              const SizedBox(height: 14),
            ],
            if (_notifications.isEmpty)
              _emptyStateCard()
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _notifications.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final notification = _notifications[index];
                  return _notificationTile(notification, index);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _mapDashboardCard(String busRegNo, String busRoute) {
    return Container(
      width: double.infinity,
      height: 280,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.grey.shade200,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _passengerLocation ?? _busLocation,
                zoom: _passengerLocation == null ? 12 : 14,
              ),
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: true,
              mapToolbarEnabled: false,
              markers: _markers,
              polylines: _polylines,
              onMapCreated: (controller) {
                if (!_mapController.isCompleted) {
                  _mapController.complete(controller);
                }
              },
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.directions_bus_rounded, color: primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$busRegNo • $busRoute',
                        style: const TextStyle(
                          color: textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_passengerLocation != null)
                      const Icon(Icons.person_pin_circle_rounded, color: Colors.blue),
                  ],
                ),
              ),
            ),
            if (_activeNotification != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _formatNotificationMeta(_activeNotification!),
                    style: const TextStyle(
                      color: textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(String status) {
    final isActive = status.toLowerCase().contains('active') ||
        status.toLowerCase().contains('connected') ||
        status.toLowerCase().contains('joined');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFE8FFF1) : const Color(0xFFFFF3E8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isActive ? const Color(0xFF22C55E) : primaryColor,
        ),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: isActive ? const Color(0xFF166534) : primaryColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _emptyStateCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: const Text(
        'Waiting for passenger boarding notifications. When a passenger boards, the message, distance, stops away, and alert will appear here.',
        style: TextStyle(
          color: textSecondary,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _latestNotificationCard(Map<String, dynamic> notification) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primaryColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_rounded, color: primaryColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _formatNotificationTitle(notification, 0),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _formatNotificationBody(notification),
            style: const TextStyle(
              color: textPrimary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _formatNotificationMeta(notification),
            style: const TextStyle(
              color: textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notificationTile(Map<String, dynamic> notification, int index) {
    final title = _formatNotificationTitle(notification, index);
    final body = _formatNotificationBody(notification);
    final meta = _formatNotificationMeta(notification);
    final icon = _notificationIcon(index, notification);
    final tint = _notificationTint(index);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: index == 0 ? primaryColor.withValues(alpha: 0.22) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: primaryColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
              ),
              if (index == 0)
                const Icon(Icons.fiber_new_rounded, color: primaryColor, size: 20),
            ],
          ),
          if (body != 'N/A') ...[
            const SizedBox(height: 8),
            Text(
              body,
              style: const TextStyle(
                color: textPrimary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            meta,
            style: const TextStyle(
              color: textSecondary,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(String title, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
