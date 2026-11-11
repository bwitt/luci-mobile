import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/screens/interfaces_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/services/router_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/app_state_provider.dart';

void main() {
  testWidgets('leaving the screen disposes its scroll controller', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    late final AppState state;
    // Built outside the fake-async zone, whose microtasks do not run while
    // runAsync awaits real storage.
    await tester.runAsync(() async {
      final routers = RouterService();
      state = AppState.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
        routerService: routers,
      );
      await routers.addRouter(
        model.Router(
          id: 'router',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'password',
          useHttps: false,
        ),
      );
      await state.fetchDashboardData();
    });
    expect(state.dashboardData, isNotNull);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: MaterialApp(
          localizationsDelegates: luciLocalizationsDelegates,
          home: const InterfacesScreen(),
        ),
      ),
    );
    await tester.pump();
    final controller = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;

    await tester.pumpWidget(const SizedBox());

    expect(() => controller.addListener(() {}), throwsFlutterError);
  });
}
