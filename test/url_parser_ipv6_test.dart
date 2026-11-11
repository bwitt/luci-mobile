import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/utils/url_parser.dart';

void main() {
  group('IPv6 addresses', () {
    // Without the brackets the port read as part of the address, and the
    // app connected to the wrong host on port 443.
    test('a scheme and a port keep the address apart from the port', () {
      final parsed = UrlParser.parse('https://[fd00::1]:8443');

      expect(parsed.isValid, isTrue);
      expect(parsed.useHttps, isTrue);
      expect(parsed.port, 8443);
      expect(parsed.hostWithPort, '[fd00::1]:8443');
      expect(parsed.displayUrl, 'https://[fd00::1]:8443');
    });

    test('a scheme without a port', () {
      final parsed = UrlParser.parse('http://[fe80::1]/');

      expect(parsed.isValid, isTrue);
      expect(parsed.hostWithPort, '[fe80::1]');
    });

    test('brackets and a port without a scheme', () {
      final parsed = UrlParser.parse('[fd00::1]:8443');

      expect(parsed.hostWithPort, '[fd00::1]:8443');
      expect(parsed.useHttps, isTrue);
    });

    test('something that is not an address is still rejected', () {
      expect(UrlParser.parse('a:b:c').isValid, isFalse);
    });
  });

  test('IPv4 and host names are unchanged', () {
    expect(
      UrlParser.parse('https://192.168.1.1:8443').hostWithPort,
      '192.168.1.1:8443',
    );
    expect(UrlParser.parse('http://router.lan').hostWithPort, 'router.lan');
    expect(UrlParser.parse('192.168.1.1').hostWithPort, '192.168.1.1');
  });
}
