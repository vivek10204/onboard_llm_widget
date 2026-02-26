//IMP: Diff from example (new)


import 'package:flutter/material.dart';

class SearchParametersSection extends StatelessWidget {
  final double threshold;
  final int topK;
  final ValueChanged<double> onThresholdChanged;
  final ValueChanged<int> onTopKChanged;

  const SearchParametersSection({
    super.key,
    required this.threshold,
    required this.topK,
    required this.onThresholdChanged,
    required this.onTopKChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '  Search Parameters',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.cyanAccent), //TBD1
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Threshold: ${threshold.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 12, color: Colors.cyanAccent) //TBD1
                  ),
                  Slider(
                    value: threshold,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    onChanged: onThresholdChanged,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Top K: $topK',
                      style: TextStyle(fontSize: 12, color: Colors.cyanAccent) //TBD1
                  ),
                  Slider(
                    value: topK.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    onChanged: (value) => onTopKChanged(value.round()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}