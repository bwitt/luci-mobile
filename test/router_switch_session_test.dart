import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/app_failure.dart';
import 'package:luci_mobile/models/router.dart';
import 'package:luci_mobile/services/interfaces/auth_service_interface.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/services/router_service.dart';
import 'package:luci_mobile/state/app_state.dart';

const _home = '192.168.1.1';
const _office = '10.0.0.1';

/// Records which router every call went to.
class _Api extends MockApiService {
  final addresses = <String>[];

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
    addresses.add(ipAddress);
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

/// Refuses logins to [down], leaving the session alone as the real service
/// does.
class _Auth extends MockAuthService {
  final down = <String>{};
  final attempts = <String>[];

  @override
  Future<FallbackLoginResult> loginWithFallback({
    required String activeAddress,
    required bool activeHttps,
    required int activeIndex,
    String? fallbackAddress,
    bool? fallbackHttps,
    required String username,
    required String password,
    BuildContext? context,
  }) async {
    attempts.add(activeAddress);
    if (down.contains(activeAddress)) {
      return FallbackLoginResult(success: false, usedAddressIndex: 0);
    }
    return super.loginWithFallback(
      activeAddress: activeAddress,
      activeHttps: activeHttps,
      activeIndex: activeIndex,
      fallbackAddress: fallbackAddress,
      fallbackHttps: fallbackHttps,
      username: username,
      password: password,
      context: context,
    );
  }
}

Router _router(String address) => Router(
  id: '$address-root',
  ipAddress: address,
  username: 'root',
  password: 'password',
  useHttps: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RouterService routers;
  late _Api api;
  late _Auth auth;
  late AppState state;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    routers = RouterService();
    await routers.addRouter(_router(_home));
    await routers.addRouter(_router(_office));
    api = _Api();
    auth = _Auth();
    state = AppState.forTesting(
      apiService: api,
      authService: auth,
      routerService: routers,
    );
    addTearDown(state.dispose);
  });

  group('a switch to a router that cannot be signed in to', () {
    setUp(() async {
      await state.selectRouter('$_home-root');
      expect(state.appFailure, isNull);
      auth.down.add(_office);
      await state.selectRouter('$_office-root');
      api.addresses.clear();
    });

    test('drops the previous router\'s session', () async {
      expect(state.appFailure?.kind, AppFailureKind.login);
      expect(routers.selectedRouter!.ipAddress, _office);
      expect(state.sysauth, isNull);
      expect(state.currentSession, isNull);
    });

    // Retry used to fetch the previous router's dashboard and show it as
    // this one's.
    test(
      'Retry signs in to it again instead of asking the previous one',
      () async {
        await state.fetchDashboardData();

        expect(api.addresses, isNot(contains(_home)));
        expect(auth.attempts.last, _office);
        expect(state.appFailure?.kind, AppFailureKind.login);
      },
    );

    test('Retry loads it once it answers', () async {
      auth.down.clear();

      await state.fetchDashboardData();

      expect(state.appFailure, isNull);
      expect(state.dashboardData, isNotNull);
      expect(api.addresses, isNotEmpty);
      expect(api.addresses.toSet(), {_office});
    });
  });

  // Adding a router, or signing in to another one from the login screen,
  // signed in to it but left the old one selected.
  test('signing in to a new router selects it', () async {
    await state.selectRouter('$_home-root');
    const added = '172.16.0.1';

    expect(await state.login(added, 'root', 'password', false), isTrue);

    expect(routers.selectedRouter!.ipAddress, added);
    expect(routers.routers.map((r) => r.ipAddress), contains(added));
    expect(api.addresses.last, added);
  });
}
