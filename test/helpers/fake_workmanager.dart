import 'package:workmanager/workmanager.dart';

/// Stands in for WorkManager so tests never schedule real background work.
///
/// On a Linux host the plugin is backed by systemd user units, so without
/// this a test that turns the poll on installs a real timer on the machine
/// running the tests.
class FakeWorkmanager extends WorkmanagerPlatform {
  /// Whether registration succeeds; false refuses it, as iOS does.
  bool accepts = false;
  final registered = <String>[];
  final cancelled = <String>[];

  /// Installs a fresh fake. [Workmanager] picks its platform once, on first
  /// use, so it is created first and then overridden.
  static FakeWorkmanager install() {
    Workmanager();
    final fake = FakeWorkmanager();
    WorkmanagerPlatform.instance = fake;
    return fake;
  }

  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Duration? flexInterval,
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingPeriodicWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    ForegroundServiceConfig? foregroundServiceConfig,
  }) async {
    if (!accepts) throw UnsupportedError('No periodic tasks here');
    registered.add(uniqueName);
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async =>
      cancelled.add(uniqueName);
}
