import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/dashboards_provider.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardsAsync = ref.watch(dashboardsProvider);
    final defaultDashboard = ref.watch(defaultDashboardProvider);

    return dashboardsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (dashboards) {
        if (dashboards.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/dashboards');
          });
          return const Scaffold(body: SizedBox.shrink());
        }

        final target = defaultDashboard ?? dashboards.first;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go('/dashboards/${target.id}');
        });
        return const Scaffold(body: SizedBox.shrink());
      },
    );
  }
}
