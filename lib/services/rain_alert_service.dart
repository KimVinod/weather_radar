import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'package:weather_radar/utils/cached_raw_image_data.dart';
import 'package:weather_radar/utils/image_utils.dart';
import 'package:weather_radar/utils/rain_status.dart';
import '../data/weather_repository.dart';

class RainAlertService {
  static const int notificationCooldownMinutes = 10;

  final WeatherRepository _repository = WeatherRepository();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings settings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(settings);
  }

  Future<void> checkAndNotify() async {
    log("RainAlertService: Starting check...");
    await _initializeNotifications();

    // 1. GET USER SETTINGS (Unchanged)
    final prefs = await SharedPreferences.getInstance();
    final userLat = prefs.getDouble('userLat');
    final userLon = prefs.getDouble('userLon');
    final watchRadiusKm = prefs.getDouble('watchRadius');

    if (userLat == null || userLon == null || watchRadiusKm == null) {
      log("RainAlertService: User location or radius not set. Aborting.");
      return;
    }

    // ANTI-SPAM CHECK (Unchanged)
    final lastAlertMillis = prefs.getInt('lastAlertTimestamp') ?? 0;
    final cooldownMillis = notificationCooldownMinutes * 60 * 1000;
    if (DateTime.now().millisecondsSinceEpoch - lastAlertMillis < cooldownMillis) {
      log("RainAlertService: In cooldown period. Aborting.");
      return;
    }

    // --- STEP 1: SIMPLIFY DATA FETCHING ---
    // We only need the reflectivity map and the clutter mask now.
    final results = await Future.wait([
      _repository.getReflectivityMap(),
      rootBundle.load('assets/images/false_positive.png'),
    ]);

    // --- STEP 2: FIX THE TYPE MISMATCH ---
    final reflectivityResult = results[0] as CachedRawImageData?;
    final maskData = (results[1] as ByteData).buffer.asUint8List();

    if (reflectivityResult == null) {
      log("RainAlertService: Failed to download reflectivity map. Aborting.");
      return;
    }

    // --- STEP 3: REMOVE VELOCITY PROCESSING ---
    // Use the .bytes property from our CachedRawImageData object
    final reflectivityImage = cropReflectivityImage(img.decodeImage(reflectivityResult.bytes));
    final maskImage = cropReflectivityImage(img.decodeImage(maskData));

    if (reflectivityImage == null || maskImage == null) {
      log("RainAlertService: Failed to decode or crop images. Aborting.");
      return;
    }

    // --- STEP 4: UPDATE THE ANALYSIS CALL ---
    // Pass only the required parameters. This will require us to update
    // the analyzeRadarData function signature in image_utils.dart later.
    final status = analyzeRadarData(
      reflectivityImage: reflectivityImage,
      maskImage: maskImage,
      userLat: userLat,
      userLon: userLon,
      watchRadiusKm: watchRadiusKm,
    );

    // --- STEP 5: SIMPLIFY NOTIFICATION LOGIC ---
    // We now only care if rain is present.
    if (status == RainStatus.rainPresent) {
      log("RainAlertService: Triggering notification because rain is present.");
      _sendNotification("Rain detected within $watchRadiusKm km of your location.");
      await prefs.setInt('lastAlertTimestamp', DateTime.now().millisecondsSinceEpoch);
    } else {
      log("RainAlertService: Check complete. Status: $status");
    }
  }

  void _sendNotification(String body) {
    // This function is unchanged and perfectly fine.
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'rain_alert_channel', 'Rain Alerts',
      channelDescription: 'Notifications for rain alerts',
      importance: Importance.max, priority: Priority.high, playSound: true,
    );
    const NotificationDetails notificationDetails = NotificationDetails(android: androidDetails);
    _notificationsPlugin.show(0, 'Rain Alert', body, notificationDetails);
  }
}