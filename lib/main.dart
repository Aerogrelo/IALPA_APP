import 'package:flutter/material.dart';

import 'screens/fleet_selection_screen.dart';

void main() {
  runApp(const IalpaApp());
}

/// Root of the app. Replaces the default Flutter counter demo (29/09) —
/// the app now starts on [FleetSelectionScreen], the first real screen.
class IalpaApp extends StatelessWidget {
  const IalpaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IALPA App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const FleetSelectionScreen(),
    );
  }
}
