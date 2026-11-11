import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/auth_service.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';

import 'helpers/fake_luci.dart';

/// Accepts one password, and only at the addresses in [reachable].
class _Router extends MockApiService {
  _Router({this.reachable = const {'192.168.1.1'}});

  final Set<String> reachable;
  final logins = <String>[];

  @override
  Future<String> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  }) async {
    logins.add(ipAddress);
    if (!reachable.contains(ipAddress)) throw Exception('unreachable');
    if (password != 'right') throw Exception('Login failed');
    return 'token-$ipAddress';
  }

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    if (!reachable.contains(ipAddress)) throw Exception('unreachable');
    return [0, <String, dynamic>{}];
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('logging in', () {
    test('a good password stores the session and credentials', () async {
      final auth = RealAuthService(_Router());

      await auth.login('192.168.1.1', 'root', 'right', false);

      expect(auth.isAuthenticated, isTrue);
      expect(auth.sysauth, 'token-192.168.1.1');
      expect(auth.ipAddress, '192.168.1.1');
      expect(auth.useHttps, isFalse);
      expect(await SecureStorageService().getCredentials(), {
        'ipAddress': '192.168.1.1',
        'username': 'root',
        'password': 'right',
        'useHttps': 'false',
      });
    });

    test('a wrong password leaves nothing behind', () async {
      final auth = RealAuthService(_Router());

      await auth.login('192.168.1.1', 'root', 'wrong', false);

      expect(auth.isAuthenticated, isFalse);
      expect(auth.sysauth, isNull);
      expect(
        (await SecureStorageService().getCredentials())['password'],
        isNull,
      );
    });

    test('logout forgets the session and the stored password', () async {
      final auth = RealAuthService(_Router());
      await auth.login('192.168.1.1', 'root', 'right', true);

      await auth.logout();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.ipAddress, isNull);
      expect(auth.useHttps, isFalse);
      expect(
        (await SecureStorageService().getCredentials()).values,
        everyElement(isNull),
      );
    });
  });

  group('falling back to the alternate address', () {
    test('the active address is used when it answers', () async {
      final api = _Router();
      final auth = RealAuthService(api);

      final result = await auth.loginWithFallback(
        activeAddress: '192.168.1.1',
        activeHttps: false,
        activeIndex: 0,
        fallbackAddress: '100.64.0.1',
        fallbackHttps: true,
        username: 'root',
        password: 'right',
      );

      expect(result.success, isTrue);
      expect(result.usedAddressIndex, 0);
      expect(api.logins, ['192.168.1.1']);
    });

    test('the other address is tried when the active one fails', () async {
      final api = _Router(reachable: {'192.168.1.1'});
      final auth = RealAuthService(api);

      // The alternate is active; the primary (index 0) is the fallback.
      final result = await auth.loginWithFallback(
        activeAddress: '100.64.0.1',
        activeHttps: true,
        activeIndex: 1,
        fallbackAddress: '192.168.1.1',
        fallbackHttps: false,
        username: 'root',
        password: 'right',
      );

      expect(result.success, isTrue);
      expect(result.usedAddressIndex, 0);
      expect(auth.ipAddress, '192.168.1.1');
      expect(auth.useHttps, isFalse);
      expect(api.logins, ['100.64.0.1', '192.168.1.1']);
    });

    test('no fallback is tried without its protocol', () async {
      final api = _Router(reachable: const {});
      final auth = RealAuthService(api);

      final result = await auth.loginWithFallback(
        activeAddress: '192.168.1.1',
        activeHttps: false,
        activeIndex: 0,
        fallbackAddress: '100.64.0.1',
        username: 'root',
        password: 'right',
      );

      expect(result.success, isFalse);
      expect(result.usedAddressIndex, 0);
      expect(api.logins, ['192.168.1.1']);
    });
  });

  group('auto-login', () {
    test('uses the credentials it is given', () async {
      final auth = RealAuthService(_Router());
      expect(
        await auth.tryAutoLogin('192.168.1.1', 'root', 'right', false),
        isTrue,
      );
    });

    test('falls back to the stored credentials', () async {
      await SecureStorageService().saveCredentials(
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'right',
        useHttps: true,
      );
      final auth = RealAuthService(_Router());

      expect(await auth.tryAutoLogin(null, null, null, null), isTrue);
      expect(auth.useHttps, isTrue);
    });

    test('with nothing stored there is nothing to try', () async {
      final api = _Router();
      final auth = RealAuthService(api);
      expect(await auth.tryAutoLogin('192.168.1.1', null, null, null), isFalse);
      expect(api.logins, isEmpty);
    });
  });

  test('router availability is whether system.board answers', () async {
    final auth = RealAuthService(_Router());
    expect(await auth.checkRouterAvailability('192.168.1.1', false), isTrue);
    expect(await auth.checkRouterAvailability('10.9.9.9', false), isFalse);
    expect(await auth.checkRouterAvailability('', false), isFalse);
  });

  group('against a real LuCI login form', () {
    late FakeLuci luci;

    setUp(() async => luci = await FakeLuci.start());
    tearDown(() => luci.close());

    test('keeps the protocol the router answered on', () async {
      final auth = RealAuthService(RealApiService());

      await auth.login(luci.host, 'root', 'pw', false);

      expect(auth.sysauth, 'abc123==');
      expect(auth.useHttps, isFalse);
      expect(
        (await SecureStorageService().getCredentials())['useHttps'],
        'false',
      );
    });

    // No cookie means LuCI did not accept the password. The HTTPS retry
    // that follows finds no TLS on this port and gives up too.
    test('no session cookie is a failed login', () async {
      luci.loginCookie = null;
      final auth = RealAuthService(RealApiService());

      await auth.login(luci.host, 'root', 'pw', false);

      expect(auth.isAuthenticated, isFalse);
    });
  });
}
