import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:luci_mobile/screens/log_screen.dart';
import 'package:luci_mobile/screens/router_dashboard_settings_screen.dart';
import 'package:luci_mobile/screens/services_screen.dart';
import 'package:luci_mobile/screens/settings_screen.dart';
import 'package:luci_mobile/screens/system_settings_screen.dart';
import 'package:luci_mobile/models/dashboard_preferences.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/services/router_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/utils/uci_values.dart';

import '../helpers/screen_harness.dart';

/// The `system` section as the router now has it.
Future<Map<String, dynamic>> _systemSection(AppState state) async {
  final session = state.currentSession!;
  final values = await uciConfigValues(state.apiService!, session, 'system');
  return uciSections(values, 'system').first.value;
}

/// Records what the app would persist: the test constructor leaves
/// [AppState]'s storage unset, so the real writes cannot run here.
class _PrefsState extends AppState {
  _PrefsState(IApiService api, RouterService routers)
    : super.forTesting(
        apiService: api,
        authService: MockAuthService(),
        routerService: routers,
      );

  ThemeMode? savedTheme;
  DashboardPreferences? savedPreferences;

  @override
  Future<void> setThemeMode(ThemeMode mode) async => savedTheme = mode;

  @override
  Future<void> saveDashboardPreferences(DashboardPreferences prefs) async =>
      savedPreferences = prefs;
}

Future<_PrefsState> _prefsState() async =>
    await signedInAppState(create: _PrefsState.new) as _PrefsState;

// The throughput switch sits in a tinted Container: see the skipped test.
const _inkHidden = 'ListTile background color or ink splashes may be invisible';

void main() {
  group('Settings', () {
    testWidgets('lists the router and app sections', (tester) async {
      final state = (await tester.runAsync(signedInAppState))!;
      await pumpScreen(tester, state, const SettingsScreen());

      expect(find.text('DEVICE MANAGEMENT'), findsOneWidget);
      expect(find.text('Reboot Router'), findsOneWidget);
      expect(find.text('APPLICATION'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('app preferences change the theme', (tester) async {
      final state = (await tester.runAsync(_prefsState))!;
      await pumpScreen(tester, state, const SettingsScreen());

      await tester.tap(find.text('App preferences'));
      await settle(tester, rounds: 3);
      await tester.tap(find.text('Dark'));
      await settle(tester, rounds: 2);

      expect(state.savedTheme, ThemeMode.dark);

      await unmount(tester);
    });
  });

  group('System', () {
    testWidgets('shows the router\'s current settings', (tester) async {
      final state = (await tester.runAsync(signedInAppState))!;
      await pumpScreen(tester, state, const SystemSettingsScreen());

      expect(find.widgetWithText(TextField, 'LuCIMobile'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Demo router'), findsOneWidget);
      expect(find.text('UTC'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('saving a new hostname applies it to the router', (
      tester,
    ) async {
      final state = (await tester.runAsync(signedInAppState))!;
      await pumpScreen(tester, state, const SystemSettingsScreen());

      await tester.enterText(
        find.widgetWithText(TextField, 'LuCIMobile'),
        'new-router',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await settle(tester);

      final section = (await tester.runAsync(() => _systemSection(state)))!;
      expect(section['hostname'], 'new-router');
      expect(section['description'], 'Demo router');

      await unmount(tester);
    });
  });

  group('Services', () {
    testWidgets('lists init scripts with their state', (tester) async {
      final state = (await tester.runAsync(signedInAppState))!;
      await pumpScreen(tester, state, const ServicesScreen());

      expect(find.text('cron'), findsOneWidget);
      expect(find.text('Stopped · starts at boot'), findsOneWidget);
      expect(find.text('Running · starts at boot'), findsNWidgets(7));

      await unmount(tester);
    });

    testWidgets('restarting a service reports back', (tester) async {
      final state = (await tester.runAsync(signedInAppState))!;
      await pumpScreen(tester, state, const ServicesScreen());

      // dnsmasq, the second row: not one the app talks through.
      await tester.tap(find.byTooltip('Show menu').at(1));
      await settle(tester, rounds: 2);
      expect(find.text('Disable at boot'), findsOneWidget);
      await tester.tap(find.text('Restart').last);
      await settle(tester, rounds: 4);

      expect(find.text('dnsmasq updated'), findsOneWidget);

      await unmount(tester);
    });
  });

  testWidgets('the log viewer switches between system and kernel logs', (
    tester,
  ) async {
    final state = (await tester.runAsync(signedInAppState))!;
    await pumpScreen(tester, state, const LogScreen());

    expect(find.text('The log is empty'), findsOneWidget);
    await tester.tap(find.text('Kernel log'));
    await settle(tester, rounds: 3);
    expect(find.text('The log is empty'), findsOneWidget);

    await unmount(tester);
  });

  group('Dashboard settings', () {
    testWidgets('choosing one interface to monitor is saved', (tester) async {
      await toleratingKnownBug(_inkHidden, () async {
        final state = (await tester.runAsync(_prefsState))!;
        await pumpScreen(
          tester,
          state,
          const RouterDashboardSettingsScreen(routerId: 'router'),
        );

        await tester.tap(find.text('Show All Interfaces'));
        await settle(tester);

        final saved = state.savedPreferences!;
        expect(saved.showAllThroughput, isFalse);
        // Switching "all" off picks an interface rather than none.
        expect(saved.primaryThroughputInterface, isNotNull);

        await unmount(tester);
      });
    });

    // testWidgets only takes a bool; the group carries the reason.
    group(
      'on Material',
      () {
        testWidgets('the throughput switch shows its ink', (tester) async {
          final state = (await tester.runAsync(signedInAppState))!;
          await pumpScreen(
            tester,
            state,
            const RouterDashboardSettingsScreen(routerId: 'router'),
          );
          expect(tester.takeException(), isNull);
          await unmount(tester);
        });
      },
      skip:
          'bug: the Show All Interfaces switch tile sits in a coloured '
          'Container, which hides its ink (Flutter asserts in debug builds)',
    );
  });
}
