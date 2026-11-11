import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:luci_mobile/screens/dashboard_screen.dart';

import 'helpers/screen_harness.dart';

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

void main() {
  // The card is 160 px wide: even "LuCI-WiFi-5G (5 GHz)" overflowed it.
  testWidgets('the fixture SSIDs fit their Wi-Fi cards', (tester) async {
    final state = (await tester.runAsync(signedInAppState))!;

    await pumpScreen(tester, state, const DashboardScreen());

    expect(find.textContaining('LuCI-WiFi'), findsWidgets);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('a long SSID is cut short with an ellipsis', (tester) async {
    const ssid = 'The-Neighbours-Very-Long-Network-Name';
    final state = (await tester.runAsync(signedInAppState))!;
    _renameSsids(state.dashboardData!, ssid);

    await pumpScreen(tester, state, const DashboardScreen());

    expect(tester.takeException(), isNull);
    final title = tester.widget<Text>(find.textContaining(ssid).first);
    expect(title.overflow, TextOverflow.ellipsis);
    await unmount(tester);
  });
}
