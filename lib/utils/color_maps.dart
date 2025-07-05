// This file contains pre-computed maps for converting radar image colors
// to their scientific values (dBZ for reflectivity, m/s for velocity).

// The key is the 32-bit integer representation of the color (0xAARRGGBB).
// The value is the corresponding dBZ value.
const Map<int, int> reflectivityColorMap = {
  // Blues (Light Rain)
  0xFF00008B: 20, // Darkest Blue
  0xFF0000CD: 24, // Medium Blue
  0xFF0000FF: 28, // Bright Blue
  0xFF00BFFF: 32, // Deep Sky Blue
  0xFF00FFFF: 36, // Cyan

  // Whites/Yellows (Moderate Rain)
  0xFFF0FFFF: 40, // Azure/White-ish
  0xFFFFFF00: 44, // Yellow
  0xFFFFD700: 48, // Gold

  // Oranges/Reds (Heavy Rain / Hail)
  0xFFFFA500: 52, // Orange
  0xFFFF0000: 56, // Red
  0xFFB30000: 60, // Darker Red
};