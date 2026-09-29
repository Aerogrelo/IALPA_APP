import 'package:flutter/material.dart';

import 'change_of_duty_input_screen.dart';
import 'fleet_selection_screen.dart';
import 'max_duty_input_screen.dart';

/// Second screen: once a fleet is chosen, which convenio group to check.
///
/// Added 29/09 when Change of Duty (Group A) became the second available
/// check, alongside the existing Maximum Duty (Group D) — this screen is
/// what makes room for that choice without cluttering fleet selection.
class CheckTypeScreen extends StatelessWidget {
  const CheckTypeScreen({super.key, required this.fleet});

  final Fleet fleet;

  @override
  Widget build(BuildContext context) {
    final fleetLabel = fleet == Fleet.a320 ? 'A320/321' : 'A330';

    return Scaffold(
      // Short on purpose (30/09): the longer 'What do you want to check? —
      // $fleetLabel' truncated on an iPhone-width screen, found by testing
      // in a 375px-wide viewport.
      appBar: AppBar(title: Text('$fleetLabel — check type')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CheckTypeButton(
                label: 'Maximum Duty',
                subtitle: 'Clause 3.10/3.11 — is this duty within the '
                    'maximum flight duty time?',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MaxDutyInputScreen(fleet: fleet),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _CheckTypeButton(
                label: 'Change of Duty',
                subtitle: 'Clause 3.2 — does a schedule change the '
                    'airline is proposing stay within the agreed window?',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChangeOfDutyInputScreen(fleet: fleet),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckTypeButton extends StatelessWidget {
  const _CheckTypeButton({
    required this.label,
    required this.subtitle,
    required this.onPressed,
  });

  final String label;
  final String subtitle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
