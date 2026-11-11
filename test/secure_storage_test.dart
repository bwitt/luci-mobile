import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/router.dart';
import 'package:luci_mobile/services/client_alias_store.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';

Router _router(String id, {String ip = '192.168.1.1'}) => Router(
  id: id,
  ipAddress: ip,
  username: 'root',
  password: 'pw-$id',
  useHttps: false,
);

/// Storage that refuses writes, as a locked keystore does.
class _ReadOnlyStorage extends SecureStorageService {
  @override
  Future<void> writeValue(String key, String value) async =>
      throw Exception('keystore locked');

  @override
  Future<void> deleteValue(String key) async =>
      throw Exception('keystore locked');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecureStorageService storage;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    storage = SecureStorageService();
  });

  group('SecureStorageService', () {
    test('credentials round-trip and clear', () async {
      await storage.saveCredentials(
        ipAddress: '10.0.0.1',
        username: 'admin',
        password: 's3cret',
        useHttps: true,
      );
      expect(await storage.getCredentials(), {
        'ipAddress': '10.0.0.1',
        'username': 'admin',
        'password': 's3cret',
        'useHttps': 'true',
      });

      await storage.clearCredentials();
      expect((await storage.getCredentials()).values, everyElement(isNull));
    });

    // Logging out must not forget the saved routers or other settings.
    test('clearing credentials leaves routers and other keys alone', () async {
      await storage.saveRouters([_router('a')]);
      await storage.writeValue('themeMode', 'dark');
      await storage.saveCredentials(
        ipAddress: '10.0.0.1',
        username: 'admin',
        password: 's3cret',
        useHttps: false,
      );

      await storage.clearCredentials();

      expect(await storage.getRouters(), hasLength(1));
      expect(await storage.readValue('themeMode'), 'dark');
    });

    test('routers round-trip, update and delete by id', () async {
      expect(await storage.getRouters(), isEmpty);

      await storage.saveRouters([_router('a'), _router('b')]);
      await storage.updateRouter(_router('b', ip: '10.0.0.2'));
      await storage.deleteRouter('a');

      final routers = await storage.getRouters();
      expect(routers.map((r) => r.id), ['b']);
      expect(routers.single.ipAddress, '10.0.0.2');
      expect(routers.single.password, 'pw-b');
    });

    test('updating an unknown router changes nothing', () async {
      await storage.saveRouters([_router('a')]);
      await storage.updateRouter(_router('zzz', ip: '10.9.9.9'));
      final routers = await storage.getRouters();
      expect(routers.map((r) => r.id), ['a']);
      expect(routers.single.ipAddress, '192.168.1.1');
    });

    test('a corrupt routers entry reads as no routers', () async {
      FlutterSecureStorage.setMockInitialValues({'routers': '{not json'});
      expect(await SecureStorageService().getRouters(), isEmpty);
    });

    test('the selected router id can be set and cleared', () async {
      expect(await storage.getSelectedRouterId(), isNull);
      await storage.saveSelectedRouterId('a');
      expect(await storage.getSelectedRouterId(), 'a');
      await storage.saveSelectedRouterId(null);
      expect(await storage.getSelectedRouterId(), isNull);
    });

    test('the signed-out flag round-trips', () async {
      expect(await storage.isSignedOut(), isFalse);
      await storage.setSignedOut(true);
      expect(await storage.isSignedOut(), isTrue);
      await storage.setSignedOut(false);
      expect(await storage.isSignedOut(), isFalse);
    });

    test('generic values can be written, read and deleted', () async {
      await storage.writeValue('k', 'v');
      expect(await storage.readValue('k'), 'v');
      await storage.deleteValue('k');
      expect(await storage.readValue('k'), isNull);
    });
  });

  group('ClientAliasStore', () {
    late ClientAliasStore aliases;

    setUp(() => aliases = ClientAliasStore(storage));

    test('an alias is found whatever form the MAC is written in', () async {
      expect(
        await aliases.setAlias('r1', 'aa-bb-cc-dd-ee-ff', ' Living room TV '),
        isTrue,
      );
      expect(
        await aliases.aliasFor('r1', 'AA:BB:CC:DD:EE:FF'),
        'Living room TV',
      );
      expect(await aliases.load('r1'), {'AA:BB:CC:DD:EE:FF': 'Living room TV'});
    });

    test('aliases are kept per router', () async {
      await aliases.setAlias('r1', 'AA:BB:CC:DD:EE:FF', 'TV');
      expect(await aliases.aliasFor('r2', 'AA:BB:CC:DD:EE:FF'), isNull);
    });

    test('a blank alias clears it, and the last one removes the key', () async {
      await aliases.setAlias('r1', 'AA:BB:CC:DD:EE:01', 'one');
      await aliases.setAlias('r1', 'AA:BB:CC:DD:EE:02', 'two');

      await aliases.setAlias('r1', 'AA:BB:CC:DD:EE:01', '   ');
      expect(await aliases.load('r1'), {'AA:BB:CC:DD:EE:02': 'two'});

      await aliases.setAlias('r1', 'AA:BB:CC:DD:EE:02', null);
      expect(await aliases.load('r1'), isEmpty);
      expect(
        await storage.readValue(ClientAliasStore.storageKey('r1')),
        isNull,
      );
    });

    test('unreadable stored aliases read as none', () async {
      await storage.writeValue(ClientAliasStore.storageKey('r1'), '[1, 2]');
      expect(await aliases.load('r1'), isEmpty);
      await storage.writeValue(ClientAliasStore.storageKey('r1'), '{oops');
      expect(await aliases.load('r1'), isEmpty);
    });

    // The UI must not show a rename that did not stick.
    test('a refused write is reported, not swallowed', () async {
      final store = ClientAliasStore(_ReadOnlyStorage());
      expect(await store.setAlias('r1', 'AA:BB:CC:DD:EE:FF', 'TV'), isFalse);
      expect(await store.setAlias('r1', 'AA:BB:CC:DD:EE:FF', null), isFalse);
    });
  });
}
