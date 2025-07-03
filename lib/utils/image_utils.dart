import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:weather_radar/utils/constants.dart';
import 'package:weather_radar/utils/coordinate_transformer.dart';
import 'package:weather_radar/utils/rain_status.dart';
import 'package:weather_radar/utils/color_maps.dart';
import 'dart:developer' as log;

img.Image? cropReflectivityImage(img.Image? originalImage) {
  if (originalImage == null) return null;
  // These coordinates are from the original raw GIF image.
  return img.copyCrop(
    originalImage,
    x: 30,
    y: 630,
    width: 1800,
    height: 1800,
  );
}

int getClosestValue(img.Pixel pixel, Map<int, int> colorMap) {
  const double matchThreshold = 100.0; // Using your stricter threshold

  num minDistance = double.infinity;
  int closestValue = 0;

  final r1 = pixel.r;
  final g1 = pixel.g;
  final b1 = pixel.b;

  if (pixel.a < 128) {
    return 0; // Transparent pixels are not rain
  }

  colorMap.forEach((key, value) {
    final r2 = (key >> 16) & 0xFF;
    final g2 = (key >> 8) & 0xFF;
    final b2 = key & 0xFF;
    final distance = pow(r1 - r2, 2) + pow(g1 - g2, 2) + pow(b1 - b2, 2);
    if (distance < minDistance) {
      minDistance = distance;
      closestValue = value;
    }
  });

  if (minDistance > matchThreshold) {
    return 0; // Match is not close enough, treat as no rain
  }

  return closestValue;
}

// --- elper function to convert pixel back to GPS ---
Map<String, double> _transformPixelToGps(int x, int y) {
  const double mapKmDiameter = radarRangeKm * 2.0;
  const double kmPerPixel = mapKmDiameter / croppedImageWidth;

  const double radToDeg = 180.0 / pi;
  const double earthRadiusKm = 6371.0;

  final double pixelOffsetX = x - radarPixelCenterX;
  final double pixelOffsetY = radarPixelCenterY - y; // Invert Y for calculation

  final double xKm = pixelOffsetX * kmPerPixel;
  final double yKm = pixelOffsetY * kmPerPixel;

  final double dLon = xKm / (earthRadiusKm * cos(radarLat * (pi / 180.0)));
  final double dLat = yKm / earthRadiusKm;

  final double finalLon = radarLon + (dLon * radToDeg);
  final double finalLat = radarLat + (dLat * radToDeg);

  return {'lat': finalLat, 'lon': finalLon};
}

// =========================================================================
// === ANALYSIS FUNCTION (with BOTH filtering methods) ===
// =========================================================================
RainStatus analyzeRadarData({
  required img.Image reflectivityImage,
  required img.Image maskImage,
  required double userLat,
  required double userLon,
  required double watchRadiusKm,
}) {
  bool rainFound = false;
  const double mapKmDiameter = radarRangeKm * 2.0;
  const double kmPerPixel = mapKmDiameter / croppedImageWidth;
  final radiusInPixels = watchRadiusKm / kmPerPixel;
  final pixelCoords = transformToPixel(userLat, userLon);
  if (pixelCoords == null) return RainStatus.clear;
  final userPixelX = pixelCoords['x']!.round();
  final userPixelY = pixelCoords['y']!.round();
  final int startX = max(0, (userPixelX - radiusInPixels).round());
  final int endX = min(croppedImageWidth.toInt() - 1, (userPixelX + radiusInPixels).round());
  final int startY = max(0, (userPixelY - radiusInPixels).round());
  final int endY = min(croppedImageHeight.toInt() - 1, (userPixelY + radiusInPixels).round());

  for (int y = startY; y <= endY; y++) {
    for (int x = startX; x <= endX; x++) {
      final distance = sqrt(pow(x - userPixelX, 2) + pow(y - userPixelY, 2));
      if (distance > radiusInPixels) continue;

      if (manualFalsePositives.contains(Offset(x.toDouble(), y.toDouble()))) {
        print('--- Manually Filtering Pixel: (x: $x, y: $y). This pixel will be ignored. ---');
        continue;
      }

      final maskPixel = maskImage.getPixel(x, y);
      final maskDbz = getClosestValue(maskPixel, reflectivityColorMap);
      if (maskDbz >= minDbzForAlert) {
        continue;
      }

      final reflectivityPixel = reflectivityImage.getPixel(x, y);
      final dbz = getClosestValue(reflectivityPixel, reflectivityColorMap);

      if (dbz >= minDbzForAlert) {
        // We found a rain pixel.
        // --- THIS IS THE FIX: Set the flag, but DO NOT return yet ---
        rainFound = true;

        // Log the finding, then let the loop continue.
        final gpsCoords = _transformPixelToGps(x, y);
        print(
            '--- Significant Rain DETECTED! ---\n'
                '  Pixel Coords: (x: $x, y: $y)\n'
                '  GPS Coords:   (Lat: ${gpsCoords['lat']!.toStringAsFixed(4)}, Lon: ${gpsCoords['lon']!.toStringAsFixed(4)})\n'
                '  Rain Stats:   (dBZ: $dbz)'
        );
        // By not returning, the loop will continue to the next pixel.
      }
    }
  }

  // --- Decision is made AFTER the loops are finished ---
  if (rainFound) {
    log.log('--- Analysis Complete: Rain was found in the area.');
    return RainStatus.rainPresent;
  } else {
    log.log('--- Analysis Complete: No significant rain found in the area.');
    return RainStatus.clear;
  }
}