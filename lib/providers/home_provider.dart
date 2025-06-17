import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle; // --- ADDED ---
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:weather_radar/services/ocr_service.dart';
import 'package:weather_radar/utils/color_maps.dart';
import 'package:weather_radar/utils/constants.dart';
import 'package:weather_radar/utils/image_utils.dart';
import 'package:weather_radar/utils/image_processing_payload.dart';
import 'package:weather_radar/utils/rain_status.dart';
import 'package:workmanager/workmanager.dart';
import '../data/weather_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;

// A unique name for our background task
const rainCheckTask = "rainRadarCheckTask";

// --- SIMPLIFIED ISOLATE FUNCTION ---
// It only does the heavy "pure Dart" image processing now. No OCR.
Future<ProcessingResult?> _processAndAnalyzeImage(ImageProcessingPayload payload) async {
  // NO MORE platform channel initialization needed here.

  try {
    final reflectivityImage = img.decodeImage(payload.reflectivityMapData);
    final velocityImage = img.decodeImage(payload.velocityMapData);
    final maskImage = img.decodeImage(payload.maskData);

    if (reflectivityImage != null && velocityImage != null && maskImage != null) {
      final croppedReflectivity = cropReflectivityImage(reflectivityImage);
      final croppedVelocity = cropVelocityImage(velocityImage);
      final croppedMask = cropReflectivityImage(maskImage);

      if (croppedReflectivity != null && croppedVelocity != null && croppedMask != null) {
        final status = analyzeRadarData(
          reflectivityImage: croppedReflectivity,
          velocityImage: croppedVelocity,
          maskImage: croppedMask,
          userLat: payload.userLat,
          userLon: payload.userLon,
          watchRadiusKm: payload.radiusKm,
        );

        // Filter the image for display
        for (int y = 0; y < croppedReflectivity.height; y++) {
          for (int x = 0; x < croppedReflectivity.width; x++) {
            final maskPixel = croppedMask.getPixel(x, y);
            final maskDbz = getClosestValue(maskPixel, reflectivityColorMap);
            if (maskDbz >= minDbzForAlert) {
              croppedReflectivity.setPixel(x, y, img.ColorRgba8(0, 0, 0, 0));
            }
          }
        }

        return ProcessingResult(
          imageBytes: Uint8List.fromList(img.encodePng(croppedReflectivity)),
          status: status,
        );
      }
    }
  } catch (e) {
    log("Error in image processing isolate: $e");
  }
  return null;
}
class HomeProvider with ChangeNotifier {
  final WeatherRepository _weatherRepository = WeatherRepository();

  bool _isLoading = true;
  double _radiusKm = 20.0;
  Uint8List? _reflectivityMapData;
  Position? _currentPosition; // Add this to store location
  String? _error;

  bool _notificationsEnabled = false;
  int _notificationFrequency = 15; // Default to 15 minutes
  RainStatus _rainStatus = RainStatus.clear;

  bool _useCurrentLocation = true;
  double? _customLat;
  double? _customLon;

  DateTime? _radarValidTime;

  bool get isLoading => _isLoading;
  Uint8List? get reflectivityMapData => _reflectivityMapData;
  Position? get currentPosition => _currentPosition;
  String? get error => _error;
  double get radiusKm => _radiusKm;
  bool get notificationsEnabled => _notificationsEnabled; // New getter
  int get notificationFrequency => _notificationFrequency; // New getter
  bool get useCurrentLocation => _useCurrentLocation;
  double? get customLat => _customLat;
  double? get customLon => _customLon;
  RainStatus get rainStatus => _rainStatus;
  DateTime? get radarValidTime => _radarValidTime;

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  HomeProvider() {
    _loadSettings();
    refreshData();
  }

  // --- MODIFIED: setLocationMode ---
  Future<void> setLocationMode(bool useCurrent) async {
    _useCurrentLocation = useCurrent;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('useCurrentLocation', _useCurrentLocation);

    // The call to refreshData() is REMOVED from here.
    // The HomeScreen will now handle the refresh.

    // We still need to notify listeners so the UI on the SettingsScreen
    // can update instantly (e.g., show/hide the custom location field).
    notifyListeners();
  }

  // --- MODIFIED: setCustomLocation ---
  Future<void> setCustomLocation(double lat, double lon) async {
    _customLat = lat;
    _customLon = lon;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('customLat', lat);
    await prefs.setDouble('customLon', lon);

    // IMPORTANT: If we are in custom mode, we MUST update the primary
    // 'userLat'/'userLon' that the background service uses.
    if (!_useCurrentLocation) {
      await prefs.setDouble('userLat', lat);
      await prefs.setDouble('userLon', lon);
      log("Set primary alert location to custom: $lat, $lon");
    }

    // The call to refreshData() is REMOVED from here.
    // The HomeScreen will now handle the refresh.

    // Notify listeners so the SettingsScreen can show the new coordinates.
    notifyListeners();
  }


  // --- NEW NOTIFICATION CONTROL METHODS ---

