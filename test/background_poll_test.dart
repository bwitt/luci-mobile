import 'dart:convert';

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/router_event.dart';
import 'package:luci_mobile/services/background_monitor.dart';
import 'package:luci_mobile/services/background_worker.dart';
import 'package:luci_mobile/services/event_log.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/notification_service.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';

import 'helpers/fake_workmanager.dart';

const _router = MonitoredRouter(
  id: 'r1',
  ipAddress: '192.168.1.1',
  username: 'root',
  password: 'secret',
  useHttps: false,
);

final _t0 = DateTime.utc(2026, 11, 11, 12);

/// The three reads a background poll makes, answered from fields a test
/// can change between polls.
class _Router extends MockApiService {
  bool reachable = true;
  bool wanUp = true;
  List<Map<String, dynamic>> leases = [];
  int? uptime = 1000;
  bool dumpReadable = true;
  int logins = 0;

  void join(String mac, String name) =>
      leases.add({'macaddr': mac, 'hostname': name, 'ipaddr': '192.168.1.50'});

  @override
  Future<String> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  }) async {
    logins++;
    if (!reachable) throw Exception('No route to host');
    return 'sid';
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
    switch ('$object.$method') {
      case 'network.interface.dump':
        if (!dumpReadable) return [6];
        return [
          0,
          {
            'interface': [
              {
                'interface': 'wan',
                'up': wanUp,
                'route': [
                  {'target': '0.0.0.0', 'mask': 0},
                ],
              },
              {'interface': 'lan', 'up': true},
            ],
          },
        ];
      case 'luci-rpc.getDHCPLeases':
        return [
          0,
          {'dhcp_leases': leases},
        ];
      case 'system.info':
        if (uptime == null) throw Exception('Access denied');
        return [
          0,
          {'uptime': uptime},
        ];
    }
    return [4];
  }
}

class _Notifications extends NotificationService {
  final shown = <String>[];
  String? channel;

