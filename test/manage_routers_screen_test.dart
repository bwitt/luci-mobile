import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/main.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/screens/manage_routers_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';

void main() {
  testWidgets('fallback removal requires confirmation', (tester) async {
    final state = _TestAppState(
      model.Router(
        id: 'router',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password',
        useHttps: false,
        alternateAddress: 'router.example.com',
        alternateUseHttps: true,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: const MaterialApp(home: ManageRoutersScreen()),
      ),
    );

    await tester.tap(find.byTooltip('Remove fallback address'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(state.updatedRouter, isNull);

    await tester.tap(find.byTooltip('Remove fallback address'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(state.updatedRouter?.hasFallback, isFalse);
  });

  testWidgets('a nickname can be set and cleared', (tester) async {
    final state = _TestAppState(
      model.Router(
        id: 'router',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password',
        useHttps: false,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: const MaterialApp(home: ManageRoutersScreen()),
      ),
    );

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Office');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(state.updatedRouter?.name, 'Office');
    expect(state.updatedRouter?.id, 'router');

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(state.updatedRouter?.name, isNull);
  });

  testWidgets('the same address can be added under another nickname', (
    tester,
  ) async {
    final state = _TestAppState(
      model.Router(
        id: '192.168.1.1-root',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password',
        useHttps: false,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: const MaterialApp(home: ManageRoutersScreen()),
      ),
    );

    await tester.tap(find.text('Add Router'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Router Address'),
      '192.168.1.1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'other',
    );
    final add = find.widgetWithText(ElevatedButton, 'Add');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.textContaining('Router already exists'), findsOneWidget);
    expect(state.loggedInAs, isNull);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nickname (optional)'),
      'Office',
    );
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(state.loggedInAs, ('192.168.1.1', 'root', 'Office', true));
  });
}

class _TestAppState extends AppState {
  _TestAppState(this.router)
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

  final model.Router router;
  model.Router? updatedRouter;
  (String, String, String?, bool)? loggedInAs;

  @override
  List<model.Router> get routers => [router];

  @override
  Future<void> updateRouter(model.Router router) async =>
      updatedRouter = router;

  @override
  Future<bool> login(
    String ip,
    String user,
    String pass,
    bool useHttps, {
    bool fromRouter = false,
    String? alternateAddress,
    bool? alternateUseHttps,
    int activeAddressIndex = 0,
    String? name,
    bool asNewRouter = false,
    BuildContext? context,
  }) async {
    loggedInAs = (ip, user, name, asNewRouter);
    return true;
  }
}
