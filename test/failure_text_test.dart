import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:luci_mobile/l10n/failure_text.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/app_failure.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/utils/format_bytes.dart';

/// A context with the app's localizations in [locale].
Future<BuildContext> _contextFor(
  WidgetTester tester, [
  Locale locale = const Locale('en'),
]) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: luciLocalizationsDelegates,
      supportedLocales: const [Locale('en'), Locale('de')],
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

DioException _http(int status, {String? call}) => DioException.badResponse(
  statusCode: status,
  requestOptions: RequestOptions(
    path: '/cgi-bin/luci/admin/ubus',
    extra: {rpcCallExtra: ?call},
  ),
  response: Response(
    requestOptions: RequestOptions(path: '/'),
    statusCode: status,
  ),
);

void main() {
  group('apiErrorText', () {
    testWidgets('words each kind of router failure', (tester) async {
      final context = await _contextFor(tester);
      String text(Object error) => apiErrorText(context, error);

      expect(text(_http(403)), contains('rejected this session'));
      expect(text(_http(500)), 'The router returned HTTP 500.');
      expect(
        text(_http(502, call: 'luci-rpc.getDHCPLeases')),
        'The router returned HTTP 502. (luci-rpc.getDHCPLeases)',
      );
      expect(
        text(const SocketException('No route to host')),
        startsWith('Could not connect to the router.'),
      );
      expect(
        text(const RpcException(object: 'uci', method: 'set', status: 6)),
        contains('permission for uci.set'),
      );
      expect(
        text(const RpcException(object: 'iwinfo', method: 'scan', status: 4)),
        'iwinfo.scan is unavailable. Install rpcd-mod-iwinfo, restart rpcd, '
        'then reconnect.',
      );
      expect(
        text(
          const RpcException(
            object: 'file',
            method: 'exec',
            detail: 'Command failed',
          ),
        ),
        'The router refused file.exec: Command failed.',
      );
      // A bare ubus status still says which failure it was.
      expect(
        text(const RpcException(object: 'file', method: 'exec', status: 7)),
        'The router refused file.exec: Request timed out (ubus status 7).',
      );
      expect(
        text(const RpcException(object: 'file', method: 'exec')),
        'The router refused file.exec.',
      );
      expect(text(Exception('Something odd')), 'Something odd');
    });

    // The router's own words and the call name stay as they are; the
    // sentence around them is translated.
    testWidgets('translates the sentence, not the call', (tester) async {
      final context = await _contextFor(tester, const Locale('de'));
      final text = apiErrorText(
        context,
        const RpcException(object: 'uci', method: 'set', status: 6),
      );
      expect(text, contains('uci.set'));
      expect(text, isNot(contains('does not have permission')));
    });
  });

  group('appFailureText', () {
    testWidgets('names what failed and why', (tester) async {
      final context = await _contextFor(tester);

      expect(
        appFailureText(context, const AppFailure(AppFailureKind.fetch)),
        "Could not read the router's status.",
      );
      expect(
        appFailureText(
          context,
          AppFailure(AppFailureKind.radioRestart, cause: _http(500)),
        ),
        'Could not restart the radio. The router returned HTTP 500.',
      );
      expect(
        appFailureText(
          context,
          const AppFailure(AppFailureKind.wifiConnect, subject: 'CoffeeShop'),
        ),
        'Could not connect to CoffeeShop.',
      );
      expect(
        appFailureText(
          context,
          const AppFailure(AppFailureKind.radioDisabledForConnect),
        ),
        'Enable ? before connecting.',
      );
    });

    testWidgets('has words for every kind of failure', (tester) async {
      final context = await _contextFor(tester);
      final texts = {
        for (final kind in AppFailureKind.values)
          appFailureText(context, AppFailure(kind, subject: 'radio0')),
      };
      expect(texts, hasLength(AppFailureKind.values.length));
      expect(texts, everyElement(isNotEmpty));
    });
  });

  test('AppFailure describes itself for logs', () {
    expect(
      const AppFailure(AppFailureKind.wifiConnect, subject: 'Home').toString(),
      'AppFailure(wifiConnect, Home)',
    );
    expect(
      AppFailure(AppFailureKind.fetch, cause: Exception('boom')).toString(),
      'AppFailure(fetch: Exception: boom)',
    );
  });

  group('formatBytes', () {
    test('picks the largest unit below 1024', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(-5), '0 B');
      expect(formatBytes(1), '1.0 B');
      expect(formatBytes(1023), '1023.0 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });

    test('stops at terabytes', () {
      const tb = 1024 * 1024 * 1024 * 1024;
      expect(formatBytes(2048 * tb), '2048.0 TB');
    });

    test('honours the requested precision', () {
      expect(formatBytes(1536, decimals: 2), '1.50 KB');
      expect(formatBytes(1536, decimals: 0), '2 KB');
    });
  });
}
