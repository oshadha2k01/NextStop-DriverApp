import 'dart:async';

import 'package:flutter/material.dart';

import 'User/DriverLogin.dart';

Future<void> main() async {
  // 1. This MUST be the first line
  WidgetsFlutterBinding.ensureInitialized();
  
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrintStack(label: 'FLUTTER ERROR', stackTrace: details.stack);
    print('Exception: ${details.exception}');
  };
  
  runZonedGuarded(
    () => runApp(const MyApp()),
    (Object error, StackTrace stack) {
      debugPrintStack(label: 'ZONE ERROR', stackTrace: stack);
      print('Error: $error');
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NextStop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.orange,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Color(0xFFFF6B35),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      initialRoute: '/driver-login',
      routes: {
        '/': (context) => const DriverLoginScreen(),
        '/driver-login': (context) => const DriverLoginScreen(),
      },
    );
  }
}


