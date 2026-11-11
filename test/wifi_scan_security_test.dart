import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/wifi_scan_result.dart';

void main() {
  // Shaped as rpcd's iwinfo.scan sends them: suite and cipher names lower
  // case, and WEP as the list of auth algorithms.
  group('encryption as rpcd reports it', () {
    WifiEncryption enc(Map<String, dynamic> json) =>
        WifiEncryption.fromJson({'enabled': true, ...json});

    test('WPA3-only joins as sae, not psk2', () {
      final e = enc({
        'wpa': [3],
        'authentication': ['sae'],
        'ciphers': ['ccmp'],
      });
      expect(e.openwrtEncryption, 'sae');
      expect(e.requiresPassword, isTrue);
      expect(e.isEnterprise, isFalse);
    });

    test('WPA2/WPA3 transition joins as sae-mixed', () {
      final e = enc({
        'wpa': [2, 3],
        'authentication': ['psk', 'sae'],
        'ciphers': ['ccmp'],
      });
      expect(e.openwrtEncryption, 'sae-mixed');
    });

    test('WPA2-PSK joins as psk2', () {
      final e = enc({
        'wpa': [2],
        'authentication': ['psk'],
        'ciphers': ['ccmp'],
      });
      expect(e.openwrtEncryption, 'psk2');
      expect(e.shortLabel, 'WPA2');
    });

    test('OWE needs no password', () {
      final e = enc({
        'wpa': [3],
        'authentication': ['owe'],
        'ciphers': ['ccmp'],
      });
      expect(e.openwrtEncryption, 'owe');
      expect(e.requiresPassword, isFalse);
    });

    test('802.1X is enterprise and is not joined as PSK', () {
      final e = enc({
        'wpa': [2],
        'authentication': ['802.1x'],
        'ciphers': ['ccmp'],
      });
      expect(e.isEnterprise, isTrue);
      expect(e.openwrtEncryption, 'wpa-eap');
    });

    test('WEP is WEP, not WPA', () {
      final e = enc({
        'wep': ['open'],
        'ciphers': ['wep-104'],
      });
      expect(e.wep, isTrue);
      expect(e.shortLabel, 'WEP');
      expect(e.openwrtEncryption, 'wep-open');
    });

    test('an open network has no wep list', () {
      final e = WifiEncryption.fromJson({'enabled': false});
      expect(e.wep, isFalse);
      expect(e.isOpen, isTrue);
      expect(e.openwrtEncryption, 'none');
    });

    test('upper-case suites from other sources still work', () {
      final e = enc({
        'wpa': 3,
        'auth_suites': ['SAE'],
      });
      expect(e.openwrtEncryption, 'sae');
    });
  });
}
