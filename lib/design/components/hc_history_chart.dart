import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/models/history_entry.dart';
import '../tokens.dart';

/// A device attribute's recent history, as a compact trend.
///
/// This is the "alive" part: a temperature is a number, but a temperature over
/// the last day is a *story* — climbing, settling, spiking when the oven ran.
/// Styled to the design system (accent line, a wash of colour beneath, no
/// Material chrome) so it reads as part of the app, not a charting library
/// bolted on. Numeric only; the caller decides an attribute is chartable.
class HcHistoryChart extends StatelessWidget {
  const HcHistoryChart({
    super.key,
    required this.entries,
    this.height = 132,
    this.color,
  });

  /// Points for ONE attribute, in time order.
  final List<HistoryEntry> entries;
  final double height;

  /// The line/fill colour — each metric gets its own so a multisensor's charts
  /// read apart at a glance. Defaults to the house accent.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = HcTokens.of(context);

    final spots = <FlSpot>[
      for (final e in entries)
        if (e.value is num)
          FlSpot(
            e.recordedAt.millisecondsSinceEpoch.toDouble(),
            (e.value as num).toDouble(),
          ),
    ]..sort((a, b) => a.x.compareTo(b.x));

    if (spots.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Not enough history yet',
            style: t.text.bodySmallStyle.copyWith(color: t.surface.onBaseMuted),
          ),
        ),
      );
    }

    final ys = spots.map((s) => s.y).toList();
    var minY = ys.reduce((a, b) => a < b ? a : b);
    var maxY = ys.reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY) == 0 ? 1.0 : (maxY - minY) * 0.15;
    minY -= pad;
    maxY += pad;

    final accent = color ?? t.accent.active;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: spots.first.x,
          maxX: spots.last.x,
          minY: minY,
          maxY: maxY,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY - minY) <= 0 ? 1 : (maxY - minY) / 3,
            getDrawingHorizontalLine: (_) => FlLine(
              color: t.stroke.hairline,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                interval: (maxY - minY) <= 0 ? 1 : (maxY - minY) / 2,
                getTitlesWidget: (v, _) => Text(
                  v.toStringAsFixed(v.abs() < 10 ? 1 : 0),
                  // Below the ramp's floor, deliberately: axis ticks are
                  // furniture for the line, not text to read, and the ramp's
                  // smallest role would crowd a 34px gutter.
                  style: TextStyle(fontSize: 9, color: t.surface.onBaseMuted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 18,
                interval: (spots.last.x - spots.first.x) / 3,
                getTitlesWidget: (v, meta) {
                  // Skip the very edges, which fl_chart tends to clip.
                  if (v <= meta.min || v >= meta.max) {
                    return const SizedBox.shrink();
                  }
                  final dt =
                      DateTime.fromMillisecondsSinceEpoch(v.toInt()).toLocal();
                  return Text(
                    '${dt.hour.toString().padLeft(2, '0')}:00',
                    // Below the ramp's floor, deliberately: axis ticks are
                    // furniture for the line, not text to read, and the ramp's
                    // smallest role would crowd a 34px gutter.
                    style: TextStyle(fontSize: 9, color: t.surface.onBaseMuted),
                  );
                },
              ),
            ),
          ),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.25,
              preventCurveOverShooting: true,
              color: accent,
              barWidth: 2.4,
              dotData: const FlDotData(show: false),
              shadow:
                  Shadow(color: accent.withValues(alpha: 0.5), blurRadius: 8),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accent.withValues(alpha: 0.38),
                    accent.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
