import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/services/router_service.dart';
import 'package:luci_mobile/services/throughput_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/app_state_provider.dart';

/// An [AppState] signed in to one router served by the reviewer fixtures,
/// with the dashboard already fetched.
///
/// Call from `tester.runAsync`: the fixtures answer after real delays.
/// [create] builds a subclass in place of the plain test state.
Future<AppState> signedInAppState({
  IApiService? api,
  AppState Function(IApiService api, RouterService routers)? create,
}) async {
  // The fixtures are assets, and the bundle caches each load as a future.
  // One a previous test left unfinished, in a fake-async zone that is gone,
  // would never complete here.
  rootBundle.clear();
  FlutterSecureStorage.setMockInitialValues({});
  final routers = RouterService();
  await routers.addRouter(
    model.Router(
      id: 'router',
      ipAddress: '192.168.1.1',
      username: 'root',
      password: 'password',
      useHttps: false,
    ),
  );
  final apiService = api ?? MockApiService();
  final state =
      create?.call(apiService, routers) ??
      AppState.forTesting(
        apiService: apiService,
        authService: MockAuthService(),
        routerService: routers,
        throughputService: ThroughputService(),
      );
  await state.fetchDashboardData();
  return state;
}

/// Pumps [screen] over [state] on a phone-sized surface and lets the
/// screen's own loads finish.
Future<void> pumpScreen(
  WidgetTester tester,
  AppState state,
  Widget screen, {
  Map<String, WidgetBuilder> routes = const {},
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => state)],
      child: MaterialApp(
        localizationsDelegates: luciLocalizationsDelegates,
        home: screen,
        routes: routes,
      ),
    ),
  );
  await settle(tester);
}

/// Lets the fixtures' delayed answers land: they wait on real timers for
/// some calls and on fake ones for others.
Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }
}

/// Unmounts the tree, which disposes the state and cancels its timers
/// before the test checks for pending ones.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// Runs [body] letting framework errors whose message contains [fragment]
/// through. Only for a bug that a separate, skipped test documents.
Future<void> toleratingKnownBug(
  String fragment,
  Future<void> Function() body,
) async {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains(fragment)) return;
    previous?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
}
