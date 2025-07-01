import 'dart:developer';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:weather_radar/utils/cached_raw_image_data.dart';

const String _reflectivityMapUrl = "https://mausam.imd.gov.in/Radar/caz_vrv.gif";
const String _velocityMapUrl = "https://mausam.imd.gov.in/Radar/ppv_vrv.gif";

const String _reflectivityCacheFile = "reflectivity.gif";
const String _velocityCacheFile = "velocity.gif";
const String _reflectivityTimestampKey = "reflectivityCacheTimestamp";
const String _velocityTimestampKey = "velocityCacheTimestamp";

class WeatherRepository {
  Future<CachedRawImageData?> _getMapData({
    required String url,
    required String cacheFileName,
    required String timestampKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheDir = await getTemporaryDirectory();
    final cacheFile = File('${cacheDir.path}/$cacheFileName');

    final lastFetchMillis = prefs.getInt(timestampKey);
    if (lastFetchMillis != null) {
      final cacheAge = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastFetchMillis));
      if (cacheAge < const Duration(minutes: 5) && await cacheFile.exists()) {
        log("RAW CACHE HIT: Loading '$cacheFileName' from local cache.");
        // Return the data and its saved timestamp ---
        return CachedRawImageData(
          bytes: await cacheFile.readAsBytes(),
          timestamp: DateTime.fromMillisecondsSinceEpoch(lastFetchMillis),
        );
      }
    }

    log("RAW CACHE MISS: Fetching '$cacheFileName' from network.");
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final now = DateTime.now();
        final data = response.bodyBytes;
        await cacheFile.writeAsBytes(data);
        await prefs.setInt(timestampKey, now.millisecondsSinceEpoch);
        log("RAW CACHE SAVED: '$cacheFileName' updated in cache.");
        // Return the new data and its timestamp ---
        return CachedRawImageData(bytes: data, timestamp: now);
      } else {
        log("Server error fetching map from $url: ${response.statusCode}");
        if (await cacheFile.exists() && lastFetchMillis != null) {
          log("NETWORK FAIL: Returning stale data from cache as fallback.");
          return CachedRawImageData(
            bytes: await cacheFile.readAsBytes(),
            timestamp: DateTime.fromMillisecondsSinceEpoch(lastFetchMillis),
          );
        }
        return null;
      }
    } catch (e) {
      log("Error fetching map from $url: $e");
      if (await cacheFile.exists() && lastFetchMillis != null) {
        log("NETWORK FAIL: Returning stale data from cache as fallback.");
        return CachedRawImageData(
          bytes: await cacheFile.readAsBytes(),
          timestamp: DateTime.fromMillisecondsSinceEpoch(lastFetchMillis),
        );
      }
      return null;
    }
  }

  /// Fetches the reflectivity map (shows where the rain is).
  /// Uses a 5-minute file-based cache.
  Future<CachedRawImageData?> getReflectivityMap() async {
    return _getMapData(
      url: _reflectivityMapUrl,
      cacheFileName: _reflectivityCacheFile,
      timestampKey: _reflectivityTimestampKey,
    );
  }

  /// Fetches the velocity map (shows which way the rain is moving).
  /// Uses a 5-minute file-based cache.
  Future<CachedRawImageData?> getVelocityMap() async {
    return _getMapData(
      url: _velocityMapUrl,
      cacheFileName: _velocityCacheFile,
      timestampKey: _velocityTimestampKey,
    );
  }
}