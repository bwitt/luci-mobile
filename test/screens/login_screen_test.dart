import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/screens/login_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/services/router_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/app_state_provider.dart';

import '../helpers/screen_harness.dart';

/// The login screen as the app opens it, over the given saved [routers].
Future<AppState> _pumpLogin(
  WidgetTester tester, {
  List<model.Router> routers = const [],
  bool signedOut = false,
}) async {
  final state = (await tester.runAsync(() async {
    FlutterSecureStorage.setMockInitialValues({
      if (signedOut) 'signedOut': 'true',
    });
    final service = RouterService();
    for (final router in routers) {
      await service.addRouter(router);
    }
    return AppState.forTesting(
      apiService: MockApiService(),
      authService: MockAuthService(),
      routerService: service,
    );
  }))!;
  await tester.binding.setSurfaceSize(const Size(430, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => state)],
      child: MaterialApp(
        localizationsDelegates: luciLocalizationsDelegates,
        initialRoute: '/login',
        routes: {
          '/': (_) => const Text('Signed in'),
          '/login': (_) => const LoginScreen(),
        },
      ),
    ),
  );
  await settle(tester);
  return state;
}

Finder _field(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextField));

Future<void> _fillIn(
  WidgetTester tester, {
  required String address,
  String password = 'password',
}) async {
  await tester.enterText(_field('Router Address'), address);
  await tester.enterText(_field('Password'), password);
  await tester.pump();
}

void main() {
  testWidgets('a first start shows an empty form with root as the user', (
    tester,
  ) async {
    await _pumpLogin(tester);

    expect(find.text('Connect to your OpenWrt router'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'root'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('an impossible address is refused before connecting', (
    tester,
  ) async {
    final state = await _pumpLogin(tester);

    await _fillIn(tester, address: '192.168.1.300');
    await tester.tap(find.text('Connect'));
    await settle(tester, rounds: 2);

    expect(find.text('Invalid address format'), findsOneWidget);
    expect(state.routers, isEmpty);

    await unmount(tester);
  });

  // The port says HTTPS; the saved router must too, or every later call
  // goes out as plain HTTP to a TLS port.
  testWidgets('connecting saves the router with the protocol it implies', (
    tester,
  ) async {
    final state = await _pumpLogin(tester);

    await _fillIn(tester, address: '192.168.1.1:8443');
    await tester.tap(find.text('Connect'));
    await settle(tester);

    expect(find.text('Signed in'), findsOneWidget);
    final saved = state.routers.single;
    expect(saved.ipAddress, '192.168.1.1:8443');
    expect(saved.useHttps, isTrue);
    expect(saved.username, 'root');

    await unmount(tester);
  });

  testWidgets('a fallback the same as the primary address is refused', (
    tester,
  ) async {
    final state = await _pumpLogin(tester);

    await tester.tap(find.text('Add fallback address'));
    await tester.pump();
    await _fillIn(tester, address: 'router.lan');
    await tester.enterText(_field('Fallback Address'), 'http://router.lan/');
    await tester.tap(find.text('Connect'));
    await settle(tester, rounds: 2);

    // Same host and port, whatever the scheme and slashes.
    expect(find.text('Must differ from primary address'), findsOneWidget);
    expect(state.routers, isEmpty);

    await unmount(tester);
  });

  // After Log out the user expects to be asked for the password, but not
  // to type the address again.
  testWidgets('after signing out the last router is filled in, not its '
      'password', (tester) async {
    await _pumpLogin(
      tester,
      signedOut: true,
      routers: [
        model.Router(
          id: 'home',
          ipAddress: 'router.lan',
          username: 'admin',
          password: 'secret',
          useHttps: true,
          alternateAddress: '100.64.0.1',
          alternateUseHttps: false,
        ),
      ],
    );

    expect(find.text('Signed in'), findsNothing);
    // Bare `router.lan` would read as HTTP, so the scheme is spelt out.
    expect(
      find.widgetWithText(TextField, 'https://router.lan'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextField, 'admin'), findsOneWidget);
    expect(find.widgetWithText(TextField, '100.64.0.1'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'secret'), findsNothing);

    await unmount(tester);
  });

  testWidgets('a saved router that is not signed out signs straight in', (
    tester,
  ) async {
    await _pumpLogin(
      tester,
      routers: [
        model.Router(
          id: 'home',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'secret',
          useHttps: false,
        ),
      ],
    );

    expect(find.text('Signed in'), findsOneWidget);

    await unmount(tester);
  });
}
