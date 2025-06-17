import 'dart:developer';
import 'dart:io'; // Required for File operations
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- MODIFIED: Use constants for URLs and cache keys for safety ---
const String _reflectivityMapUrl = "https://mausam.imd.gov.in/Radar/caz_vrv.gif";
const String _velocityMapUrl = "https://mausam.imd.gov.in/Radar/ppv_vrv.gif";

const String _reflectivityCacheFile = "reflectivity.gif";
const String _velocityCacheFile = "velocity.gif";
const String _reflectivityTimestampKey = "reflectivityCacheTimestamp";
const String _velocityTimestampKey = "velocityCacheTimestamp";

class WeatherRepository {
  // --- NEW: A single, generic caching method ---
  Future<Uint8List?> _getMapData({
    required String url,
    required String cacheFileName,
    required String timestampKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheDir = await getTemporaryDirectory(); // Use temp directory for cache
    final cacheFile = File('${cacheDir.path}/$cacheFileName');

    // --- 1. Check the cache first ---
    final lastFetchMillis = prefs.getInt(timestampKey);
    if (lastFetchMillis != null) {
      final cacheAge = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastFetchMillis));
      // Check if the cache is less than 5 minutes old AND the file exists
      if (cacheAge < const Duration(minutes: 5) && await cacheFile.exists()) {
        log("CACHE HIT: Loading '$cacheFileName' from local cache.");
        return await cacheFile.readAsBytes();
      }
    }

    // --- 2. If cache is invalid or missing, fetch from network ---
    log("CACHE MISS: Fetching '$cacheFileName' from network.");
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = response.bodyBytes;
        // --- 3. Save the new data to the cache ---
        await cacheFile.writeAsBytes(data); // Save the file
        await prefs.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch); // Save the timestamp
        log("CACHE SAVED: '$cacheFileName' updated in cache.");
        return data;
      } else {
        log("Server error fetching map from $url: ${response.statusCode}");
        // Optional: If network fails, try to return old cached data as a fallback
        if (await cacheFile.exists()) {
          log("NETWORK FAIL: Returning stale data from cache as fallback.");
          return await cacheFile.readAsBytes();
        }
        return null;
      }
    } catch (e) {
      log("Error fetching map from $url: $e");
      // Optional: Fallback to stale cache on network error
      if (await cacheFile.exists()) {
        log("NETWORK FAIL: Returning stale data from cache as fallback.");
        return await cacheFile.readAsBytes();
      }
      return null;
    }
  }

  /// Fetches the reflectivity map (shows where the rain is).
  /// Uses a 5-minute file-based cache.
  Future<Uint8List?> getReflectivityMap() async {
    return _getMapData(
      url: _reflectivityMapUrl,
      cacheFileName: _reflectivityCacheFile,
      timestampKey: _reflectivityTimestampKey,
    );
  }

  /// Fetches the velocity map (shows which way the rain is moving).
  /// Uses a 5-minute file-based cache.
  Future<Uint8List?> getVelocityMap() async {
    return _getMapData(
      url: _velocityMapUrl,
      cacheFileName: _velocityCacheFile,
      timestampKey: _velocityTimestampKey,
    );
  }
}