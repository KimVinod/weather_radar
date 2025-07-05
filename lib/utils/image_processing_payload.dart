import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:weather_radar/utils/rain_status.dart';

// --- A result class for the isolate ---
class ProcessingResult {
  final Uint8List? imageBytes;
  final RainStatus status;

  ProcessingResult({required this.imageBytes, required this.status});
}

// --- Payload now includes everything for analysis ---
class ImageProcessingPayload {
  final Uint8List reflectivityMapData;
  final Uint8List maskData;
  final double userLat;
  final double userLon;
  final double radiusKm;

  ImageProcessingPayload({
    required this.reflectivityMapData,
    required this.maskData,
    required this.userLat,
    required this.userLon,
    required this.radiusKm,
  });
}