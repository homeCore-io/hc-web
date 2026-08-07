import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/api/history_api.dart';
import '../../core/models/history_entry.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/time_display_provider.dart';
import '../../design/tokens.dart';

// Provider for device history (keyed by device ID)
final _historyProvider =
    FutureProvider.family<List<HistoryEntry>, String>((ref, deviceId) async {
  final client = ref.watch(homecoreClientProvider);
  return HistoryApi(client).getHistory(deviceId);
});

class DeviceHistoryPage extends ConsumerWidget {
  final String deviceId;
  const DeviceHistoryPage({required this.deviceId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(_historyProvider(deviceId));
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text('History: $deviceId'),
        actions: [
          IconButton(
            tooltip: 'Reload history',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_historyProvider(deviceId)),
          ),
        ],
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(
                child: Text('No history data for the last 24 hours'));
          }

          final attrs = entries.map((e) => e.attribute).toSet().toList()
            ..sort();

          return DefaultTabController(
            length: attrs.length,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  tabs: attrs.map((a) => Tab(text: a)).toList(),
                ),
                Expanded(
                  child: TabBarView(
                    children: attrs.map((attr) {
                      final attrEntries = entries
                          .where((e) => e.attribute == attr)
                          .toList()
                        ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
                      return _AttributeChart(
                          attribute: attr,
                          entries: attrEntries,
                          primaryColor: primaryColor);
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AttributeChart extends ConsumerWidget {
  final String attribute;
  final List<HistoryEntry> entries;
  final Color primaryColor;

  const _AttributeChart(
      {required this.attribute,
      required this.entries,
      required this.primaryColor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = HcTokens.of(context);
    final isUtc = ref.watch(timeUtcProvider);
    if (entries.isEmpty) {
      return const Center(child: Text('No data'));
    }

    // Determine if boolean or numeric
    final isBool = entries.any((e) => e.value is bool);
    final isNumeric = entries.any((e) => e.value is num);

    if (!isBool && !isNumeric) {
      // String values — show as list
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final e = entries[entries.length - 1 - i];
          return ListTile(
            title: Text(e.value?.toString() ?? 'null'),
            subtitle: Text(fmtTime(e.recordedAt, utc: isUtc, showDate: true)),
            dense: true,
          );
        },
      );
    }

    // Build chart spots
    final now = DateTime.now();
    final minX = now
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch
        .toDouble();
    final maxX = now.millisecondsSinceEpoch.toDouble();

    final spots = entries.map((e) {
      final x = e.recordedAt.millisecondsSinceEpoch.toDouble();
      final y =
          isBool ? (e.value == true ? 1.0 : 0.0) : (e.value as num).toDouble();
      return FlSpot(x, y);
    }).toList();

    final allY = spots.map((s) => s.y).toList();
    final minY = allY.reduce((a, b) => a < b ? a : b);
    final maxY = allY.reduce((a, b) => a > b ? a : b);
    final yPad = (maxY - minY) == 0 ? 1.0 : (maxY - minY) * 0.1;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: LineChart(
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: isBool ? -0.1 : minY - yPad,
          maxY: isBool ? 1.1 : maxY + yPad,
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: isBool ? 40 : 50,
                getTitlesWidget: (val, meta) {
                  if (isBool) {
                    if (val == 1.0) {
                      return Text('ON', style: t.text.overlineStyle);
                    }
                    if (val == 0.0) {
                      return Text('OFF', style: t.text.overlineStyle);
                    }
                    return const SizedBox.shrink();
                  }
                  return Text(val.toStringAsFixed(1),
                      style: t.text.overlineStyle);
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: (maxX - minX) / 4,
                getTitlesWidget: (val, meta) {
                  final dt = DateTime.fromMillisecondsSinceEpoch(val.toInt());
                  // Named `at`, not `t`: `t` is the tokens here, and a DateTime
                  // shadowing them compiles right up until something asks for
                  // `t.text`.
                  final at = isUtc ? dt.toUtc() : dt.toLocal();
                  return Text(
                      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                      style: t.text.overlineStyle);
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: true),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: !isBool,
              isStepLineChart: isBool,
              color: primaryColor,
              barWidth: 2,
              dotData: FlDotData(show: spots.length < 50),
            ),
          ],
        ),
      ),
    );
  }
}
