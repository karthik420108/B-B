import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';

/// Simple line chart of a single test's numeric observations over time.
class ObservationTrendChart extends StatelessWidget {
  const ObservationTrendChart({super.key, required this.observations, this.height = 220});

  final List<Observation> observations;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Only numeric observations with a date can be plotted.
    final points = <({double value, double x})>[];
    for (final obs in observations) {
      final value = obs.value;
      final date = obs.date;
      if (!value.isFinite || date == null) continue;
      // Normalize x to days since the first point so large gaps render sanely.
      if (points.isEmpty) {
        points.add((value: value, x: 0));
      } else {
        final first = observations.first.date!;
        points.add((value: value, x: date.difference(first).inDays.toDouble()));
      }
    }
    if (points.length < 2) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.show_chart, color: theme.colorScheme.outline),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Not enough dated numeric results to plot a trend for this test yet.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final minX = points.map((p) => p.x).reduce((a, b) => a < b ? a : b);
    final maxX = points.map((p) => p.x).reduce((a, b) => a > b ? a : b);
    final minY = points.map((p) => p.value).reduce((a, b) => a < b ? a : b);
    final maxY = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final yPad = (maxY - minY).abs() < 0.0001 ? 1.0 : (maxY - minY) * 0.15;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX == minX ? minX + 1 : maxX,
          minY: minY - yPad,
          maxY: maxY + yPad,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (v, meta) => Text(
                  v.toStringAsFixed(v.abs() >= 100 ? 0 : 1),
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: maxX == minX ? 1 : (maxX - minX) / 4,
                getTitlesWidget: (v, meta) {
                  final days = v.round();
                  String label;
                  if (days == 0) {
                    label = 'Start';
                  } else if (days >= 90) {
                    label = '${(days / 30).round()} mo';
                  } else {
                    label = '$days d';
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(label, style: theme.textTheme.labelSmall),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((s) {
                final label = s.y.toStringAsFixed(s.y.abs() >= 100 ? 0 : 1);
                return LineTooltipItem(
                  label,
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: points.map((p) => FlSpot(p.x, p.value)).toList(),
              isCurved: true,
              color: theme.colorScheme.primary,
              barWidth: 3,
              belowBarData: BarAreaData(
                show: true,
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                  radius: 3.5,
                  color: theme.colorScheme.primary,
                  strokeWidth: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}