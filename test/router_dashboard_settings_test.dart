import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:luci_mobile/screens/router_dashboard_settings_screen.dart';

import 'helpers/screen_harness.dart';

void main() {
  // Each section's Show All switch sat in a coloured Container, which hid
  // its ink; Flutter asserts on that in debug builds.
  testWidgets('every section\'s switch shows its ink', (tester) async {
    final state = (await tester.runAsync(signedInAppState))!;
    await pumpScreen(
      tester,
      state,
      const RouterDashboardSettingsScreen(routerId: 'router'),
    );
    expect(tester.takeException(), isNull);

    // Only the first section starts open.
    for (final section in find.byType(ExpansionTile).evaluate().skip(1)) {
      await tester.tap(
        find
            .descendant(
              of: find.byWidget(section.widget),
              matching: find.byType(ListTile),
            )
            .first,
      );
      await tester.pumpAndSettle();
    }

    final switches = find.byType(SwitchListTile);
    expect(switches, findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });
}
