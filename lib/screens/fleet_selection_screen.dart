import 'package:flutter/material.dart';

import 'check_type_screen.dart';

enum Fleet { a320, a330 }

/// First screen of the app: choose which fleet the pilot flies, so the
/// right set of rules (A320/321 or A330) is used for whatever check comes
/// next.
///
/// v1.0 scope note (29/09, updated same day): tapping a fleet now opens
/// [CheckTypeScreen], which offers Maximum Duty (Group D) and, as of
/// 29/09, Change of Duty (Group A) — the second end-to-end check built
/// for the app. Minimum Rest (Group B) is the natural next addition,
/// reusing this same fleet selection and check-type structure.
class FleetSelectionScreen extends StatelessWidget {
  const FleetSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('IALPA App')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Which fleet do you fly?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'You can check Maximum Flight Duty Time (clause '
                '3.10/3.11) or Change of Duty (clause 3.2). More checks '
                'coming soon.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 32),
              _FleetButton(
                label: 'A320 / A321 / Neo',
                onPressed: () => _openCheckType(context, Fleet.a320),
              ),
              const SizedBox(height: 16),
              _FleetButton(
                label: 'A330',
                onPressed: () => _openCheckType(context, Fleet.a330),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openCheckType(BuildContext context, Fleet fleet) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheckTypeScreen(fleet: fleet),
      ),
    );
  }
}

class _FleetButton extends StatelessWidget {
  const _FleetButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}
