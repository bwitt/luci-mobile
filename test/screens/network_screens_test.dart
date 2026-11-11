import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:luci_mobile/screens/firewall_screen.dart';
import 'package:luci_mobile/screens/interfaces_screen.dart';
import 'package:luci_mobile/screens/wifi_scan_screen.dart';
import 'package:luci_mobile/screens/wireless_screen.dart';

import '../helpers/screen_harness.dart';

void main() {
  group('Interfaces', () {
    testWidgets('lists wired and wireless interfaces with their addresses', (
      tester,
    ) async {
      final state = (await tester.runAsync(signedInAppState))!;
      await pumpScreen(tester, state, const InterfacesScreen());

      expect(find.text('WAN'), findsOneWidget);
      expect(find.text('dhcp • 100.64.0.123'), findsOneWidget);
      // An IPv6-only uplink shows its v6 address.
      expect(find.text('dhcpv6 • 2001:db8::1'), findsOneWidget);
      expect(find.text('LAN'), findsOneWidget);
      expect(find.text('static • 192.168.1.1'), findsOneWidget);
      expect(find.text('LuCI-WiFi-5G'), findsWidgets);

      await unmount(tester);
    });

    testWidgets('expanding a wired interface shows its details', (
      tester,
    ) async {
      final state = (await tester.runAsync(signedInAppState))!;
      await pumpScreen(tester, state, const InterfacesScreen());

      await tester.tap(find.text('WAN'));
      await settle(tester, rounds: 3);

      expect(find.text('Gateway'), findsOneWidget);
      expect(find.text('100.64.0.1'), findsOneWidget);
      expect(find.text('8.8.8.8, 8.8.4.4'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('a wireless interface opens its editor', (tester) async {
      final state = (await tester.runAsync(signedInAppState))!;
      await pumpScreen(tester, state, const InterfacesScreen());

      await tester.tap(find.text('LuCI-WiFi-5G').first);
      await settle(tester, rounds: 3);
      await tester.tap(find.text('Edit').first);
      await settle(tester, rounds: 3);

      expect(find.widgetWithText(TextField, 'LuCI-WiFi-5G'), findsOneWidget);

      await unmount(tester);
    });
  });

  group('Wireless', () {
    testWidgets('lists each radio with its networks', (tester) async {
      final state = (await tester.runAsync(signedInAppState))!;
      await pumpScreen(tester, state, const WirelessScreen());

      expect(find.text('2.4 GHz'), findsOneWidget);
      expect(find.text('Ch: 6 · HT40 · US'), findsOneWidget);
      expect(find.text('5 GHz'), findsOneWidget);
      expect(find.text('LuCI-WiFi'), findsOneWidget);
      expect(find.text('LuCI-WiFi-5G'), findsOneWidget);
      expect(find.text('Add network'), findsNWidgets(2));

      await unmount(tester);
    });

    testWidgets('a network opens prefilled for editing', (tester) async {
      final state = (await tester.runAsync(signedInAppState))!;
      await pumpScreen(tester, state, const WirelessScreen());

      await tester.tap(find.text('LuCI-WiFi-5G'));
      await settle(tester, rounds: 3);

      expect(find.widgetWithText(TextField, 'LuCI-WiFi-5G'), findsOneWidget);

      await unmount(tester);
    });
  });

  group('Firewall', () {
    testWidgets('has a tab for each kind of rule', (tester) async {
      final state = (await tester.runAsync(signedInAppState))!;
      await pumpScreen(tester, state, const FirewallScreen());

      expect(find.text('No port forwards yet'), findsOneWidget);

      Future<void> openTab(String name) async {
        await tester.ensureVisible(find.text(name));
        await tester.pumpAndSettle();
        await tester.tap(find.text(name));
        await settle(tester, rounds: 3);
      }

      await openTab('Zones');
      // The WAN zone masquerades and rejects inbound traffic.
      expect(find.text('NAT'), findsOneWidget);
      expect(find.text('REJECT'), findsNWidgets(2));
      expect(find.text('wan, wan6, wanb'), findsOneWidget);

      await openTab('Traffic rules');
      await openTab('Static routes');

      await unmount(tester);
    });

    testWidgets('adding a port forward opens the form', (tester) async {
      final state = (await tester.runAsync(signedInAppState))!;
      await pumpScreen(tester, state, const FirewallScreen());

      await tester.tap(find.text('Add port forward').first);
      await settle(tester, rounds: 3);

      expect(find.text('External port'), findsOneWidget);
      expect(find.text('Internal address'), findsOneWidget);
      // Defaults to forwarding from the WAN zone to the LAN zone.
      expect(find.text('wan'), findsOneWidget);
      expect(find.text('lan'), findsOneWidget);

      await unmount(tester);
    });
  });

  group('Wi-Fi scan', () {
    testWidgets('scanning lists nearby networks strongest first', (
      tester,
    ) async {
      final state = (await tester.runAsync(signedInAppState))!;
      await pumpScreen(tester, state, const WifiScanScreen());

      expect(
        find.textContaining('Select a radio and tap Scan'),
        findsOneWidget,
      );
      await tester.tap(find.text('Scan Networks'));
      await settle(tester);

      expect(find.text('Neighbor-WiFi'), findsOneWidget);
      expect(find.text('CoffeeShop-Free'), findsOneWidget);
      expect(find.text('Office-5G'), findsOneWidget);
      double top(String ssid) => tester.getTopLeft(find.text(ssid)).dy;
      expect(top('Neighbor-WiFi'), lessThan(top('Office-5G')));
      expect(top('Office-5G'), lessThan(top('CoffeeShop-Free')));
      expect(find.text('(Hidden Network)'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('a secured network needs a WPA-length password', (
      tester,
    ) async {
      final state = (await tester.runAsync(signedInAppState))!;
      await pumpScreen(tester, state, const WifiScanScreen());
      await tester.tap(find.text('Scan Networks'));
      await settle(tester);

      await tester.tap(find.text('Office-5G'));
      await settle(tester, rounds: 3);
      expect(find.text('WPA2 PSK (CCMP)'), findsOneWidget);

      await tester.tap(find.text('Connect'));
      await tester.pump();
      expect(
        find.text('Password is required for this network.'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'short');
      await tester.tap(find.text('Connect'));
      await tester.pump();
      expect(
        find.text('Password must be at least 8 characters.'),
        findsOneWidget,
      );

      await unmount(tester);
    });
  });
}
