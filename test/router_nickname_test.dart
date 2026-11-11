import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/router.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/services/router_service.dart';
import 'package:luci_mobile/state/app_state.dart';

Router _router({String id = 'r', String? name, String? hostname}) => Router(
  id: id,
  ipAddress: '192.168.1.1',
  username: 'root',
  password: 'password',
  useHttps: false,
  lastKnownHostname: hostname,
  name: name,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Router nickname', () {
    test('a stored router without one still loads', () {
      final router = Router.fromJson({
        'id': '192.168.1.1-root',
        'ipAddress': '192.168.1.1',
        'username': 'root',
        'password': 'password',
        'useHttps': false,
      });
      expect(router.name, isNull);
      expect(router.toJson().containsKey('name'), isFalse);
    });

    test('survives a JSON round trip', () {
      final router = Router.fromJson(_router(name: 'Office').toJson());
      expect(router.name, 'Office');
      expect(router.id, 'r');
    });

    test('is trimmed, and a blank one is none', () {
      expect(_router(name: '  Home ').name, 'Home');
      expect(_router(name: '   ').name, isNull);
    });

    test('copyWith keeps it, and an empty one clears it', () {
      final router = _router(name: 'Home');
      expect(router.copyWith(password: 'new').name, 'Home');
      expect(router.copyWith(name: 'Office').name, 'Office');
      expect(router.copyWith(name: '').name, isNull);
    });

    test('display name prefers nickname, hostname, then address', () {
      expect(
        _router(name: 'Home', hostname: 'OpenWrt').displayName(hostname: 'gw'),
        'Home',
      );
      expect(_router(hostname: 'OpenWrt').displayName(hostname: 'gw'), 'gw');
      expect(_router(hostname: 'OpenWrt').displayName(hostname: ''), 'OpenWrt');
      expect(_router(hostname: '').displayName(), '192.168.1.1');
      expect(_router().displayName(address: '10.0.0.1'), '10.0.0.1');
    });

    test('matches the same address, account and nickname', () {
      final router = _router(name: 'Home');
      expect(router.matches('192.168.1.1', 'root', ' home '), isTrue);
      expect(router.matches('192.168.1.1', 'root', 'Office'), isFalse);
      expect(router.matches('192.168.1.1', 'root', null), isFalse);
      expect(router.matches('192.168.1.1', 'admin', 'Home'), isFalse);
      expect(_router().matches('192.168.1.1', 'root', ''), isTrue);
    });
  });

  group('two routers at the same address', () {
    late RouterService routers;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      routers = RouterService();
    });

    AppState stateFor() {
      final state = AppState.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
        routerService: routers,
      );
      addTearDown(state.dispose);
      return state;
    }

    test('new ids keep the old form while free, then get a suffix', () async {
      expect(routers.newRouterId('192.168.1.1', 'root'), '192.168.1.1-root');
      await routers.addRouter(_router(id: '192.168.1.1-root'));
      expect(routers.newRouterId('192.168.1.1', 'root'), '192.168.1.1-root-2');
      await routers.addRouter(_router(id: '192.168.1.1-root-2'));
      expect(routers.newRouterId('192.168.1.1', 'root'), '192.168.1.1-root-3');
      expect(routers.newRouterId('192.168.1.2', 'root'), '192.168.1.2-root');
    });

    test('can both be added under different nicknames', () async {
      final state = stateFor();

      for (final name in ['Home', 'Office']) {
        expect(
          await state.login(
            '192.168.1.1',
            'root',
            'password-$name',
            false,
            name: name,
            asNewRouter: true,
          ),
          isTrue,
        );
      }

      expect(routers.routers.map((r) => r.id), [
        '192.168.1.1-root',
        '192.168.1.1-root-2',
      ]);
      expect(routers.routers.map((r) => r.name), ['Home', 'Office']);
      expect(routers.routers.map((r) => r.password), [
        'password-Home',
        'password-Office',
      ]);

      // Both are kept across a restart.
      final restarted = RouterService();
      await restarted.loadRouters();
      expect(restarted.routers.map((r) => r.name), ['Home', 'Office']);
    });

    test('signing in from the login screen updates the saved one', () async {
      await routers.addRouter(_router(id: '192.168.1.1-root', name: 'Home'));
      final state = stateFor();

      expect(
        await state.login('192.168.1.1', 'root', 'changed', false),
        isTrue,
      );

      expect(routers.routers, hasLength(1));
      expect(routers.routers.single.id, '192.168.1.1-root');
      expect(routers.routers.single.name, 'Home');
      expect(routers.routers.single.password, 'changed');
    });

    test('signing in from the login screen updates the selected one', () async {
      await routers.addRouter(_router(id: '192.168.1.1-root', name: 'Home'));
      await routers.addRouter(
        _router(id: '192.168.1.1-root-2', name: 'Office'),
      );
      routers.selectRouter('192.168.1.1-root-2');
      final state = stateFor();

      expect(
        await state.login('192.168.1.1', 'root', 'changed', false),
        isTrue,
      );

      expect(routers.routers.map((r) => r.password), ['password', 'changed']);
      expect(routers.routers.map((r) => r.name), ['Home', 'Office']);
    });
  });
}
