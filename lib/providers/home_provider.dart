import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher_string.dart';
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

// --- SOLATE FUNCTION ---
// It only does the heavy "pure Dart" image processing now. No OCR.
Future<ProcessingResult?> _processAndAnalyzeImage(ImageProcessingPayload payload) async {
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

  PackageInfo? _packageInfo;

  bool _isLoading = true;
  String _loadingStatusText = '';
  double _radiusKm = 20.0;
  Uint8List? _reflectivityMapData;
  Position? _currentPosition;
  String? _error;

  bool _notificationsEnabled = false;
  int _notificationFrequency = 15; // Default to 15 minutes
  RainStatus _rainStatus = RainStatus.clear;

  bool _useCurrentLocation = true;
  double? _customLat;
  double? _customLon;

  DateTime? _radarValidTime;

  PackageInfo? get packageInfo => _packageInfo;
  bool get isLoading => _isLoading;
  String get loadingStatusText => _loadingStatusText;
  Uint8List? get reflectivityMapData => _reflectivityMapData;
  Position? get currentPosition => _currentPosition;
  String? get error => _error;
  double get radiusKm => _radiusKm;
  bool get notificationsEnabled => _notificationsEnabled;
  int get notificationFrequency => _notificationFrequency;
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

  Future<void> setLocationMode(bool useCurrent) async {
    _useCurrentLocation = useCurrent;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('useCurrentLocation', _useCurrentLocation);
    notifyListeners();
  }

  Future<void> setCustomLocation(double lat, double lon) async {
    _customLat = lat;
    _customLon = lon;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('customLat', lat);
    await prefs.setDouble('customLon', lon);

    // If we are in custom mode, we MUST update the primary
    // 'userLat'/'userLon' that the background service uses.
    if (!_useCurrentLocation) {
      await prefs.setDouble('userLat', lat);
      await prefs.setDouble('userLon', lon);
      log("Set primary alert location to custom: $lat, $lon");
    }

    notifyListeners();
  }


  Future<void> toggleNotifications(bool isEnabled) async {
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _notificationsEnabled = isEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationsEnabled', _notificationsEnabled);

    if (_notificationsEnabled) {
      _registerTask();
    } else {
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


  Future<void> _loadSettings() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    _packageInfo = packageInfo;

    final prefs = await SharedPreferences.getInstance();
    _radiusKm = prefs.getDouble('watchRadius') ?? 20.0;
    _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? false;
    _notificationFrequency = prefs.getInt('notificationFrequency') ?? 15;
    _useCurrentLocation = prefs.getBool('useCurrentLocation') ?? true;
    _customLat = prefs.getDouble('customLat');
    _customLon = prefs.getDouble('customLon');

    notifyListeners();
  }

  void updateRadiusLive(double newRadius) {
    _radiusKm = newRadius;
    notifyListeners();
  }

  Future<void> saveRadius(double finalRadius) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('watchRadius', finalRadius);
    log("Radius saved: $finalRadius"); // Good for debugging
  }

  Future<void> refreshData() async {
    _isLoading = true;
    _error = null;
    _loadingStatusText = 'Initializing...';
    notifyListeners();

    try {
      // We need to determine the position to use for BOTH the UI marker
      // and the background analysis.
      final prefs = await SharedPreferences.getInstance();

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

      final currentRadius = _radiusKm;

      // --- 2. GET RAW DATA (FROM REPO'S CACHE OR NETWORK) ---
      _loadingStatusText = 'Fetching radar data...';
      notifyListeners();
      final reflectivityData = await _weatherRepository.getReflectivityMap();
      if (reflectivityData == null) throw Exception("Failed to get reflectivity map.");

      // --- 3. CHECK IF PROCESSED DATA IS STILL VALID ---
      final lastProcessedImageTimestamp = prefs.getInt('processed_image_timestamp') ?? 0;
      final lastProcessedRadius = prefs.getDouble('processed_radius') ?? 0.0;
      final lastProcessedLat = prefs.getDouble('processed_lat') ?? 0.0;
      final lastProcessedLon = prefs.getDouble('processed_lon') ?? 0.0;

      final isSameImage = reflectivityData.timestamp.millisecondsSinceEpoch == lastProcessedImageTimestamp;
      final isSameRadius = currentRadius == lastProcessedRadius;
      final isSameLocation = (position.latitude - lastProcessedLat).abs() < 0.0001 &&
          (position.longitude - lastProcessedLon).abs() < 0.0001;

      final cacheDir = await getTemporaryDirectory();
      final processedCacheFile = File('${cacheDir.path}/processed_reflectivity.png');

      // --- 4. PROCESSED CACHE HIT LOGIC ---
      if (isSameImage && isSameRadius && isSameLocation && await processedCacheFile.exists()) {
        log("PROCESSED CACHE HIT: Loading fully processed data from cache.");

        // Load all processed data directly from cache, skipping all heavy work.
        _reflectivityMapData = await processedCacheFile.readAsBytes();
        final statusIndex = prefs.getInt('processed_status_index') ?? 0;
        _rainStatus = RainStatus.values[statusIndex];
        final validTimeMillis = prefs.getInt('processed_valid_time') ?? 0;
        _radarValidTime = validTimeMillis > 0 ? DateTime.fromMillisecondsSinceEpoch(validTimeMillis) : null;

      } else {
        // --- 5. PROCESSED CACHE MISS LOGIC ---
        log("PROCESSED CACHE MISS: Re-processing required. Reason: sameImage=$isSameImage, sameRadius=$isSameRadius, sameLocation=$isSameLocation");
        _loadingStatusText = 'Analyzing...';
        notifyListeners();

        final velocityData = await _weatherRepository.getVelocityMap();
        final maskByteData = await rootBundle.load('assets/images/false_positive.png');
        if (velocityData == null) throw Exception("Failed to get velocity map.");

        // OCR is faster, run it while we wait for the isolate
        final ocrFuture = OcrService().processImageForTimestamp(reflectivityData.bytes);

        // Run heavy processing in the isolate
        final payload = ImageProcessingPayload(
          reflectivityMapData: reflectivityData.bytes,
          velocityMapData: velocityData.bytes,
          maskData: maskByteData.buffer.asUint8List(),
          userLat: position.latitude,
          userLon: position.longitude,
          radiusKm: currentRadius,
        );
        final processingResult = await compute(_processAndAnalyzeImage, payload);

        // Await OCR and update state
        final validTime = await ocrFuture;

        if (processingResult != null) {
          _reflectivityMapData = processingResult.imageBytes;
          _rainStatus = processingResult.status;
          _radarValidTime = validTime;

          // --- SAVE NEWLY PROCESSED DATA TO CACHE ---
          await processedCacheFile.writeAsBytes(_reflectivityMapData!);
          await prefs.setInt('processed_image_timestamp', reflectivityData.timestamp.millisecondsSinceEpoch);
          await prefs.setDouble('processed_radius', currentRadius);
          await prefs.setDouble('processed_lat', position.latitude);
          await prefs.setDouble('processed_lon', position.longitude);
          await prefs.setInt('processed_status_index', _rainStatus.index);
          await prefs.setInt('processed_valid_time', validTime?.millisecondsSinceEpoch ?? 0);
          log("PROCESSED CACHE SAVED: New data and parameters cached.");
        } else {
          _error = "Failed to process map image.";
        }
      }

      // Save latest location for the background service (this should always run)
      if (_useCurrentLocation && _currentPosition != null) {
        await prefs.setDouble('userLat', _currentPosition!.latitude);
        await prefs.setDouble('userLon', _currentPosition!.longitude);
      }
    } catch (e) {
      log("Error in refreshData: $e");
      if(e.toString() == "Exception: Could not determine user location for analysis.") {
        _error = "Please turn ON your location service\nor set a custom location.";
      } else {
        _error = "An error occurred. Please try again.";
      }
    }

    _isLoading = false;
    _loadingStatusText = '';
    notifyListeners();
  }

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
  
  Future<bool> openGithubReleases() async {
    if(await canLaunchUrlString(githubReleasesUrl)) {
      return await launchUrlString(githubReleasesUrl, mode: LaunchMode.inAppBrowserView);
    } else {
      return false;
    }
  }
}