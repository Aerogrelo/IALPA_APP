import 'package:flutter/material.dart';

import '../models/rule_result.dart';

/// Shows the outcome of a single rule check as a 3-color semaphore, with
/// the applicable clause, the explanation, and the EASA reference when
/// there is one — the same [RuleResult] every rule in lib/rules already
/// returns, just rendered for a pilot to read.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.result});

  final RuleResult result;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    switch (result.color) {
      case RuleColor.green:
        color = Colors.green;
        label = 'COMPLIES';
        break;
      case RuleColor.amber:
        color = Colors.amber.shade800;
        label = 'OWC';
        break;
      case RuleColor.red:
        color = Colors.red;
        label = 'BREACHES EASA';
        break;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Clause: ${result.clause}',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(result.explanation, style: const TextStyle(fontSize: 15)),
            if (result.marginToOwc != null ||
                result.owcOverage != null ||
                result.marginToEasaLimit != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: result.color == RuleColor.green
                      ? Colors.green.shade50
                      : Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: result.color == RuleColor.green
                        ? Colors.green.shade100
                        : Colors.amber.shade100,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (result.marginToOwc != null)
                      Text(
                        'Margin: ${_fmt(result.marginToOwc!)} left before '
                        'this becomes OWC.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    if (result.owcOverage != null)
                      Text(
                        'This duty is ${_fmt(result.owcOverage!)} over the '
                        "agreement's normal maximum (OWC).",
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    if (result.marginToEasaLimit != null) ...[
                      if (result.marginToOwc != null ||
                          result.owcOverage != null)
                        const SizedBox(height: 4),
                      Text(
                        '${_fmt(result.marginToEasaLimit!)} left before '
                        'the EASA limit is exceeded.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (result.easaReference != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blueGrey.shade100),
                ),
                child: Text(
                  'EASA reference: ${result.easaReference}',
                  style:
                      const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),
            ],
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Check another duty'),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final hours = d.inMinutes ~/ 60;
    final minutes = d.inMinutes % 60;
    return '${hours}h${minutes.toString().padLeft(2, '0')}';
  }
}
