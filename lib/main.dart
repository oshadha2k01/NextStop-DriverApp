import 'dart:async';

import 'package:flutter/material.dart';

import 'User/DriverLogin.dart';
import 'User/Home.dart';

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
        '/': (context) => const HomePage(),
        '/driver-login': (context) => const DriverLoginScreen(),
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.directions_bus_rounded,
              size: 100,
              color: Color(0xFFFF6B35),
            ),
            const SizedBox(height: 20),
            const Text(
              'Welcome to NextStop!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
