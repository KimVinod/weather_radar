import 'dart:math';

// --- RADAR CONSTANTS ---
const double radarLat = 19.1342;
const double radarLon = 72.8762;
const double radarRangeKm = 249.0;

// --- CROPPED IMAGE CONSTANTS ---
// The dimensions of our new, clean, cropped image
const double croppedImageWidth = 1800.0;
const double croppedImageHeight = 1800.0;

// The radar is now at the exact center of our cropped image
const double radarPixelCenterX = croppedImageWidth / 2.0;
const double radarPixelCenterY = croppedImageHeight / 2.0;


Map<String, double>? transformToPixel(double userLat, double userLon) {
  const double mapKmDiameter = radarRangeKm * 2.0;
  const double kmPerPixel = mapKmDiameter / croppedImageWidth;

  const double degToRad = pi / 180.0;
  const double earthRadiusKm = 6371.0;

  // Use the direct lat/lon values instead of from an object
  double dLat = (userLat - radarLat) * degToRad;
  double dLon = (userLon - radarLon) * degToRad;

  double xKm = dLon * earthRadiusKm * cos(radarLat * degToRad);
  double yKm = dLat * earthRadiusKm;

  final double pixelOffsetX = xKm / kmPerPixel;
  final double pixelOffsetY = yKm / kmPerPixel;

  final double finalPixelX = radarPixelCenterX + pixelOffsetX;
  final double finalPixelY = radarPixelCenterY - pixelOffsetY;

  return {'x': finalPixelX, 'y': finalPixelY};
}