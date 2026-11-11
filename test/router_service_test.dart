import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/router.dart';
import 'package:luci_mobile/services/router_service.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';

/// Keeps the routers and selected id in memory. The write of [slowId] waits
/// for [release], the way the storage plugin can finish calls out of order.
class _Storage extends SecureStorageService {
  _Storage(this.routers);

  final List<Router> routers;
  String? selectedId;
  String? slowId;
  final release = Completer<void>();

  @override
  Future<List<Router>> getRouters() async => [...routers];

  @override
  Future<void> saveRouters(List<Router> routers) async {}

  @override
  Future<String?> getSelectedRouterId() async => selectedId;

  @override
  Future<void> saveSelectedRouterId(String? id) async {
    if (id == slowId) await release.future;
    selectedId = id;
  }
}

Router _router(String id) => Router(
  id: id,
  ipAddress: '192.168.1.$id',
  username: 'root',
  password: 'password',
  useHttps: false,
);

void main() {
  test('two quick switches leave the later router saved', () async {
    final storage = _Storage([_router('1'), _router('2'), _router('3')]);
    final routers = RouterService(storage: storage);
    await routers.loadRouters();
    storage.slowId = '2';

    routers.selectRouter('2');
    routers.selectRouter('3');
    await pumpEventQueue();
    storage.release.complete();
    await pumpEventQueue();

    expect(routers.selectedRouter!.id, '3');
    expect(storage.selectedId, '3');
    // What the next launch restores.
    final restarted = RouterService(storage: storage);
    await restarted.loadRouters();
    expect(restarted.selectedRouter!.id, '3');
  });

  test('a removal after a switch saves the router it falls back to', () async {
    final storage = _Storage([_router('1'), _router('2')]);
    final routers = RouterService(storage: storage);
    await routers.loadRouters();
    storage.slowId = '2';

    routers.selectRouter('2');
    storage.routers.removeWhere((r) => r.id == '2');
    final removal = routers.removeRouter('2');
    await pumpEventQueue();
    storage.release.complete();
    await removal;

    expect(routers.selectedRouter!.id, '1');
    expect(storage.selectedId, '1');
  });
}
