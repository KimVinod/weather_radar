// lib/services/rain_alert_service.dart

import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle; // --- ADDED ---
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'package:weather_radar/utils/image_utils.dart';
import 'package:weather_radar/utils/rain_status.dart';
import '../data/weather_repository.dart';

class RainAlertService {
  // --- CONFIGURATION ---
  // How long to wait before sending another notification (in minutes).
  static const int notificationCooldownMinutes = 10;

  final WeatherRepository _repository = WeatherRepository();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher'); // IMPORTANT: Use your app's icon
    const InitializationSettings settings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(settings);
  }

  Future<void> checkAndNotify() async {
    log("RainAlertService: Starting check...");
    await _initializeNotifications();

    // 1. GET USER SETTINGS FROM STORAGE
    final prefs = await SharedPreferences.getInstance();
    final userLat = prefs.getDouble('userLat');
    final userLon = prefs.getDouble('userLon');
    final watchRadiusKm = prefs.getDouble('watchRadius');

    if (userLat == null || userLon == null || watchRadiusKm == null) {
      log("RainAlertService: User location or radius not set. Aborting.");
      return;
    }

    // ANTI-SPAM CHECK: Don't notify too frequently
    final lastAlertMillis = prefs.getInt('lastAlertTimestamp') ?? 0;
    final cooldownMillis = notificationCooldownMinutes * 60 * 1000;
    if (DateTime.now().millisecondsSinceEpoch - lastAlertMillis < cooldownMillis) {
      log("RainAlertService: In cooldown period. Aborting.");
      return;
    }

    // --- ADDED: Load ALL THREE images now ---
    final results = await Future.wait([
      _repository.getReflectivityMap(),
      _repository.getVelocityMap(),
      rootBundle.load('assets/images/false_positive.png'),
    ]);

    final reflectivityData = results[0] as Uint8List?;
    final velocityData = results[1] as Uint8List?;
    final maskData = (results[2] as ByteData).buffer.asUint8List();

    if (reflectivityData == null || velocityData == null) {
      log("RainAlertService: Failed to download one or both maps. Aborting.");
      return;
    }

    final reflectivityImage = cropReflectivityImage(img.decodeImage(reflectivityData));
    final velocityImage = cropVelocityImage(img.decodeImage(velocityData));
    final maskImage = cropReflectivityImage(img.decodeImage(maskData));

    if (reflectivityImage == null || velocityImage == null || maskImage == null) {
      log("RainAlertService: Failed to decode or crop images. Aborting.");
      return;
    }

    // --- REFACTORED: The entire analysis loop is replaced by one call ---
    final status = analyzeRadarData(
      reflectivityImage: reflectivityImage,
      velocityImage: velocityImage,
      maskImage: maskImage,
      userLat: userLat,
      userLon: userLon,
      watchRadiusKm: watchRadiusKm,
    );
    // --- END REFACTORED ---

    // 5. SEND NOTIFICATION IF NEEDED
    if (status == RainStatus.approachingRain) { // <-- Check against the enum
      log("RainAlertService: Triggering notification for approaching rain.");
      _sendNotification("Rain is approaching your location.");
      await prefs.setInt('lastAlertTimestamp', DateTime.now().millisecondsSinceEpoch);
    } else if (status == RainStatus.rainPresent) {
      log("RainAlertService: Triggering notification for rain is present.");
      _sendNotification("Rain detected within $watchRadiusKm km of your location.");
      await prefs.setInt('lastAlertTimestamp', DateTime.now().millisecondsSinceEpoch);
    } else {
      log("RainAlertService: Check complete. Status: $status");
    }

  }

  void _sendNotification(String body) {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'rain_alert_channel',
      'Rain Alerts',
      channelDescription: 'Notifications for rain alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );
    const NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);

    _notificationsPlugin.show(
      0, // Notification ID
      'Rain Alert',
      body,
      notificationDetails,
    );
  }
}