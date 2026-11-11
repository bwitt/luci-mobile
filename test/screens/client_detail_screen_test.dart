import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/screens/client_detail_screen.dart';
import 'package:luci_mobile/services/client_alias_store.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/utils/uci_values.dart';

import '../helpers/screen_harness.dart';

/// The fixtures' Amazon Echo: wireless, with a lease and station data.
Future<(AppState, Client)> _echo(WidgetTester tester) async {
  final state = (await tester.runAsync(signedInAppState))!;
  final clients = (await tester.runAsync(state.fetchClientsForSelectedRouter))!;
  return (state, clients.firstWhere((c) => c.hostname == 'Amazon-Echo'));
}

void main() {
  testWidgets('shows the station, traffic and addresses of a client', (
    tester,
  ) async {
    final (state, echo) = await _echo(tester);
    await pumpScreen(tester, state, ClientDetailScreen(client: echo));

    expect(find.text('Amazon-Echo'), findsWidgets);
    expect(find.text('-44 dBm'), findsOneWidget);
    expect(find.text('49 dB'), findsOneWidget);
    expect(find.text('3.3 GB'), findsOneWidget);
    expect(find.text('192.168.1.106'), findsOneWidget);
    expect(find.text('fd42:1::6a'), findsOneWidget);
    expect(find.text('Block internet access'), findsOneWidget);

    await unmount(tester);
  });

  // A local alias is the default rename: see ClientAliasStore.
  testWidgets('renaming stores an alias on the phone, not the router', (
    tester,
  ) async {
    final (state, echo) = await _echo(tester);
    await pumpScreen(tester, state, ClientDetailScreen(client: echo));

    await tester.tap(find.byTooltip('Display name'));
    await settle(tester, rounds: 2);
    expect(find.text('Shown only in this app'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Kitchen speaker');
    await tester.pump();
    await tester.tap(find.text('Save').last);
    await settle(tester, rounds: 3);

    expect(find.text('Kitchen speaker'), findsWidgets);
    final alias = await tester.runAsync(
      () =>
          ClientAliasStore(SecureStorageService())
              .aliasFor('router', echo.macAddress),
    );
    expect(alias, 'Kitchen speaker');

    await unmount(tester);
  });

  testWidgets('reserving the address adds a static lease for this MAC', (
    tester,
  ) async {
    final (state, echo) = await _echo(tester);
    await pumpScreen(tester, state, ClientDetailScreen(client: echo));

    await tester.tap(find.text('Reserve this address'));
    await settle(tester, rounds: 2);
    // The current address is offered, with a warning that it is dynamic.
    expect(
      find.text('Inside the DHCP pool - may clash with a dynamic lease'),
      findsOneWidget,
    );
    await tester.tap(find.text('Save').last);
    await settle(tester);

    final hosts = (await tester.runAsync(() async {
      final dhcp = await uciConfigValues(
        state.apiService!,
        state.currentSession!,
        'dhcp',
      );
      return [for (final host in uciSections(dhcp, 'host')) host.value];
    }))!;
    final lease = hosts.where(
      (h) => '${h['mac']}'.toUpperCase() == echo.macAddress.toUpperCase(),
    );
    expect(lease, hasLength(1));
    expect(lease.single['ip'], '192.168.1.106');

    await unmount(tester);
  });
}
