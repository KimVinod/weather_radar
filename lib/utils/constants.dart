// lib/utils/constants.dart

// --- ALERT CONFIGURATION ---
// The dBZ value at or above which we consider the rain "significant".
import 'package:flutter/material.dart';

const int minDbzForAlert = 20;

// The velocity at or below which we consider the rain "approaching".
const int approachingVelocity = -1; // Any movement towards the radar.

// --- NEW: Hardcoded list of known false positive pixels ---
// Use this for quick, targeted filtering of single pixels found in logs.
// Example: const List<Offset> manualFalsePositives = [ Offset(1234, 987), ];
Set<Offset> manualFalsePositives = {
  Offset(875, 964),
  Offset(875, 965),
  Offset(876, 965),
  Offset(877, 965),
  Offset(876, 966),
  Offset(878, 964),
  Offset(878, 966),
  Offset(878, 967),
  Offset(878, 968),
  Offset(879, 968),
  Offset(880, 946),
  Offset(880, 948),
  Offset(880, 948),
  Offset(880, 949),
  Offset(881, 948),
  Offset(881, 949),
  Offset(881, 950),
  Offset(882, 944),
  Offset(882, 947),
  Offset(882, 946),
  Offset(882, 948),
  Offset(882, 949),
  Offset(882, 950),
  Offset(883, 943),
  Offset(892, 945),
  Offset(893, 945),
  Offset(893, 946),
  Offset(894, 946),
  Offset(907, 948),
  Offset(929, 873),
  //Offset(942, 835), recheck again in future
  Offset(950, 882),
  Offset(952, 881),
  Offset(952, 882),
};