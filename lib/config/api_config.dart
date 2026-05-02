class ApiConfig {
  static const String baseUrl = 'https://smartbusstop.me/backend/api';
  static const String socketUrl = 'https://smartbusstop.me';
 static const String socketPath = '/backend/socket.io';
  static const Duration requestTimeout = Duration(seconds: 15);
  // Optional: Google Directions API key (set to non-empty to enable route fetching)
  // Get a key from https://console.cloud.google.com/apis/credentials and enable Directions API
  static const String googleDirectionsKey = 'AIzaSyBmgWCSt6zznmFD1XiuzKMW4gaxO5LANUc';
//static const String baseUrl = 'http://192.168.8.118:5000/api';
 // static const String socketUrl = 'http://192.168.8.118:5000';
  //static const String socketPath = '/socket.io';
  // Auth endpoints
  static const String driverLogin = '$baseUrl/drivers/login';
  static const String driverRegister = '$baseUrl/drivers/register';
  static const String passengerRegister = '$baseUrl/passengers/register';
  static const String verifyOtp = '$baseUrl/drivers/verify-otp';
  static const String resendOtp = '$baseUrl/drivers/resend-otp';

  // Route endpoints
  static const String routes = '$baseUrl/routes';

  // Bus endpoints
  static const String buses = '$baseUrl/buses';
  static const String busTripStatus = '$buses/trip-status';
  static const String busDevice = '$baseUrl/bus-device';

  // Prediction endpoints (ML)
  static const String crowdPrediction = '$baseUrl/predict/route-predict';
  static const String destinationPrediction = '$baseUrl/destination/predict';

  // Fare endpoint
  static const String fareCalculation = '$baseUrl/fare/calculate';

  // Notifications
  static const String notify = '$baseUrl/notify/board';

  // Dashboard
  static const String dashboard = '$baseUrl/dashboard';
}
