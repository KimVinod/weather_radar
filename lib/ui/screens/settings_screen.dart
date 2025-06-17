import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/home_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void openBottomModal(HomeProvider provider, BuildContext context) {
    final latController = TextEditingController(
      text: provider.customLat?.toStringAsFixed(4) ?? '',
    );
    final lonController = TextEditingController(
      text: provider.customLon?.toStringAsFixed(4) ?? '',
    );
    final formKey = GlobalKey<FormState>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            top: 24,
            left: 24,
            right: 24,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter Custom Location',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: latController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final v = double.tryParse(value ?? '');
                      if (v == null || v < -90 || v > 90) {
                        return 'Enter a valid latitude (-90 to 90)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: lonController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final v = double.tryParse(value ?? '');
                      if (v == null || v < -180 || v > 180) {
                        return 'Enter a valid longitude (-180 to 180)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      if (formKey.currentState?.validate() ?? false) {
                        final lat = double.parse(latController.text);
                        final lon = double.parse(lonController.text);
                        provider.setCustomLocation(lat, lon);
                        Navigator.pop(context); // Close modal
                      }
                    },
                    child: const Text('SAVE'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: colorScheme.surfaceContainer,
        titleSpacing: 0,
        title: const Text('Settings'),
      ),
      body: Consumer<HomeProvider>(
        builder: (context, provider, child) {
          return ListView(
            padding: EdgeInsets.all(16),
            children: [
              Text('Location', style: Theme.of(context).textTheme.titleLarge),

              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest,
                surfaceTintColor: colorScheme.surfaceTint,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    RadioListTile<bool>(
                      title: Text('Use Current GPS Location', style: Theme.of(context).textTheme.titleMedium,),
                      value: true,
                      groupValue: provider.useCurrentLocation,
                      onChanged: (value) => provider.setLocationMode(true),
                    ),
                    RadioListTile<bool>(
                      title: Text('Use a Fixed Custom Location', style: Theme.of(context).textTheme.titleMedium,),
                      value: false,
                      groupValue: provider.useCurrentLocation,
                      onChanged: (value) => provider.setLocationMode(false),
                    ),
                    if (!provider.useCurrentLocation)
                      ListTile(
                        title: Text(provider.customLat != null
                            ? 'Lat: ${provider.customLat?.toStringAsFixed(4)}, Lon: ${provider.customLon?.toStringAsFixed(4)}'
                            : 'No location set'),
                        subtitle: const Text('Hint: Use gps-coordinates.net to get Lat/Lon'),
                        trailing: const Icon(Icons.edit),
                        onTap: () => openBottomModal(provider, context),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              Text('Notifications', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),

              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest,
                surfaceTintColor: colorScheme.surfaceTint,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.symmetric(horizontal: 16.0),
                        title: Text(
                          'Enable Rain Alerts',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        value: provider.notificationsEnabled,
                        onChanged: provider.toggleNotifications,
                      ),
                      const SizedBox(height: 12),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Wrap(
                          children: [
                            Text(
                              'Coverage Radius: ${provider.radiusKm.toStringAsFixed(0)} km',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'Pro Tip: 20km is the sweet spot!',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Slider(
                          value: provider.radiusKm,
                          min: 5,
                          max: 100,
                          divisions: 19,
                          label: '${provider.radiusKm.toStringAsFixed(0)} km',
                          onChanged: provider.updateRadiusLive,
                          onChangeEnd: provider.saveRadius,
                        ),
                      ),

                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          children: [
                            Text(
                              'Check Frequency:',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: provider.notificationFrequency,
                                onChanged: !provider.notificationsEnabled
                                    ? (int? newValue) {
                                  if (newValue != null) {
                                    provider.updateNotificationFrequency(newValue);
                                  }
                                }
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                                dropdownColor: colorScheme.surface,
                                items: <int>[15, 30, 45, 60]
                                    .map((int value) => DropdownMenuItem<int>(
                                  value: value,
                                  child: Text('$value minutes'),
                                ))
                                    .toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