  Future<void> toggleNotifications(bool isEnabled) async {
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _notificationsEnabled = isEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationsEnabled', _notificationsEnabled);

    if (_notificationsEnabled) {
      // If user turned them ON, register the task
      _registerTask();
    } else {
      // If user turned them OFF, cancel the task
      _cancelTask();
    }
    notifyListeners();
  }

  Future<void> updateNotificationFrequency(int frequencyInMinutes) async {
    _notificationFrequency = frequencyInMinutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notificationFrequency', _notificationFrequency);

    // If notifications are enabled, re-register the task with the new frequency
    if (_notificationsEnabled) {
      _registerTask();
    }
    notifyListeners();
  }

  // --- PRIVATE WORKMANAGER HELPERS ---

  void _registerTask() {
    Workmanager().registerPeriodicTask(
      rainCheckTask,
      rainCheckTask, // Task name and unique name are the same
      frequency: Duration(minutes: _notificationFrequency),
      // This ensures the task is replaced if it already exists
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      backoffPolicy: BackoffPolicy.linear,
    );
    log("WorkManager task registered with frequency: $_notificationFrequency minutes.");
  }

  void _cancelTask() {
    Workmanager().cancelByUniqueName(rainCheckTask);
    log("WorkManager task cancelled.");
  }

  // --- UPDATED LOAD/REFRESH METHODS ---

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // Load existing settings
    _radiusKm = prefs.getDouble('watchRadius') ?? 20.0;
    _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? false;
    _notificationFrequency = prefs.getInt('notificationFrequency') ?? 15;

    // Load new location settings
    _useCurrentLocation = prefs.getBool('useCurrentLocation') ?? true;
    _customLat = prefs.getDouble('customLat');
    _customLon = prefs.getDouble('customLon');

    notifyListeners();
  }

  // NEW: This method is FAST. It only updates the value in memory.
  void updateRadiusLive(double newRadius) {
    _radiusKm = newRadius;
    notifyListeners(); // This is fast, just rebuilds the UI
  }

  // NEW: This method is for SAVING. It can be slower.
  Future<void> saveRadius(double finalRadius) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('watchRadius', finalRadius);
    // No need to call notifyListeners() here, as the UI already has the final value.
    log("Radius saved: $finalRadius"); // Good for debugging
  }

  Future<void> refreshData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // --- THE FIX: GET AND SET THE POSITION FOR THE UI ---
      // We need to determine the position to use for BOTH the UI marker
      // and the background analysis.
      Position? position;
      if (_useCurrentLocation) {
        position = await _determinePosition();
      } else if (_customLat != null && _customLon != null) {
        // Create a Position object from the custom location for the UI.
        position = Position(
            latitude: _customLat!,
            longitude: _customLon!,
            timestamp: DateTime.now(),
            accuracy: 0, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0
        );
      }

      // If we couldn't get a location, we can't proceed.
      if (position == null) {
        throw Exception("Could not determine user location for analysis.");
      }

      // --- SET THE STATE FOR THE UI MARKER ---
      _currentPosition = position;
      // --- END OF FIX ---

      // Now, fetch all three images.
      final results = await Future.wait([
        _weatherRepository.getReflectivityMap(),
        _weatherRepository.getVelocityMap(),
        rootBundle.load('assets/images/false_positive.png'),
      ]);

      final reflectivityData = results[0] as Uint8List?;
      final velocityData = results[1] as Uint8List?;
      final maskData = (results[2] as ByteData).buffer.asUint8List();

      if (reflectivityData != null && velocityData != null) {
        final ocrFuture = OcrService().processImageForTimestamp(reflectivityData);

        final payload = ImageProcessingPayload(
          reflectivityMapData: reflectivityData,
          velocityMapData: velocityData,
          maskData: maskData,
          userLat: position.latitude,   // Use the position we just determined
          userLon: position.longitude,  // Use the position we just determined
          radiusKm: _radiusKm,
        );

        final result = await compute(_processAndAnalyzeImage, payload);

        final validTime = await ocrFuture;

        if (result != null) {
          _reflectivityMapData = result.imageBytes;
          _rainStatus = result.status;
          _radarValidTime = validTime;
        } else {
          _error = "Failed to process map image.";
        }
      } else {
        _error = "Failed to load radar maps.";
      }
    } catch (e) {
      log("Error in refreshData: $e");
      if(e.toString() == "Exception: Could not determine user location for analysis.") {
        _error = "Please turn ON your location service\nor set a custom location.";
      } else {
        _error = "An error occurred. Please try again.";
      }
    }

    // --- The logic to SAVE the location to SharedPreferences for the background task is still important ---
    final prefs = await SharedPreferences.getInstance();
    if (_useCurrentLocation && _currentPosition != null) {
      await prefs.setDouble('userLat', _currentPosition!.latitude);
      await prefs.setDouble('userLon', _currentPosition!.longitude);
      log("Saved current location for alerts: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}");
    }
    // --- End of saving logic ---

    _isLoading = false;
    notifyListeners();
  }

  // New private method for getting location
  Future<Position?> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      log('Location services are disabled.');
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        log('Location permissions are denied');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      log('Location permissions are permanently denied.');
      return null;
    }

    return await Geolocator.getCurrentPosition();
  }
}