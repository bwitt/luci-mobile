import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/interface.dart';
import 'package:luci_mobile/models/wireless_config.dart';

void main() {
  group('NetworkInterface.fromJson', () {
    // The shape `network.interface dump` returns for a DHCP WAN.
    test('reads addresses, gateway, DNS and counters', () {
      final iface = NetworkInterface.fromJson({
        'interface': 'wan',
        'up': true,
        'proto': 'dhcp',
        'uptime': 3725,
        'l3_device': 'eth1',
        'ipv4-address': [
          {'address': '203.0.113.7', 'mask': 24},
        ],
        'ipv6-address': [
          {'address': '2001:db8::7', 'mask': 64},
          {'mask': 64},
          {'address': ''},
        ],
        'route': [
          {'target': '0.0.0.0', 'mask': 0, 'nexthop': '203.0.113.1'},
        ],
        'dns-server': ['1.1.1.1', '9.9.9.9'],
        'stats': {'rx_bytes': 1024, 'tx_bytes': 2048},
      });

      expect(iface.name, 'wan');
      expect(iface.isUp, isTrue);
      expect(iface.protocol, 'dhcp');
      expect(iface.device, 'eth1');
      expect(iface.ipAddress, '203.0.113.7');
      // The mask arrives as a prefix length, an int.
      expect(iface.netmask, '24');
      expect(iface.gateway, '203.0.113.1');
      expect(iface.dnsServers, ['1.1.1.1', '9.9.9.9']);
      expect(iface.stats['rx_bytes'], 1024);
      expect(iface.ipv6Addresses, ['2001:db8::7']);
    });

    test('prefers device over l3_device', () {
      final iface = NetworkInterface.fromJson({
        'device': 'br-lan',
        'l3_device': 'eth0',
      });
      expect(iface.device, 'br-lan');
    });

    // 0.0.0.0 is "no next hop" (an on-link route), not a gateway to show.
    test('does not report 0.0.0.0 as a gateway', () {
      final iface = NetworkInterface.fromJson({
        'route': [
          {'target': '192.168.1.0', 'nexthop': '0.0.0.0'},
        ],
      });
      expect(iface.gateway, isNull);
    });

    test('an empty or down interface parses to safe defaults', () {
      final iface = NetworkInterface.fromJson(const {});
      expect(iface.name, 'Unknown');
      expect(iface.isUp, isFalse);
      expect(iface.protocol, 'N/A');
      expect(iface.device, 'N/A');
      expect(iface.uptime, 0);
      expect(iface.ipAddress, isNull);
      expect(iface.gateway, isNull);
      expect(iface.dnsServers, isEmpty);
      expect(iface.stats, isEmpty);
      expect(iface.ipv6Addresses, isNull);
    });

    test('ignores malformed address, route, DNS and stats fields', () {
      final iface = NetworkInterface.fromJson({
        'ipv4-address': ['not a map'],
        'route': 'nope',
        'dns-server': 'not a list',
        'stats': ['not', 'a', 'map'],
        'ipv6-address': const [],
      });
      expect(iface.ipAddress, isNull);
      expect(iface.gateway, isNull);
      expect(iface.dnsServers, isEmpty);
      expect(iface.stats, isEmpty);
      expect(iface.ipv6Addresses, isNull);
    });
  });

  group('NetworkInterface.formattedUptime', () {
    NetworkInterface up(int seconds) => NetworkInterface(
      name: 'lan',
      isUp: true,
      protocol: 'static',
      uptime: seconds,
      device: 'br-lan',
      dnsServers: const [],
      stats: const {},
    );

    test('says N/A for no uptime', () {
      expect(up(0).formattedUptime, 'N/A');
      expect(up(-1).formattedUptime, 'N/A');
    });

    test('shows the largest non-zero units', () {
      expect(up(30).formattedUptime, '0m');
      expect(up(3725).formattedUptime, '1h 2m');
      expect(up(2 * 86400 + 5 * 60).formattedUptime, '2d 5m');
      expect(up(86400).formattedUptime, '1d');
    });
  });

  group('WirelessRadio', () {
    test('labels known bands and falls back to the section', () {
      expect(
        const WirelessRadio(section: 'radio0', band: '2g').label,
        '2.4 GHz',
      );
      expect(const WirelessRadio(section: 'radio1', band: '5g').label, '5 GHz');
      expect(const WirelessRadio(section: 'radio2', band: '6g').label, '6 GHz');
      expect(const WirelessRadio(section: 'radio3').label, 'radio3');
    });

    test('withNetworks keeps the radio settings', () {
      const radio = WirelessRadio(
        section: 'radio0',
        band: '5g',
        channel: '36',
        htmode: 'VHT80',
        country: 'DE',
        txpower: '20',
        disabled: true,
      );
      final net = const WirelessNetwork(
        section: 'default_radio0',
        device: 'radio0',
      );
      final copy = radio.withNetworks([net]);
      expect(copy.networks, [net]);
      expect(copy.channel, '36');
      expect(copy.htmode, 'VHT80');
      expect(copy.country, 'DE');
      expect(copy.txpower, '20');
      expect(copy.disabled, isTrue);
    });
  });

  group('WirelessNetwork', () {
    test('open means no encryption or `none`', () {
      expect(const WirelessNetwork(section: 's', device: 'r').isOpen, isTrue);
      expect(
        const WirelessNetwork(
          section: 's',
          device: 'r',
          encryption: 'none',
        ).isOpen,
        isTrue,
      );
      expect(
        const WirelessNetwork(
          section: 's',
          device: 'r',
          encryption: 'psk2',
        ).isOpen,
        isFalse,
      );
    });

    test('a guest network is an isolated AP outside the LAN', () {
      const guest = WirelessNetwork(
        section: 'guest',
        device: 'radio0',
        network: ['guest'],
        isolate: true,
      );
      expect(guest.looksLikeGuest, isTrue);
      expect(guest.copyWith(network: ['lan']).looksLikeGuest, isFalse);
      expect(guest.copyWith(isolate: false).looksLikeGuest, isFalse);
      const client = WirelessNetwork(
        section: 'sta',
        device: 'radio0',
        mode: 'sta',
        isolate: true,
      );
      expect(client.isAccessPoint, isFalse);
      expect(client.looksLikeGuest, isFalse);
    });

    test('copyWith can clear the key', () {
      const net = WirelessNetwork(
        section: 's',
        device: 'r',
        ssid: 'Home',
        encryption: 'psk2',
        key: 'secret123',
      );
      expect(net.copyWith(ssid: 'Other').key, 'secret123');
      expect(net.copyWith(ssid: 'Other').ssid, 'Other');
      expect(net.copyWith(encryption: 'none', clearKey: true).key, isNull);
      final changed = net.copyWith(hidden: true, disabled: true);
      expect(changed.hidden, isTrue);
      expect(changed.disabled, isTrue);
      expect(changed.section, 's');
      expect(changed.device, 'r');
    });
  });

  group('WirelessSecurity', () {
    test('maps UCI tokens, cipher suffixes included', () {
      expect(WirelessSecurity.fromUci('none'), WirelessSecurity.none);
      expect(WirelessSecurity.fromUci('psk2+ccmp'), WirelessSecurity.wpa2);
      expect(
        WirelessSecurity.fromUci('psk-mixed+tkip+ccmp'),
        WirelessSecurity.wpa2,
      );
      expect(WirelessSecurity.fromUci('PSK'), WirelessSecurity.wpa2);
      expect(WirelessSecurity.fromUci('sae-mixed'), WirelessSecurity.wpa2wpa3);
      expect(WirelessSecurity.fromUci('sae'), WirelessSecurity.wpa3);
      expect(WirelessSecurity.fromUci('owe'), WirelessSecurity.owe);
    });

    // Editing an EAP network here would drop its RADIUS settings.
    test('leaves enterprise and unknown tokens unmapped', () {
      expect(WirelessSecurity.fromUci('wpa2+ccmp'), isNull);
      expect(WirelessSecurity.fromUci('wep-open'), isNull);
      expect(WirelessSecurity.fromUci(''), isNull);
      expect(WirelessSecurity.fromUci(null), isNull);
    });

    test('recognises enterprise modes', () {
      expect(WirelessSecurity.isEnterprise('wpa2+ccmp'), isTrue);
      expect(WirelessSecurity.isEnterprise('wpa3-mixed'), isTrue);
      expect(WirelessSecurity.isEnterprise('psk2'), isFalse);
      expect(WirelessSecurity.isEnterprise(null), isFalse);
    });

    test('only the PSK and SAE modes need a passphrase', () {
      expect(
        {
          for (final s in WirelessSecurity.values)
            if (s.needsPassphrase) s,
        },
        {
          WirelessSecurity.wpa2,
          WirelessSecurity.wpa2wpa3,
          WirelessSecurity.wpa3,
        },
      );
      expect(WirelessSecurity.wpa2.uciValue, 'psk2');
    });
  });
}
