import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'DriverDashboard.dart';

class DriverLoginScreen extends StatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  State<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  static const Color primaryColor = Color(0xFFFF6B35);
  static const Color backgroundColor = Colors.white;
  static const Color textPrimary = Color(0xFF1F2937);

  final TextEditingController _licenseController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  @override
  void dispose() {
    _licenseController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  Future<void> _restoreSession() async {
    try {
      final token = await AuthService().getToken();
      final driver = await AuthService().getDriverData();
      final bus = await AuthService().getBusData();

      if (!mounted || token == null || token.isEmpty || driver == null || bus == null) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DriverDashboardScreen(
              driver: driver,
              bus: bus,
            ),
          ),
        );
      });
    } catch (e) {
      print('Error restoring session: $e');
    }
  }

  Future<void> _onLoginPressed() async {
    final licenseNumber = _licenseController.text.trim();
    final phoneNumber = _phoneController.text.trim();

    if (licenseNumber.isEmpty || phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter license number and phone number')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await ApiService().post(
        ApiConfig.driverLogin,
        body: {
          'licenseNumber': licenseNumber,
          'licenceNumber': licenseNumber,
          'phoneNumber': phoneNumber,
          'phone': phoneNumber,
        },
      );

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (!response.success || response.data == null) {
        final statusCode = response.statusCode;
        final message = statusCode == 401
            ? 'Invalid license number or phone number'
            : statusCode == 403
                ? 'Driver has no assigned bus'
                : response.errorMessage ?? 'Driver login failed';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        return;
      }

      final root = response.data!;
      final payload = _asMap(root['data']) ?? root;
      final driver = _asMap(payload['driver']) ?? _asMap(root['driver']);
      final bus = _asMap(payload['bus']) ?? _asMap(root['bus']);

      final token = (payload['token'] ?? root['token'] ?? payload['accessToken'] ?? root['accessToken'])?.toString();

      if (driver == null || bus == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login succeeded but profile data is missing')),
        );
        return;
      }

      if (token != null && token.isNotEmpty) {
        await AuthService().saveDriverSession(
          token: token,
          driver: driver,
          bus: bus,
        );
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => DriverDashboardScreen(
            driver: driver,
            bus: bus,
          ),
        ),
      );
    } catch (e) {
      print('Login error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(title: const Text('Driver Login')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('License Number'),
            const SizedBox(height: 8),
            TextField(
              controller: _licenseController,
              decoration: InputDecoration(
                hintText: 'Enter license number',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Phone Number'),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: 'Enter phone number',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _onLoginPressed,
                style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Text('Login', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
