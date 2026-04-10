import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _tokenKey = 'auth_token';
  static const String _userTypeKey = 'user_type';
  static const String _userIdKey = 'user_id';
  static const String _driverDataKey = 'driver_data';
  static const String _busDataKey = 'bus_data';

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<bool> isAuthenticated() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> saveUserType(String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userTypeKey, type);
  }

  Future<String?> getUserType() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userTypeKey);
  }

  Future<void> saveUserId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, id);
  }

  Future<void> saveDriverData(Map<String, dynamic> driver) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_driverDataKey, jsonEncode(driver));
  }

  Future<void> saveBusData(Map<String, dynamic> bus) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_busDataKey, jsonEncode(bus));
  }

  Future<Map<String, dynamic>?> getDriverData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_driverDataKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  Future<Map<String, dynamic>?> getBusData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_busDataKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  Future<void> saveDriverSession({
    required String token,
    required Map<String, dynamic> driver,
    required Map<String, dynamic> bus,
  }) async {
    await saveToken(token);
    await saveUserType('driver');
    final driverId = (driver['id'] ?? driver['_id'])?.toString();
    if (driverId != null && driverId.isNotEmpty) {
      await saveUserId(driverId);
    }
    await saveDriverData(driver);
    await saveBusData(bus);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userTypeKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_driverDataKey);
    await prefs.remove(_busDataKey);
  }
}
