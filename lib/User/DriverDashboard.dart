import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/api_config.dart';
import '../services/api_service.dart';
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
  static const Color backgroundColor = Color(0xFFFFFAF7);
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const LatLng _defaultCenter = LatLng(6.9271, 79.8612);

  final DriverSocketService _socketService = DriverSocketService();
  final AlertService _alertService = AlertService();
  final List<Map<String, dynamic>> _notifications = [];
  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();
  final Map<String, String> _locationNameCache = {};
  bool _ackInProgress = false;

  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  StreamSubscription<String>? _statusSubscription;

  bool _isConnecting = true;
  bool _soundEnabled = true;
  bool _isTripActive = false;

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

    _notificationSubscription =
        _socketService.notifications.listen((payload) async {
      if (!mounted) return;

      setState(() {
        _notifications.insert(0, payload);
        _activeNotification = payload;
        _unreadCount += 1;
        _applyLivePayload(payload);
      });

      if (_soundEnabled) {
        await _alertService.playPassengerAlert();
      }

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

    _socketService.connect(busId: busId, token: token);
  }

  Future<void> _manualReconnect(String busId) async {
    final token = await AuthService().getToken();
    if (!mounted) return;

    setState(() {
      _isConnecting = true;
      _connectionStatus = 'Connecting to live updates...';
    });

    _socketService.connect(busId: busId, token: token);
  }

  void _manualDisconnect() {
    _socketService.disconnect();
    if (!mounted) return;

    setState(() {
      _isConnecting = false;
      _connectionStatus = 'Disconnected from live updates';
    });
  }

  void _primeMapFromBus() {
    final lat =
        _readDouble(widget.bus, ['lat', 'latitude', 'busLat', 'currentLat']);
    final lng =
        _readDouble(widget.bus, ['lng', 'longitude', 'busLng', 'currentLng']);

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

    final busLocation = _extractLatLng(
          payload,
          latitudeKeys: const ['busLat', 'busLatitude', 'currentLat', 'currentLatitude', 'lat', 'latitude'],
          longitudeKeys: const ['busLng', 'busLongitude', 'currentLng', 'currentLongitude', 'lng', 'longitude'],
          nestedKeys: const ['bus', 'vehicle', 'busLocation', 'currentBus', 'location'],
        ) ??
        _extractLatLng(
          busMap,
          latitudeKeys: const ['lat', 'latitude'],
          longitudeKeys: const ['lng', 'longitude'],
        );

    final passengerLocation = _extractLatLng(
          payload,
          latitudeKeys: const ['passengerLat', 'passengerLatitude', 'pickupLat', 'pickupLatitude', 'stopLat', 'stopLatitude', 'lat', 'latitude'],
          longitudeKeys: const ['passengerLng', 'passengerLongitude', 'pickupLng', 'pickupLongitude', 'stopLng', 'stopLongitude', 'lng', 'longitude'],
          nestedKeys: const ['passenger', 'passengerLocation', 'pickupLocation', 'boardingPoint', 'busStop', 'stop', 'location'],
        ) ??
        _extractLatLng(
          passengerMap,
          latitudeKeys: const ['lat', 'latitude'],
          longitudeKeys: const ['lng', 'longitude'],
        );

    if (busLocation != null) {
      _busLocation = busLocation;
    }

    if (passengerLocation != null) {
      _passengerLocation = passengerLocation;
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
          infoWindow: InfoWindow(
            title: _readValue(
              payload,
              ['passengerLocationName', 'pickupLocationName', 'boardingPointName', 'stopName', 'busStopName'],
            ),
            snippet: _readValue(
              payload,
              ['message', 'text', 'description', 'details', 'boardingMessage'],
            ),
          ),
        ),
    };

    if (_passengerLocation != null) {
      // If payload contains an encoded route/polyline, decode and display it.
      final encoded = _findEncodedPolyline(payload);
      if (encoded != null && encoded.isNotEmpty) {
        final points = _decodePolyline(encoded);
        if (points.isNotEmpty) {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('boarding_path'),
              color: primaryColor,
              width: 4,
              points: points,
            ),
          };
        } else {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('boarding_path'),
              color: primaryColor,
              width: 4,
              points: [_busLocation, _passengerLocation!],
            ),
          };
        }
      } else {
        _polylines = {
          Polyline(
            polylineId: const PolylineId('boarding_path'),
            color: primaryColor,
            width: 4,
            points: [_busLocation, _passengerLocation!],
          ),
        };
        // If we don't have an encoded route, try fetching a route from Directions API (if configured)
        _fetchRouteFromDirectionsIfAvailable(_busLocation, _passengerLocation!);
      }

      // Kick off reverse geocode to obtain a readable location name for the passenger
      final key = '${_passengerLocation!.latitude.toStringAsFixed(5)},${_passengerLocation!.longitude.toStringAsFixed(5)}';
      if (!_locationNameCache.containsKey(key)) {
        _reverseGeocode(_passengerLocation!).then((name) {
          if (name != null && name.isNotEmpty) {
            setState(() {
              _locationNameCache[key] = name;
            });
          }
        });
      }
    } else {
      _polylines = {};
    }
  }

  LatLng? _extractLatLng(
    Map<String, dynamic>? source, {
    required List<String> latitudeKeys,
    required List<String> longitudeKeys,
    List<String> nestedKeys = const [],
  }) {
    if (source == null) return null;

    final lat = _readDouble(source, latitudeKeys);
    final lng = _readDouble(source, longitudeKeys);
    if (lat != null && lng != null) {
      return LatLng(lat, lng);
    }

    final coordinates = source['coordinates'];
    if (coordinates is List && coordinates.length >= 2) {
      final first = coordinates[0];
      final second = coordinates[1];
      final maybeLng = first is num ? first.toDouble() : double.tryParse(first.toString());
      final maybeLat = second is num ? second.toDouble() : double.tryParse(second.toString());
      if (maybeLat != null && maybeLng != null) {
        return LatLng(maybeLat, maybeLng);
      }
    }

    final location = _asMap(source['location']);
    if (location != null) {
      final nestedLat = _readDouble(location, latitudeKeys) ?? _readDouble(location, const ['lat', 'latitude']);
      final nestedLng = _readDouble(location, longitudeKeys) ?? _readDouble(location, const ['lng', 'longitude']);
      if (nestedLat != null && nestedLng != null) {
        return LatLng(nestedLat, nestedLng);
      }

      final nestedCoordinates = location['coordinates'];
      if (nestedCoordinates is List && nestedCoordinates.length >= 2) {
        final first = nestedCoordinates[0];
        final second = nestedCoordinates[1];
        final maybeLng = first is num ? first.toDouble() : double.tryParse(first.toString());
        final maybeLat = second is num ? second.toDouble() : double.tryParse(second.toString());
        if (maybeLat != null && maybeLng != null) {
          return LatLng(maybeLat, maybeLng);
        }
      }
    }

    for (final key in nestedKeys) {
      final nested = _asMap(source[key]);
      if (nested == null) continue;

      final nestedLat = _readDouble(nested, latitudeKeys) ?? _readDouble(nested, const ['lat', 'latitude']);
      final nestedLng = _readDouble(nested, longitudeKeys) ?? _readDouble(nested, const ['lng', 'longitude']);
      if (nestedLat != null && nestedLng != null) {
        return LatLng(nestedLat, nestedLng);
      }

      final nestedCoordinates = nested['coordinates'];
      if (nestedCoordinates is List && nestedCoordinates.length >= 2) {
        final first = nestedCoordinates[0];
        final second = nestedCoordinates[1];
        final maybeLng = first is num ? first.toDouble() : double.tryParse(first.toString());
        final maybeLat = second is num ? second.toDouble() : double.tryParse(second.toString());
        if (maybeLat != null && maybeLng != null) {
          return LatLng(maybeLat, maybeLng);
        }
      }
    }

    return null;
  }

  String? _findEncodedPolyline(Map<String, dynamic> payload) {
    // Common keys that may contain encoded polylines
    const candidates = [
      'encodedPolyline',
      'polyline',
      'overview_polyline',
      'routePolyline',
      'encoded',
      'path',
    ];

    for (final key in candidates) {
      final v = payload[key];
      if (v is String && v.length > 10) return v;
      if (v is Map && v['points'] is String && (v['points'] as String).length > 10) {
        return v['points'] as String;
      }
    }

    // Also check nested objects like payload['route']
    for (final entry in payload.entries) {
      final v = entry.value;
      if (v is Map) {
        for (final key in candidates) {
          final nested = v[key];
          if (nested is String && nested.length > 10) return nested;
          if (nested is Map && nested['points'] is String && (nested['points'] as String).length > 10) {
            return nested['points'] as String;
          }
        }
      }
    }

    return null;
  }

  Future<void> _fetchRouteFromDirectionsIfAvailable(LatLng origin, LatLng dest) async {
    final key = ApiConfig.googleDirectionsKey;
    if (key == null || key.isEmpty) return;

    try {
      final url = 'https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${dest.latitude},${dest.longitude}&key=$key&mode=driving&alternatives=false';
      final resp = await ApiService().get(url);
      if (!resp.success || resp.data == null) return;
      final routes = resp.data!['routes'];
      if (routes is List && routes.isNotEmpty) {
        final overview = routes[0]['overview_polyline'];
        if (overview != null && overview['points'] is String) {
          final decoded = _decodePolyline(overview['points'] as String);
          if (decoded.isNotEmpty) {
            setState(() => _polylines = {
                  Polyline(
                    polylineId: const PolylineId('boarding_path'),
                    color: primaryColor,
                    width: 4,
                    points: decoded,
                  ),
                });
        }
      }
    }
    } catch (e) {
      debugPrint('Directions fetch failed: $e');
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      final latitude = lat / 1E5;
      final longitude = lng / 1E5;
      points.add(LatLng(latitude, longitude));
    }

    return points;
  }

  Future<String?> _reverseGeocode(LatLng pos) async {
    try {
      final url = 'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${pos.latitude}&lon=${pos.longitude}';
      final resp = await ApiService().get(url);
      if (resp.success && resp.data != null) {
        final display = resp.data!['display_name'];
        if (display != null && display.toString().trim().isNotEmpty) return display.toString();
      }
    } catch (_) {}
    return '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
  }

  Future<void> _acknowledgeNotification(Map<String, dynamic> notification) async {
    if (_ackInProgress) return;
    setState(() => _ackInProgress = true);

    // Try to find an identifier in the notification
    final idCandidates = ['id', '_id', 'notificationId', 'notifId'];
    String? notifId;
    for (final k in idCandidates) {
      final v = notification[k];
      if (v != null) {
        notifId = v.toString();
        break;
      }
    }

    final body = <String, dynamic>{
      // include multiple likely fields so backend accepts the request
      if (notifId != null) 'notificationId': notifId,
      'status': 'acknowledged',
      'action': 'driver_ack',
    };

    // include passenger id if available
    final passengerId = notification['passenger'] is Map ? (notification['passenger']['_id'] ?? notification['passenger']['id']) : (notification['passengerId'] ?? notification['passenger_id']);
    if (passengerId != null) body['passengerId'] = passengerId;

    // also send bus id if available
    final busId = _readValue(notification, ['busId', 'bus_id', 'busId', 'bus', '_id']);
    if (busId != 'N/A') body['busId'] = busId;

    final response = await ApiService().post(ApiConfig.notify, body: body, requiresAuth: true);

    if (!mounted) return;
    setState(() => _ackInProgress = false);

    if (response.success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Acknowledged')));
      setState(() {
        _activeNotification = null;
        _unreadCount = 0;
      });
    } else {
      // Log detailed response to help debug backend contract issues
      debugPrint('Acknowledge failed: ${response.statusCode} ${response.errorMessage} ${response.data}');
      final err = response.errorMessage ?? 'Failed to acknowledge';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  void _focusMapOnLiveEvent() {
    if (_passengerLocation == null) return;

    _mapController.future.then((controller) {
      final passenger = _passengerLocation!;
      if (_busLocation.latitude == passenger.latitude &&
          _busLocation.longitude == passenger.longitude) {
        controller.animateCamera(CameraUpdate.newLatLngZoom(_busLocation, 15));
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
      if (value is String) return double.tryParse(value);
    }
    return null;
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  String _formatNotificationTitle(Map<String, dynamic> payload, int index) {
    final value = _readValue(payload, [
      'title',
      'passengerName',
      'name',
      'userName',
      'messageType',
    ]);
    return value == 'N/A' ? 'Passenger Boarding #${index + 1}' : value;
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

  void _markAllRead() {
    setState(() {
      _unreadCount = 0;
    });
  }

  void _dismissActiveNotification() {
    setState(() {
      _activeNotification = null;
      _unreadCount = 0;
    });
  }

  Future<void> _testSound() async {
    await _alertService.playPassengerAlert();
  }

  Future<void> _toggleTripStatus() async {
    final busId = _readValue(widget.bus, [
      'regNo',
      'registrationNumber',
      'busNo',
      'device_id',
      'deviceId',
    ]);
    if (busId == 'N/A') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to determine bus identifier for trip status update.'),
        ),
      );
      return;
    }

    final nextStatus = !_isTripActive;
    final response = await ApiService().put(
      ApiConfig.busTripStatus,
      body: {
        'busId': busId,
        'isActive': nextStatus,
      },
      requiresAuth: true,
    );

    if (!mounted) return;

    if (response.success) {
      setState(() {
        _isTripActive = nextStatus;
      });

      final message = nextStatus
          ? 'Trip started successfully.'
          : 'Trip ended successfully.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } else {
      final errorMessage = response.errorMessage ??
          'Unable to update trip status. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final driverName = _readValue(widget.driver, ['name', 'fullName', 'driverName']);
    final busRegNo = _readValue(widget.bus, ['regNo', 'registrationNumber', 'busNo']);
    final busRoute = _readValue(widget.bus, ['route', 'routeName', 'routeNo']);
    final busId = _readValue(widget.bus, ['_id', 'id', 'busId']);
    final showDashboardChrome = _activeNotification == null;

    final isDesktop = MediaQuery.of(context).size.width >= 980;
    final isConnected = !_isConnecting && (
      _connectionStatus.toLowerCase().contains('active') ||
      _connectionStatus.toLowerCase().contains('connected') ||
      _connectionStatus.toLowerCase().contains('joined')
    );

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                final offsetAnimation = Tween<Offset>(
                  begin: const Offset(0, -0.08),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: offsetAnimation,
                    child: child,
                  ),
                );
              },
              child: showDashboardChrome
                  ? Column(
                      key: const ValueKey('dashboard_chrome_visible'),
                      children: [
                        _topBar(driverName, isConnected),
                        _setupPanel(busRegNo, busRoute, busId),
                      ],
                    )
                  : const SizedBox.shrink(key: ValueKey('dashboard_chrome_hidden')),
            ),
            Expanded(
              child: isDesktop
                  ? Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 12, 16),
                            child: _mapDashboardCard(busRegNo, busRoute),
                          ),
                        ),
                        SizedBox(
                          width: 360,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 16, 16),
                            child: _sidebarPanel(),
                          ),
                        ),
                      ],
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        children: [
                          Expanded(flex: 8, child: _mapDashboardCard(busRegNo, busRoute)),
                          const SizedBox(height: 12),
                          Expanded(flex: 5, child: _sidebarPanel()),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(String driverName, bool isConnected) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B35), Color(0xFFFF8A5B)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'NextStop',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                'Driver Dashboard • $driverName',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Row(
            children: [
              if (_unreadCount > 0)
                Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    _unreadCount > 99 ? '99+' : '$_unreadCount',
                    style: const TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: isConnected
                        ? const Color(0xFF30B857)
                        : const Color(0xFFFFA37A),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 9,
                      color: isConnected ? const Color(0xFF30B857) : primaryColor,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      isConnected ? 'Connected' : 'Disconnected',
                      style: TextStyle(
                        color:
                            isConnected ? const Color(0xFF1F7A3D) : primaryColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _setupPanel(String busRegNo, String busRoute, String busId) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4EE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFFD4C1)),
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _chipField(Icons.directions_bus_filled_rounded, 'Bus', busRegNo),
            _chipField(Icons.route_rounded, 'Route', busRoute),
            _chipField(Icons.badge_rounded, 'Bus ID', busId),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: busId == 'N/A' ? null : () => _manualReconnect(busId),
              icon: const Icon(Icons.link_rounded),
              label: const Text('Connect'),
            ),
            OutlinedButton.icon(
              onPressed: _manualDisconnect,
              icon: const Icon(Icons.link_off_rounded),
              label: const Text('Disconnect'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipField(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFDCCB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: primaryColor),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: const TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapDashboardCard(String busRegNo, String busRoute) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFFFFF4EE),
        border: Border.all(color: const Color(0xFFFFD9C8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFE2D4)),
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
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_passengerLocation != null)
                      const Icon(Icons.person_pin_circle_rounded,
                          color: Color(0xFF0EA5E9)),
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
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFE2D4)),
                  ),
                  child: Text(
                    _formatNotificationMeta(_activeNotification!),
                    style: const TextStyle(
                      color: textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sidebarPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFDCCB)),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _tripToggleCard(),
                  if (_activeNotification != null)
                    _activeNotificationCard(_activeNotification!)
                  else
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8F4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFE2D4)),
                      ),
                      child: const Text(
                        'Waiting for passenger boarding notifications...',
                        style: TextStyle(
                          color: textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  if (_notifications.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Column(
                        children: List.generate(
                          _notifications.length,
                          (index) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _historyTile(_notifications[index], index),
                          ),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: const Text(
                        'No notification history yet.',
                        style: TextStyle(color: textSecondary, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFFFE2D4))),
            ),
            child: Row(
              children: [
                const Icon(Icons.volume_up_rounded,
                    size: 18, color: textSecondary),
                const SizedBox(width: 8),
                const Text(
                  'Alert Sound',
                  style: TextStyle(color: textSecondary, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Switch(
                  value: _soundEnabled,
                  activeThumbColor: primaryColor,
                  onChanged: (value) {
                    setState(() {
                      _soundEnabled = value;
                    });
                  },
                ),
                TextButton(
                  onPressed: _testSound,
                  child: const Text('Test'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tripToggleCard() {
    final buttonLabel = _isTripActive ? 'End Trip' : 'Start Trip';
    final buttonColor = _isTripActive ? Colors.red : Colors.green;
    final buttonIcon = _isTripActive ? Icons.stop_circle_rounded : Icons.play_circle_rounded;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8F4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFE2D4)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Trip Control',
              style: TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: buttonColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _toggleTripStatus,
                icon: Icon(buttonIcon, size: 22),
                label: Text(
                  buttonLabel,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeNotificationCard(Map<String, dynamic> notification) {
    final passengerLocation = _extractLatLng(
      notification,
      latitudeKeys: const ['passengerLat', 'passengerLatitude', 'pickupLat', 'pickupLatitude', 'stopLat', 'stopLatitude', 'lat', 'latitude'],
      longitudeKeys: const ['passengerLng', 'passengerLongitude', 'pickupLng', 'pickupLongitude', 'stopLng', 'stopLongitude', 'lng', 'longitude'],
      nestedKeys: const ['passenger', 'passengerLocation', 'pickupLocation', 'boardingPoint', 'busStop', 'stop', 'location'],
    );
    final busLocation = _extractLatLng(
      notification,
      latitudeKeys: const ['busLat', 'busLatitude', 'currentLat', 'currentLatitude', 'lat', 'latitude'],
      longitudeKeys: const ['busLng', 'busLongitude', 'currentLng', 'currentLongitude', 'lng', 'longitude'],
      nestedKeys: const ['bus', 'vehicle', 'busLocation', 'currentBus', 'location'],
    );
    final passengerLocationName = _readValue(notification, [
      'passengerLocationName',
      'pickupLocationName',
      'boardingPointName',
      'stopName',
      'busStopName',
      'locationName',
    ]);
    final busLocationName = _readValue(notification, [
      'busLocationName',
      'busStopName',
      'stopName',
      'locationName',
    ]);

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAF7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFC8AF), width: 1.8),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFFFEFE6),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Passenger Boarding Request',
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                if (_unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'NEW',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _detailLine(
                  Icons.message_rounded,
                  'Passenger Message',
                  _formatNotificationBody(notification),
                  highlight: true,
                ),
                _detailLine(
                  Icons.route_rounded,
                  'Road Distance',
                  _readValue(notification, ['distanceText', 'distance', 'distanceKm']),
                  highlight: true,
                ),
                _detailLine(
                  Icons.schedule_rounded,
                  'Estimated Arrival',
                  _readValue(
                    notification,
                    ['durationText', 'duration', 'eta', 'minutes'],
                  ),
                  highlight: true,
                ),
                _detailLine(
                  Icons.pin_drop_rounded,
                  'Passenger Location',
                  passengerLocation != null
                    ? (_locationNameCache['${passengerLocation.latitude.toStringAsFixed(5)},${passengerLocation.longitude.toStringAsFixed(5)}'] ??
                      passengerLocationName
                          .replaceFirst(RegExp(r'^N/A$'), '${passengerLocation.latitude.toStringAsFixed(5)}, ${passengerLocation.longitude.toStringAsFixed(5)}'))
                    : passengerLocationName,
                ),
                _detailLine(
                  Icons.directions_bus_filled_rounded,
                  'Bus Location',
                  busLocation != null
                      ? '${busLocation.latitude.toStringAsFixed(5)}, ${busLocation.longitude.toStringAsFixed(5)}'
                      : busLocationName,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _ackInProgress ? null : () => _acknowledgeNotification(notification),
                        child: _ackInProgress ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Acknowledge'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _dismissActiveNotification,
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(
    IconData icon,
    String label,
    String value, {
    bool highlight = false,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE5D9)),
      ),
      child: Row(
        children: [
          Icon(icon, color: primaryColor, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value == 'N/A' ? '—' : value,
                  style: TextStyle(
                    color: highlight ? primaryColor : textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: highlight ? 14.5 : 13.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(Map<String, dynamic> notification, int index) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE1D3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEFE5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: primaryColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _formatNotificationTitle(notification, index),
                  style: const TextStyle(
                    color: textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatNotificationBody(notification),
            style: const TextStyle(
              color: Color(0xFF0EA5E9),
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatNotificationMeta(notification),
            style: const TextStyle(
              color: textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