  @override
  Future<void> show(
    List<({RouterEvent event, String text})> items, {
    String channelName = NotificationService.channelName,
  }) async {
    shown.addAll(items.map((i) => i.text));
    channel = channelName;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecureStorageService store;
  late _Router router;
  late _Notifications notifications;
  late int factoryCalls;
  late FakeWorkmanager workmanager;

  setUp(() {
    workmanager = FakeWorkmanager.install();
    FlutterSecureStorage.setMockInitialValues({});
    store = SecureStorageService();
    router = _Router();
    notifications = _Notifications();
    factoryCalls = 0;
  });

  Future<void> enable() async {
    await store.writeValue(BackgroundKeys.enabled, 'true');
    await setMonitoredRouter(store, _router);
  }

  Future<void> poll(DateTime at) => runBackgroundPoll(
    storage: store,
    apiFactory: () {
      factoryCalls++;
      return router;
    },
    notifications: notifications,
    clock: () => at,
  );

  Future<List<RouterEventKind>> feed() async =>
      (await EventLog(store).load(_router.id)).map((e) => e.kind).toList();

  group('runBackgroundPoll', () {
    test('does nothing while the switch is off', () async {
      await setMonitoredRouter(store, _router);
      await poll(_t0);
      expect(factoryCalls, 0);
    });

    test('does nothing without a monitored router', () async {
      await store.writeValue(BackgroundKeys.enabled, 'true');
      await poll(_t0);
      expect(factoryCalls, 0);
    });

    // Off the network is not news.
    test('an unreachable router is neither recorded nor notified', () async {
      await enable();
      router.reachable = false;

      await poll(_t0);

      expect(router.logins, 1);
      expect(
        await store.readValue(BackgroundKeys.observation(_router.id)),
        isNull,
      );
      expect(notifications.shown, isEmpty);
    });

    test('the first poll only records a baseline', () async {
      await enable();
      router.join('AA:BB:CC:00:00:01', 'laptop');

      await poll(_t0);

      final stored = jsonDecode(
        (await store.readValue(BackgroundKeys.observation(_router.id)))!,
      );
      expect(stored, isA<Map<String, dynamic>>());
      expect(await feed(), isEmpty);
      expect(notifications.shown, isEmpty);
    });

    test('a new client is logged and notified in the user\'s words', () async {
      await enable();
      await poll(_t0);

      router.join('AA:BB:CC:00:00:02', 'phone');
      await poll(_t0.add(const Duration(minutes: 15)));

      expect(await feed(), [RouterEventKind.clientJoined]);
      expect(notifications.shown, ['phone joined the network']);
      expect(notifications.channel, 'Router events');
    });

    // The feed is the record; a departure is not worth waking anyone for.
    test('a client leaving is logged but not notified', () async {
      await enable();
      router.join('AA:BB:CC:00:00:02', 'phone');
      await poll(_t0);

      router.leases.clear();
      await poll(_t0.add(const Duration(minutes: 15)));

      expect(await feed(), [RouterEventKind.clientLeft]);
      expect(notifications.shown, isEmpty);
    });

    test('a kind the user switched off is logged but not notified', () async {
      await enable();
      await store.writeValue(
        BackgroundKeys.kinds,
        jsonEncode([RouterEventKind.wanDown.name]),
      );
      await poll(_t0);

      router.join('AA:BB:CC:00:00:02', 'phone');
      router.wanUp = false;
      await poll(_t0.add(const Duration(minutes: 15)));

      expect(
        await feed(),
        containsAll([RouterEventKind.clientJoined, RouterEventKind.wanDown]),
      );
      expect(notifications.shown, ['Internet connection went down']);
    });

    test('a falling uptime is notified as a reboot', () async {
      await enable();
      router.uptime = 50000;
      await poll(_t0);

      router.uptime = 120;
      await poll(_t0.add(const Duration(minutes: 15)));

      expect(await feed(), [RouterEventKind.rebooted]);
      expect(notifications.shown, ['Router rebooted']);
    });

    // The last reading stands, so a reboot across the gap is still seen
    // and a missing one is not invented.
    test('a poll without uptime keeps the last clocks', () async {
      await enable();
      router.uptime = 50000;
      await poll(_t0);

      router.uptime = null;
      await poll(_t0.add(const Duration(minutes: 15)));
      expect(await feed(), isEmpty);

      router.uptime = 60;
      await poll(_t0.add(const Duration(minutes: 30)));
      expect(await feed(), [RouterEventKind.rebooted]);
    });

    // Hours apart, "who joined" is everyone and means nothing.
    test('a stale baseline counts as a first poll', () async {
      await enable();
      await poll(_t0);

      router.join('AA:BB:CC:00:00:02', 'phone');
      await poll(_t0.add(const Duration(hours: 7)));

      expect(await feed(), isEmpty);
      expect(notifications.shown, isEmpty);
    });

    test('an unreadable interface dump skips the poll', () async {
      await enable();
      router.dumpReadable = false;

      await poll(_t0);

      expect(
        await store.readValue(BackgroundKeys.observation(_router.id)),
        isNull,
      );
    });

    test('notifications are capped, the feed is not', () async {
      await enable();
      await poll(_t0);

      for (var i = 0; i < 5; i++) {
        router.join('AA:BB:CC:00:00:1$i', 'device$i');
      }
      await poll(_t0.add(const Duration(minutes: 15)));

      expect(await feed(), hasLength(5));
      expect(notifications.shown, hasLength(BackgroundMonitor.maxPerPoll));
    });
  });

  group('settling the switch at startup', () {
    setUp(resetBackgroundStartup);
    tearDown(settleBackgroundStartup);

    test('settles straight away when the poll is off', () async {
      await ensureScheduled(storage: store);
      expect(backgroundStartupSettled, isTrue);
      expect(await store.readValue(BackgroundKeys.schedulingFailed), isNull);
    });

    test('re-registers an enabled poll without resetting its timer', () async {
      await enable();
      workmanager.accepts = true;

      await ensureScheduled(storage: store);

      expect(workmanager.registered, [BackgroundMonitor.taskName]);
      expect(await store.readValue(BackgroundKeys.enabled), 'true');
    });

    // As on iOS, which has no periodic tasks.
    test(
      'a registration refused twice switches the poll off and says why',
      () async {
        await enable();
        final waits = <Duration>[];

        await ensureScheduled(storage: store, delay: (d) async => waits.add(d));

        expect(waits, [const Duration(seconds: 2)]);
        // A task left by an earlier launch must not keep waking the app.
        expect(workmanager.cancelled, [BackgroundMonitor.taskName]);
        expect(await store.readValue(BackgroundKeys.enabled), 'false');
        expect(await store.readValue(BackgroundKeys.schedulingFailed), 'true');
        // Switching back on must not mean adding the router again.
        expect(await store.readValue(BackgroundKeys.router), isNotNull);
        expect(backgroundStartupSettled, isTrue);
      },
    );

    test('an unavailable WorkManager switches an enabled poll off', () async {
      await enable();

      await backgroundPollUnavailable(storage: store);

      expect(await store.readValue(BackgroundKeys.enabled), 'false');
      expect(await store.readValue(BackgroundKeys.schedulingFailed), 'true');
      expect(await store.readValue(BackgroundKeys.router), isNotNull);
      expect(backgroundStartupSettled, isTrue);
    });
  });

  group('following the selected router', () {
    Future<MonitoredRouter?> monitored() async {
      final raw = await store.readValue(BackgroundKeys.router);
      return raw == null ? null : MonitoredRouter.fromJson(jsonDecode(raw));
    }

    Future<void> seedBaseline() => store.writeValue(
      BackgroundKeys.observation(_router.id),
      '{"seeded": true}',
    );

    test('is a no-op while the poll is off', () async {
      await followSelectedRouter(_router, storage: store);
      expect(await monitored(), isNull);
    });

    // Same clients as a moment ago: the baseline stays.
    test('a new address for the same router keeps the baseline', () async {
      await enable();
      await seedBaseline();

      const moved = MonitoredRouter(
        id: 'r1',
        ipAddress: '100.64.0.1',
        username: 'root',
        password: 'secret',
        useHttps: true,
      );
      await followSelectedRouter(moved, storage: store);

      expect((await monitored())!.ipAddress, '100.64.0.1');
      expect(
        await store.readValue(BackgroundKeys.observation(_router.id)),
        isNotNull,
      );
    });

    test('a different router drops the old baseline', () async {
      await enable();
      const other = MonitoredRouter(
        id: 'r2',
        ipAddress: '10.0.0.1',
        username: 'root',
        password: 'x',
        useHttps: false,
      );
      await store.writeValue(BackgroundKeys.observation('r2'), '{}');

      await followSelectedRouter(other, storage: store);

      expect((await monitored())!.id, 'r2');
      expect(await store.readValue(BackgroundKeys.observation('r2')), isNull);
    });
  });

  group('readNotificationKinds', () {
    test('defaults to every notifiable kind', () async {
      expect(await readNotificationKinds(store), notifiableKinds);
      await store.writeValue(BackgroundKeys.kinds, '{"not": "a list"}');
      expect(await readNotificationKinds(store), notifiableKinds);
      await store.writeValue(BackgroundKeys.kinds, 'not json');
      expect(await readNotificationKinds(store), notifiableKinds);
    });

    // A stored kind that is not notifiable must not be smuggled in.
    test('keeps only known notifiable kinds', () async {
      await store.writeValue(
        BackgroundKeys.kinds,
        jsonEncode(['wanDown', 'routerUnreachable', 'bogus']),
      );
      expect(await readNotificationKinds(store), {RouterEventKind.wanDown});

      await store.writeValue(BackgroundKeys.kinds, '[]');
      expect(await readNotificationKinds(store), isEmpty);
    });
  });
}
