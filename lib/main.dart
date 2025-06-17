import 'dart:developer';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:weather_radar/firebase_options.dart';
import 'package:weather_radar/services/rain_alert_service.dart';
import 'package:weather_radar/ui/screens/home_screen.dart';
import 'package:workmanager/workmanager.dart';
import 'providers/home_provider.dart';

// --- NEW TOP-LEVEL FUNCTION FOR WORKMANAGER ---
// This function needs to be defined outside of any class.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    log("Background task started: $task");
    try {
      final alertService = RainAlertService();
      await alertService.checkAndNotify();
      log("Background task finished successfully.");
      return Future.value(true);
    } catch (e) {
      log("Error in background task: $e");
      return Future.value(false); // Signal failure
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: kDebugMode,
  );

  // Pass all uncaught "fatal" errors from the framework to Crashlytics
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => HomeProvider(),
      child: MaterialApp(
        title: 'Weather & Radar',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}