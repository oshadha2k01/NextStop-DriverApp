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
  static const Color primaryDark = Color(0xFFE85A28);
  static const Color accentColor = Color(0xFFFFA36C);
  static const Color backgroundColor = Colors.white;
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);

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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(
            color: textPrimary,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(icon, color: primaryColor),
            filled: true,
            fillColor: const Color(0xFFFFF7F3),
            hintStyle: const TextStyle(color: textSecondary),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: primaryColor.withOpacity(0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: primaryColor, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: backgroundColor,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFF7F3),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.28),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Welcome back, Driver',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in with your license and phone number to continue to your dashboard.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: primaryColor.withOpacity(0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 28,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTextField(
                        controller: _licenseController,
                        label: 'License Number',
                        hintText: 'Enter license number',
                        icon: Icons.badge_outlined,
                      ),
                      const SizedBox(height: 18),
                      _buildTextField(
                        controller: _phoneController,
                        label: 'Phone Number',
                        hintText: 'Enter phone number',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 26),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _onLoginPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: _isLoading
                                ? const SizedBox(
                                    key: ValueKey('loading'),
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  )
                                : const Text(
                                    'Login',
                                    key: ValueKey('login'),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Use the same credentials issued by the NextStop Super Admin Team.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textSecondary.withOpacity(0.95),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
