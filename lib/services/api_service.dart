import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../config/api_config.dart';
import 'auth_service.dart';

class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? errorMessage;
  final int? statusCode;

  ApiResponse({
    required this.success,
    this.data,
    this.errorMessage,
    this.statusCode,
  });
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  Future<bool> _hasInternetConnection() async {
    final result = await Connectivity().checkConnectivity();
    if (result is List) {
      return !(result as List).contains(ConnectivityResult.none);
    }
    return result != ConnectivityResult.none;
  }

  Future<Map<String, String>> _buildHeaders({bool requiresAuth = false}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (requiresAuth) {
      final token = await AuthService().getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  Future<ApiResponse<Map<String, dynamic>>> get(
    String url, {
    bool requiresAuth = false,
    Map<String, String>? queryParams,
  }) async {
    if (!await _hasInternetConnection()) {
      return ApiResponse(
        success: false,
        errorMessage: 'No internet connection. Please check your network.',
      );
    }

    try {
      Uri uri = Uri.parse(url);
      if (queryParams != null && queryParams.isNotEmpty) {
        uri = uri.replace(queryParameters: queryParams);
      }

      final headers = await _buildHeaders(requiresAuth: requiresAuth);
      final response = await http
          .get(uri, headers: headers)
          .timeout(ApiConfig.requestTimeout);

      return _handleResponse(response);
    } on TimeoutException {
      return ApiResponse(
        success: false,
        errorMessage: 'Request timed out. Please try again.',
      );
    } on SocketException {
      return ApiResponse(
        success: false,
        errorMessage: 'Cannot reach server. Please try again later.',
      );
    } on FormatException {
      return ApiResponse(
        success: false,
        errorMessage: 'Invalid response from server.',
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        errorMessage: 'An unexpected error occurred: ${e.toString()}',
      );
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> post(
    String url, {
    Map<String, dynamic>? body,
    bool requiresAuth = false,
  }) async {
    if (!await _hasInternetConnection()) {
      return ApiResponse(
        success: false,
        errorMessage: 'No internet connection. Please check your network.',
      );
    }

    try {
      final headers = await _buildHeaders(requiresAuth: requiresAuth);
      final response = await http
          .post(
            Uri.parse(url),
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(ApiConfig.requestTimeout);

      return _handleResponse(response);
    } on TimeoutException {
      return ApiResponse(
        success: false,
        errorMessage: 'Request timed out. Please try again.',
      );
    } on SocketException {
      return ApiResponse(
        success: false,
        errorMessage: 'Cannot reach server. Please try again later.',
      );
    } on FormatException {
      return ApiResponse(
        success: false,
        errorMessage: 'Invalid response from server.',
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        errorMessage: 'An unexpected error occurred: ${e.toString()}',
      );
    }
  }

  Future<ApiResponse<Map<String, dynamic>>> put(
    String url, {
    Map<String, dynamic>? body,
    bool requiresAuth = false,
  }) async {
    if (!await _hasInternetConnection()) {
      return ApiResponse(
        success: false,
        errorMessage: 'No internet connection. Please check your network.',
      );
    }

    try {
      final headers = await _buildHeaders(requiresAuth: requiresAuth);
      final response = await http
          .put(
            Uri.parse(url),
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(ApiConfig.requestTimeout);

      return _handleResponse(response);
    } on TimeoutException {
      return ApiResponse(
        success: false,
        errorMessage: 'Request timed out. Please try again.',
      );
    } on SocketException {
      return ApiResponse(
        success: false,
        errorMessage: 'Cannot reach server. Please try again later.',
      );
    } on FormatException {
      return ApiResponse(
        success: false,
        errorMessage: 'Invalid response from server.',
      );
    } catch (e) {
      return ApiResponse(
        success: false,
        errorMessage: 'An unexpected error occurred: ${e.toString()}',
      );
    }
  }

  ApiResponse<Map<String, dynamic>> _handleResponse(http.Response response) {
    try {
      final Map<String, dynamic> body = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResponse(
          success: true,
          data: body,
          statusCode: response.statusCode,
        );
      } else {
        final errorMsg = body['message'] ?? body['error'] ?? 'Request failed';
        return ApiResponse(
          success: false,
          data: body,
          errorMessage: errorMsg.toString(),
          statusCode: response.statusCode,
        );
      }
    } on FormatException {
      return ApiResponse(
        success: false,
        errorMessage: 'Invalid response format from server.',
        statusCode: response.statusCode,
      );
    }
  }
  
}
