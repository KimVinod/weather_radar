import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:weather_radar/providers/home_provider.dart';
import 'package:weather_radar/ui/components/status_indicator.dart';
import 'package:weather_radar/ui/components/radius_painter.dart';
import 'package:weather_radar/ui/screens/settings_screen.dart';
import 'package:weather_radar/utils/coordinate_transformer.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:developer' as log;

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<HomeProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        title: const Text('Weather & Radar'),
        leading: Icon(Icons.cloudy_snowing),
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: "Settings",
            onPressed: () async {
              // --- STEP 1: Remember the current values BEFORE navigating ---
              final initialRadius = provider.radiusKm;
              final initialUseCurrentLocation = provider.useCurrentLocation;
              final initialCustomLat = provider.customLat;
              final initialCustomLon = provider.customLon;

              // --- STEP 2: Navigate and wait for the user to return ---
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );

              // --- STEP 3: Compare the old values with the new ones ---
              // The provider now holds the potentially updated values.
              if (initialRadius != provider.radiusKm ||
                  initialUseCurrentLocation != provider.useCurrentLocation ||
                  initialCustomLat != provider.customLat ||
                  initialCustomLon != provider.customLon)
              {
                // If any of the relevant settings have changed, THEN refresh.
                log.log("Settings changed. Refreshing data...");
                provider.refreshData();
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Consumer<HomeProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    provider.loadingStatusText,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              );
            } else if (provider.error != null) {
              return Text(provider.error!, textAlign: TextAlign.center);
            } else if (provider.reflectivityMapData != null) {
              final Position? userPosition = provider.currentPosition;

              return Column(
                children: [
                  if(provider.radarValidTime != null)...[
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        "Radar updated: ${timeago.format(provider.radarValidTime!)}",
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                  StatusIndicator(status: provider.rainStatus),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final onScreenWidth = constraints.maxWidth;
                        final onScreenHeight = constraints.maxHeight;

                        // Our source is now the small, cropped image
                        final sourceSize = Size(croppedImageWidth, croppedImageHeight);
                        final destinationSize = Size(onScreenWidth, onScreenHeight);

                        // Calculate the scale and offset of the CROPPED image
                        final scale = min(destinationSize.width / sourceSize.width,
                            destinationSize.height / sourceSize.height);
                        final finalImageSize = sourceSize * scale;
                        final imageOffset = Offset(
                          (destinationSize.width - finalImageSize.width) / 2,
                          (destinationSize.height - finalImageSize.height) / 2,
                        );

                        // All calculations are relative to the cropped image
                        Map<String, double>? pixelCoords = userPosition != null
                            ? transformToPixel(userPosition.latitude, userPosition.longitude)
                            : null;

                        Map<String, double>? imageRelativeCoords;
                        double? scaledRadius;

                        if (pixelCoords != null) {
                          // Coordinates relative to the top-left of the image (not the screen)
                          imageRelativeCoords = {
                            'x': pixelCoords['x']! * scale,
                            'y': pixelCoords['y']! * scale,
                          };

                          // Define totalKm here for radius calculation
                          const double totalKm = radarRangeKm * 2;
                          final originalRadiusInPixels = (provider.radiusKm / totalKm) * croppedImageWidth;
                          scaledRadius = originalRadiusInPixels * scale;
                        }

                        return InteractiveViewer(
                          minScale: 1.0,
                          maxScale: 10.0,
                          child: SizedBox(
                            width: onScreenWidth,
                            height: onScreenHeight,
                            child: Stack(
                              children: [
                                Positioned(
                                  left: imageOffset.dx,
                                  top: imageOffset.dy,
                                  width: finalImageSize.width,
                                  height: finalImageSize.height,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Image.memory(provider.reflectivityMapData!),

                                      // All overlays are now in the correct coordinate space
                                      if (imageRelativeCoords != null)
                                        Positioned(
                                          left: imageRelativeCoords['x']! - 6,
                                          top: imageRelativeCoords['y']! - 6,
                                          child: const Icon(Icons.adjust, color: Colors.red, size: 12.0),
                                        ),

                                      if (imageRelativeCoords != null && scaledRadius != null)
                                        CustomPaint(
                                          size: finalImageSize,
                                          painter: RadiusPainter(
                                            center: imageRelativeCoords,
                                            radiusInPixels: scaledRadius,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            } else {
              return const Text('Something went wrong.');
            }
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Provider.of<HomeProvider>(context, listen: false).refreshData();
        },
        tooltip: "Refresh",
        child: const Icon(Icons.refresh),
      ),
    );
  }
}