import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/services/api_service.dart';

/// cgi-io's own split: unescaped whitespace separates arguments and a
/// backslash takes the next character literally.
List<String> _parseCommand(String line) {
  final args = <String>[];
  final current = StringBuffer();
  var escaped = false;
  var started = false;
  for (final char in line.split('')) {
    if (escaped) {
      current.write(char);
      escaped = false;
    } else if (char == r'\') {
      escaped = true;
      started = true;
    } else if (char.trim().isEmpty) {
      if (started) args.add(current.toString());
      current.clear();
      started = false;
    } else {
      current.write(char);
      started = true;
    }
  }
  if (started) args.add(current.toString());
  return args;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding answers every HTTP request with a 400; use real sockets.
  HttpOverrides.global = null;

  test('the command line is escaped the way cgi-io splits it', () {
    expect(
      cgiExecBody('sid', '/sbin/logread', ['-e', '^']),
      'sessionid=sid&command=%2Fsbin%2Flogread%20-e%20%5E&stderr=0',
    );

    final body = Uri.splitQueryString(
      cgiExecBody('s/d=', '/bin/echo', ['a b', r'c\d', 'tab\there']),
    );
    expect(body['sessionid'], 's/d=');
    expect(_parseCommand(body['command']!), [
      '/bin/echo',
      'a b',
      r'c\d',
      'tab\there',
    ]);
  });

  group('execDirect against a cgi-io stand-in', () {
    late HttpServer server;
    late String address;
    final requests = <(String, String, Map<String, String>)>[];
    var status = 200;
    var output = '';

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      requests.clear();
      status = 200;
      output = '';
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      address = '127.0.0.1:${server.port}';
      server.listen((request) async {
        final body = await utf8.decodeStream(request);
        requests.add((
          request.uri.path,
          request.headers.contentType?.mimeType ?? '',
          Uri.splitQueryString(body),
        ));
        request.response.statusCode = status;
        request.response.write(status == 200 ? output : 'refused');
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    // #96: rpcd's file.exec stops at 256 KiB; cgi-exec does not.
    test('posts the form LuCI posts and returns all of stdout', () async {
      output = [for (var i = 0; i < 6000; i++) 'line $i ${'x' * 60}']
          .join('\n');
      expect(output.length, greaterThan(256 * 1024));

      final result = await RealApiService().execDirect(
        address,
        'session-id',
        false,
        command: '/usr/libexec/syslog-wrapper',
      );

      expect(result, output);
      final (path, contentType, form) = requests.single;
      expect(path, '/cgi-bin/cgi-exec');
      expect(contentType, 'application/x-www-form-urlencoded');
      expect(form, {
        'sessionid': 'session-id',
        'command': '/usr/libexec/syslog-wrapper',
        'stderr': '0',
      });
    });

    test('bytes that are not UTF-8 do not fail the read', () async {
      await server.close(force: true);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      address = '127.0.0.1:${server.port}';
      server.listen((request) async {
        await request.drain<void>();
        request.response.add([0x6f, 0x6b, 0xff, 0x0a]);
        await request.response.close();
      });

      final result = await RealApiService().execDirect(
        address,
        'sid',
        false,
        command: '/bin/dmesg',
        params: ['-r'],
      );

      expect(result, startsWith('ok'));
    });

    for (final (http, ubus) in [(403, 6), (404, 4), (400, 2)]) {
      test('HTTP $http is ubus status $ubus', () async {
        status = http;

        await expectLater(
          RealApiService().execDirect(
            address,
            'sid',
            false,
            command: '/bin/dmesg',
            params: ['-r'],
          ),
          throwsA(isA<RpcException>().having((e) => e.status, 'status', ubus)),
        );
      });
    }
  });
}
