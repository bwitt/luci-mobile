import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/models/router_event.dart';
import 'package:luci_mobile/services/background_monitor.dart';
import 'package:luci_mobile/services/background_worker.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/services/notification_service.dart';
import 'package:luci_mobile/services/router_service.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/notifications_notifier.dart';

import 'helpers/fake_workmanager.dart';

class _Permission extends NotificationService {
  _Permission({required this.granted});
  final bool granted;

  @override
  Future<bool> requestPermission() async => granted;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeWorkmanager workmanager;
  final store = SecureStorageService();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    workmanager = FakeWorkmanager.install();
    settleBackgroundStartup();
  });

  tearDown(() => onBackgroundPollChanged = null);

  /// A container whose selected router, if any, is reached through its
  /// alternate address.
  Future<ProviderContainer> containerFor({
    bool withRouter = true,
    bool permission = true,
  }) async {
    final routers = RouterService();
    if (withRouter) {
      await routers.addRouter(
        model.Router(
          id: 'r1',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'secret',
          useHttps: false,
          alternateAddress: 'router.example.com',
          alternateUseHttps: true,
          activeAddressIndex: 1,
        ),
      );
    }
    final state = AppState.forTesting(
      apiService: MockApiService(),
      authService: MockAuthService(),
      routerService: routers,
    );
    final container = ProviderContainer(
      overrides: [
        appStateProvider.overrideWith((ref) => state),
        notificationServiceProvider.overrideWithValue(
          _Permission(granted: permission),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(notificationSettingsProvider.future);
    return container;
  }

  NotificationSettingsNotifier notifier(ProviderContainer c) =>
      c.read(notificationSettingsProvider.notifier);

  NotificationSettings settings(ProviderContainer c) =>
      c.read(notificationSettingsProvider).requireValue;

  test('starts off with every notifiable kind selected', () async {
    final c = await containerFor();
    expect(settings(c).enabled, isFalse);
    expect(settings(c).kinds, notifiableKinds);
  });

  test('reads a poll that startup had to switch off', () async {
    await store.writeValue(BackgroundKeys.enabled, 'false');
    await store.writeValue(BackgroundKeys.schedulingFailed, 'true');
    final c = await containerFor();
    expect(settings(c).schedulingFailed, isTrue);
  });

  group('turning notifications on', () {
    test('schedules the poll for the address last reached', () async {
      workmanager.accepts = true;
      final c = await containerFor();

      await notifier(c).setEnabled(true);

      expect(settings(c).enabled, isTrue);
      expect(workmanager.registered, [BackgroundMonitor.taskName]);
      expect(await store.readValue(BackgroundKeys.enabled), 'true');
      final router = MonitoredRouter.fromJson(
        jsonDecode((await store.readValue(BackgroundKeys.router))!),
      )!;
      expect(router.ipAddress, 'router.example.com');
      expect(router.useHttps, isTrue);
    });

    test('a refused permission leaves it off and says so', () async {
      workmanager.accepts = true;
      final c = await containerFor(permission: false);

      await notifier(c).setEnabled(true);

      expect(settings(c).enabled, isFalse);
      expect(settings(c).permissionDenied, isTrue);
      expect(workmanager.registered, isEmpty);
    });

    test('without a saved router there is nothing to poll', () async {
      workmanager.accepts = true;
      final c = await containerFor(withRouter: false);

      await notifier(c).setEnabled(true);

      expect(settings(c).needsRouter, isTrue);
      expect(workmanager.registered, isEmpty);
    });

    // The credentials have no reader if the poll never runs.
    test('a refused registration switches off and drops the router', () async {
      final c = await containerFor();

      await notifier(c).setEnabled(true);

      expect(settings(c).enabled, isFalse);
      expect(settings(c).schedulingFailed, isTrue);
      expect(await store.readValue(BackgroundKeys.router), isNull);
      expect(await store.readValue(BackgroundKeys.schedulingFailed), 'true');
    });
  });

  test('turning notifications off cancels the poll', () async {
    workmanager.accepts = true;
    final c = await containerFor();
    await notifier(c).setEnabled(true);

    await notifier(c).setEnabled(false);

    expect(settings(c).enabled, isFalse);
    expect(workmanager.cancelled, [BackgroundMonitor.taskName]);
    expect(await store.readValue(BackgroundKeys.enabled), 'false');
    expect(await store.readValue(BackgroundKeys.router), isNull);
  });

  test('kinds are saved where the background poll reads them', () async {
    final c = await containerFor();

    await notifier(c).setKind(RouterEventKind.clientJoined, false);

    expect(settings(c).kinds, isNot(contains(RouterEventKind.clientJoined)));
    expect(
      await readNotificationKinds(store),
      notifiableKinds.difference({RouterEventKind.clientJoined}),
    );

    await notifier(c).setKind(RouterEventKind.clientJoined, true);
    expect(await readNotificationKinds(store), notifiableKinds);
  });

  // A write from somewhere with no screen of its own, such as deleting the
  // monitored router, must still move the switch.
  test('follows a change made elsewhere in storage', () async {
    workmanager.accepts = true;
    final c = await containerFor();
    await notifier(c).setEnabled(true);

    await forgetBackgroundRouter('r1', storage: store);
    await pumpEventQueue();

    expect(settings(c).enabled, isFalse);
  });
}
