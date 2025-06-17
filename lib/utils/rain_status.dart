// lib/utils/rain_status.dart
enum RainStatus {
  clear,          // No significant rain in the radius
  rainPresent,    // Rain is in the radius, but not approaching
  approachingRain // Rain is in the radius AND approaching
}