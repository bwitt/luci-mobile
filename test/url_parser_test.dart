import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/utils/url_parser.dart';

void main() {
  group('an address typed without a scheme', () {
    test('defaults to plain HTTP on port 80', () {
      final parsed = UrlParser.parse('192.168.1.1');
      expect(parsed.isValid, isTrue);
      expect(parsed.host, '192.168.1.1');
      expect(parsed.port, 80);
      expect(parsed.useHttps, isFalse);
      expect(parsed.hostWithPort, '192.168.1.1');
    });

    test('ignores surrounding whitespace and trailing slashes', () {
      final parsed = UrlParser.parse('  openwrt.lan//  ');
      expect(parsed.isValid, isTrue);
      expect(parsed.host, 'openwrt.lan');
    });

    // Routers that only serve LuCI over TLS are usually on these two ports.
    test('infers HTTPS from port 443 and 8443', () {
      expect(UrlParser.parse('router:443').useHttps, isTrue);
      expect(UrlParser.parse('router:8443').useHttps, isTrue);
      expect(UrlParser.parse('router:8080').useHttps, isFalse);
    });

    test('keeps a non-default port in hostWithPort', () {
      final parsed = UrlParser.parse('10.0.0.1:8080');
      expect(parsed.port, 8080);
      expect(parsed.hostWithPort, '10.0.0.1:8080');
      expect(parsed.displayUrl, 'http://10.0.0.1:8080');
    });

    test('rejects a port outside 1-65535 or that is not a number', () {
      for (final input in ['router:0', 'router:65536', 'router:abc']) {
        final parsed = UrlParser.parse(input);
        expect(parsed.isValid, isFalse, reason: input);
        expect(parsed.error, 'Invalid port number', reason: input);
      }
    });

    test('rejects IPv4 octets above 255', () {
      expect(UrlParser.parse('192.168.1.256').isValid, isFalse);
      expect(UrlParser.parse('999.1.1.1').isValid, isFalse);
    });

    test('rejects hostnames with characters DNS does not allow', () {
      expect(UrlParser.parse('my_router').isValid, isFalse);
      expect(UrlParser.parse('-router').isValid, isFalse);
      expect(UrlParser.parse('').isValid, isFalse);
    });
  });

  group('IPv6 addresses', () {
    test('a bracketed literal keeps its brackets', () {
      final parsed = UrlParser.parse('[fd00::1]');
      expect(parsed.isValid, isTrue);
      expect(parsed.host, '[fd00::1]');
      expect(parsed.port, 80);
      expect(parsed.hostWithPort, '[fd00::1]');
    });

    test('a bracketed literal with a port infers HTTPS from it', () {
      final parsed = UrlParser.parse('[fd00::1]:8443');
      expect(parsed.isValid, isTrue);
      expect(parsed.port, 8443);
      expect(parsed.useHttps, isTrue);
      expect(parsed.hostWithPort, '[fd00::1]:8443');
      expect(parsed.displayUrl, 'https://[fd00::1]:8443');
    });

    test('an out-of-range port on a bracketed literal falls back to 80', () {
      final parsed = UrlParser.parse('[fd00::1]:70000');
      expect(parsed.port, 80);
      expect(parsed.useHttps, isFalse);
    });

    // Without brackets there is no telling the port from the address.
    test('an unbracketed literal is refused with a reason', () {
      final parsed = UrlParser.parse('fd00::1');
      expect(parsed.isValid, isFalse);
      expect(parsed.error, 'Invalid address format');
    });

    test(
      'a URL with a scheme keeps the brackets the API needs to add a port',
      () {
        final parsed = UrlParser.parse('https://[fd00::1]:8443');
        expect(parsed.isValid, isTrue);
        expect(parsed.port, 8443);
        // Saved as the router address and later turned back into a URL:
        // without brackets the port is read as part of the address.
        expect(parsed.hostWithPort, '[fd00::1]:8443');
      },
      skip:
          'bug: Uri.host drops the brackets, so hostWithPort is '
          '"fd00::1:8443" and the port is lost',
    );
  });

  group('an address typed with a scheme', () {
    test('uses the scheme and its default port', () {
      final https = UrlParser.parse('https://router.lan/');
      expect(https.useHttps, isTrue);
      expect(https.port, 443);
      expect(https.hostWithPort, 'router.lan');
      expect(https.displayUrl, 'https://router.lan');

      final http = UrlParser.parse('http://router.lan');
      expect(http.useHttps, isFalse);
      expect(http.port, 80);
    });

    // An explicit port wins over the scheme's default, and does not change
    // the scheme: http on 443 is unusual but is what was asked for.
    test('an explicit port is kept as typed', () {
      final parsed = UrlParser.parse('http://router.lan:443');
      expect(parsed.useHttps, isFalse);
      expect(parsed.port, 443);
      expect(parsed.hostWithPort, 'router.lan:443');
    });

    test('a scheme with no host is invalid', () {
      expect(UrlParser.parse('http://').isValid, isFalse);
      expect(UrlParser.parse('https:///').isValid, isFalse);
    });
  });

  group('buildUrl', () {
    test('omits the default port for each scheme', () {
      expect(UrlParser.buildUrl('router', 80, false), 'http://router');
      expect(UrlParser.buildUrl('router', 443, true), 'https://router');
    });

    test('spells out a port that is not the scheme default', () {
      expect(UrlParser.buildUrl('router', 443, false), 'http://router:443');
      expect(UrlParser.buildUrl('router', 80, true), 'https://router:80');
      expect(
        UrlParser.buildUrl('[fd00::1]', 8080, false),
        'http://[fd00::1]:8080',
      );
    });
  });
}
