import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/utils/wifi_qr.dart';

void main() {
  group('wifiQrSecurity', () {
    test('maps open and OWE networks to nopass', () {
      for (final encryption in [null, '', 'none', 'owe']) {
        expect(wifiQrSecurity(encryption), WifiQrSecurity.nopass);
      }
    });

    test('maps WEP variants to WEP', () {
      for (final encryption in ['wep', 'wep-open', 'wep-shared']) {
        expect(wifiQrSecurity(encryption), WifiQrSecurity.wep);
      }
    });

    test('maps PSK and SAE variants, with or without a cipher, to WPA', () {
      for (final encryption in [
        'psk',
        'psk2',
        'psk-mixed',
        'psk2+ccmp',
        'psk-mixed+tkip+ccmp',
        'sae',
        'sae-mixed',
        'SAE',
      ]) {
        expect(wifiQrSecurity(encryption), WifiQrSecurity.wpa);
      }
    });

    test('rejects 802.1X enterprise and unknown modes', () {
      for (final encryption in [
        'wpa',
        'wpa2',
        'wpa3',
        'wpa-mixed',
        'wpa3-mixed',
        'wpa2+ccmp',
        'wpa3-192',
        'bogus',
      ]) {
        expect(wifiQrSecurity(encryption), isNull, reason: encryption);
      }
    });
  });

  test('wifiQrEscape backslash-escapes the reserved characters', () {
    expect(wifiQrEscape(r'a\b;c,d:e"f'), r'a\\b\;c\,d\:e\"f');
    expect(wifiQrEscape('plain text'), 'plain text');
  });

  group('WifiQrNetwork.payload', () {
    test('encodes a WPA network', () {
      const network = WifiQrNetwork(
        ssid: 'Home',
        security: WifiQrSecurity.wpa,
        password: 'hunter22',
      );
      expect(network.payload, 'WIFI:T:WPA;S:Home;P:hunter22;;');
    });

    test('escapes the SSID and password', () {
      const network = WifiQrNetwork(
        ssid: 'Cafe;"Bar"',
        security: WifiQrSecurity.wpa,
        password: r'p:a,s\s;',
      );
      expect(network.payload, r'WIFI:T:WPA;S:Cafe\;\"Bar\";P:p\:a\,s\\s\;;;');
    });

    test('omits the password of an open network', () {
      const network = WifiQrNetwork(
        ssid: 'Guest',
        security: WifiQrSecurity.nopass,
        password: 'ignored',
      );
      expect(network.payload, 'WIFI:T:nopass;S:Guest;;');
    });

    test('flags a hidden network', () {
      const network = WifiQrNetwork(
        ssid: 'Secret',
        security: WifiQrSecurity.wep,
        password: 'abcde',
        hidden: true,
      );
      expect(network.payload, 'WIFI:T:WEP;S:Secret;P:abcde;H:true;;');
    });
  });

  group('WifiQrNetwork.fromUci', () {
    test('reads ssid, key and hidden from a PSK section', () {
      final network = WifiQrNetwork.fromUci({
        'ssid': 'Home',
        'encryption': 'psk2+ccmp',
        'key': ' spaced key ',
        'hidden': '1',
      })!;
      expect(network.ssid, 'Home');
      expect(network.security, WifiQrSecurity.wpa);
      expect(network.password, ' spaced key ');
      expect(network.hidden, isTrue);
      expect(network.hasPassword, isTrue);
      expect(network.payload, 'WIFI:T:WPA;S:Home;P: spaced key ;H:true;;');
    });

    test('treats a missing or empty encryption as open', () {
      final network = WifiQrNetwork.fromUci({'ssid': 'Open', 'key': 'x'})!;
      expect(network.security, WifiQrSecurity.nopass);
      expect(network.password, isEmpty);
      expect(network.hasPassword, isTrue);
      expect(network.payload, 'WIFI:T:nopass;S:Open;;');
    });

    test('maps OWE to nopass', () {
      final network = WifiQrNetwork.fromUci({
        'ssid': 'Enhanced',
        'encryption': 'owe',
      })!;
      expect(network.payload, 'WIFI:T:nopass;S:Enhanced;;');
    });

    test('returns null for an enterprise section', () {
      expect(
        WifiQrNetwork.fromUci({
          'ssid': 'Corp',
          'encryption': 'wpa2',
          'auth_server': '10.0.0.2',
        }),
        isNull,
      );
    });

    test('reports a missing or empty key as no password', () {
      for (final key in [null, '']) {
        final network = WifiQrNetwork.fromUci({
          'ssid': 'Home',
          'encryption': 'sae',
          'key': ?key,
        })!;
        expect(network.hasPassword, isFalse);
      }
    });

    test('resolves a WEP key index and strips the ASCII prefix', () {
      final network = WifiQrNetwork.fromUci({
        'ssid': 'Legacy',
        'encryption': 'wep-open',
        'key': '2',
        'key2': 's:abcde',
      })!;
      expect(network.password, 'abcde');
      expect(network.payload, 'WIFI:T:WEP;S:Legacy;P:abcde;;');
    });

    test('reads list-shaped options', () {
      final network = WifiQrNetwork.fromUci({
        'ssid': ['Home'],
        'encryption': ['psk2'],
        'key': ['secret12'],
      })!;
      expect(network.payload, 'WIFI:T:WPA;S:Home;P:secret12;;');
    });
  });
}
