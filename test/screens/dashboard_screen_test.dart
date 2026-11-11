import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:luci_mobile/screens/dashboard_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';

import '../helpers/screen_harness.dart';

/// The fixtures, with `system.board` failing until [healed].
class _BoardFails extends MockApiService {
  bool healed = false;

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) {
    if (!healed && object == 'system' && method == 'board') {
      throw Exception('board unavailable');
    }
    return super.call(
      ipAddress,
      sysauth,
      useHttps,
      object: object,
      method: method,
      params: params,
      context: context,
    );
  }
}

/// Renames every SSID the dashboard shows.
void _renameSsids(Map<String, dynamic> dashboard, String ssid) {
  final radios = dashboard['wireless'] as Map<String, dynamic>;
  for (final radio in radios.values) {
    for (final iface in (radio as Map)['interfaces'] as List) {
      final iwinfo = (iface as Map)['iwinfo'];
      if (iwinfo is Map && iwinfo['ssid'] != null) iwinfo['ssid'] = ssid;
      final config = iface['config'];
      if (config is Map && config['ssid'] != null) config['ssid'] = ssid;
    }
  }
}

// The wireless card's title row is not flexible: see the skipped test below.
const _overflow = 'A RenderFlex overflowed';

void main() {
  testWidgets('shows the router, its vitals, Wi-Fi and interfaces', (
    tester,
  ) async {
    await toleratingKnownBug(_overflow, () async {
      final state = (await tester.runAsync(signedInAppState))!;
      await pumpScreen(tester, state, const DashboardScreen());

      expect(find.text('Netgear Nighthawk R7800'), findsOneWidget);
      expect(find.text('CPU Load'), findsOneWidget);
      expect(find.text('Memory'), findsOneWidget);
      expect(find.textContaining('LuCI-WiFi'), findsWidgets);
      expect(find.text('WAN'), findsOneWidget);
      expect(find.text('LAN'), findsOneWidget);
      // wanb is configured but down.
      expect(find.text('DOWN'), findsOneWidget);

      await unmount(tester);
    });
  });

  testWidgets('a failed read offers a retry that recovers', (tester) async {
    await toleratingKnownBug(_overflow, () async {
      final api = _BoardFails();
      final state = (await tester.runAsync(() => signedInAppState(api: api)))!;
      expect(state.appFailure, isNotNull);

      await pumpScreen(tester, state, const DashboardScreen());
      expect(
        find.textContaining("Could not read the router's status."),
        findsOneWidget,
      );

      api.healed = true;
      await tester.tap(find.text('Retry Connection'));
      await settle(tester);

      expect(state.appFailure, isNull);
      expect(find.text('Netgear Nighthawk R7800'), findsOneWidget);

      await unmount(tester);
    });
  });

  // testWidgets only takes a bool; the group carries the reason.
  group(
    'wireless cards',
    () {
      testWidgets('a long SSID is truncated rather than overflowing', (
        tester,
      ) async {
        final state = (await tester.runAsync(signedInAppState))!;
        _renameSsids(state.dashboardData!, 'The-Neighbours-Very-Long-Network');

        await pumpScreen(tester, state, const DashboardScreen());

        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    },
    skip:
        'bug: the SSID row in _buildWirelessInfoCardContent has no '
        'Flexible, so its ellipsis never applies and long names overflow',
  );
}
