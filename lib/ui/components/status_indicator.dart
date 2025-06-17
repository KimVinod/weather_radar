import 'package:flutter/material.dart';
import 'package:weather_radar/utils/rain_status.dart';

class StatusIndicator extends StatelessWidget {
  final RainStatus status;
  const StatusIndicator({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    String text;
    Color color;
    IconData icon;

    switch (status) {
      case RainStatus.approachingRain:
        text = 'Approaching Rain';
        color = Colors.red.shade400;
        icon = Icons.warning_amber;
        break;
      case RainStatus.rainPresent:
        text = 'Rain Detected';
        color = Colors.blue.shade300;
        icon = Icons.water_drop;
        break;
      case RainStatus.clear:
        text = 'Clear';
        color = Colors.green.shade400;
        icon = Icons.wb_sunny;
        break;
    }

    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.8),
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(
            text.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}