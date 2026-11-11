import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/services/api_service.dart';

import 'helpers/fake_luci.dart';

void main() {
  late FakeLuci luci;
  late RealApiService api;

  setUp(() async {
    luci = await FakeLuci.start();
    api = RealApiService();
  });

  tearDown(() => luci.close());

  group('login', () {
    test('posts the form and returns the sysauth cookie', () async {
      final token = await api.login(luci.host, 'root', 'p@ss&word', false);

      // The cookie value may itself contain `=`.
      expect(token, 'abc123==');
      expect(
        luci.logins.single,
        'luci_username=root&luci_password=p%40ss%26word',
      );
    });

    test('accepts the sysauth_https cookie name too', () async {
      luci.loginCookie = 'sysauth_https=tls-token; path=/; secure';
      final result = await api.loginWithProtocolDetection(
        luci.host,
        'root',
        'pw',
        false,
      );
      expect(result.token, 'tls-token');
      expect(result.actualUseHttps, isFalse);
    });

    // LuCI answers a wrong password with 403 and no cookie.
    test('a rejected password surfaces as the HTTP error', () async {
      luci
        ..loginStatus = 403
        ..loginCookie = null;
      await expectLater(
        api.login(luci.host, 'root', 'wrong', false),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            403,
          ),
        ),
      );
    });
  });

  group('call', () {
    test('sends the session, object, method and params', () async {
      luci.handlers['system.board'] = (_) => [
        0,
        {'hostname': 'OpenWrt'},
      ];

      final result = await api.call(
        luci.host,
        'sid-1',
        false,
        object: 'system',
        method: 'board',
        params: {'verbose': true},
      );

      expect(result, [
        0,
        {'hostname': 'OpenWrt'},
      ]);
      expect(luci.calls.single.sid, 'sid-1');
      expect(luci.calls.single.params, {'verbose': true});
    });

    test('a non-zero ubus status becomes an RpcException', () async {
      luci.handlers['system.board'] = (_) => [6];
      await expectLater(
        api.call(luci.host, 's', false, object: 'system', method: 'board'),
        throwsA(
          isA<RpcException>()
              .having((e) => e.status, 'status', 6)
              .having((e) => e.isAccessDenied, 'isAccessDenied', isTrue),
        ),
      );
    });

    // LuCI's proxy reports an expired session as a JSON-RPC error.
    test('a JSON-RPC error carries its message', () async {
      luci.handlers['system.board'] = (_) => const RawResponse({
        'jsonrpc': '2.0',
        'id': 1,
        'error': {'code': -32002, 'message': 'Access denied'},
      });
      await expectLater(
        api.call(luci.host, 's', false, object: 'system', method: 'board'),
        throwsA(
          isA<RpcException>()
              .having((e) => e.detail, 'detail', 'Access denied')
              .having((e) => e.isAccessDenied, 'isAccessDenied', isTrue),
        ),
      );
    });

    test('a body that is not a JSON object is an invalid response', () async {
      luci.handlers['system.board'] = (_) => const RawResponse([1, 2, 3]);
      await expectLater(
        api.call(luci.host, 's', false, object: 'system', method: 'board'),
        throwsA(
          isA<RpcException>().having(
            (e) => e.detail,
            'detail',
            'invalid response',
          ),
        ),
      );
    });

    test('an HTTP error names the call that failed', () async {
      luci.handlers['luci-rpc.getDHCPLeases'] = (_) =>
          const RawResponse('<h1>500 Internal Server Error</h1>', status: 500);
      try {
        await api.call(
          luci.host,
          's',
          false,
          object: 'luci-rpc',
          method: 'getDHCPLeases',
        );
        fail('expected an error');
      } on DioException catch (e) {
        expect(e.response?.statusCode, 500);
        expect(rpcCallOf(e), 'luci-rpc.getDHCPLeases');
        expect(
          userFacingApiError(e),
          'The router returned HTTP 500 for luci-rpc.getDHCPLeases.',
        );
      }
    });

    // What UrlParser saves for `[fd00::1]:8443`.
    test('reaches a bracketed IPv6 address with a port', () async {
      final v6 = await FakeLuci.start(InternetAddress.loopbackIPv6);
      addTearDown(v6.close);
      v6.handlers['system.board'] = (_) => [0, <String, dynamic>{}];

      final result = await api.call(
        v6.host,
        's',
        false,
        object: 'system',
        method: 'board',
      );

      expect(v6.host, startsWith('[::1]:'));
      expect(result, [0, <String, dynamic>{}]);
    });
  });

  test('reboot reports success only for a zero status', () async {
    luci.handlers['system.reboot'] = (_) => [0];
    expect(await api.reboot(luci.host, 's', false), isTrue);

    luci.handlers['system.reboot'] = (_) => [6];
    expect(await api.reboot(luci.host, 's', false), isFalse);
  });

  group('wireless', () {
    test('associated MACs are collected per AP interface', () async {
      luci.handlers['luci-rpc.getWirelessDevices'] = (_) => [
        0,
        {
          'radio0': {
            'interfaces': [
              {
                'ifname': 'wlan0',
                'config': {'mode': 'ap'},
              },
              // A client (sta) interface has no stations of its own.
              {
                'ifname': 'wlan0-1',
                'config': {'mode': 'sta'},
              },
              // Not up yet: no ifname.
              {
                'config': {'mode': 'ap'},
              },
            ],
          },
          'radio1': {
            'interfaces': [
              {'ifname': 'wlan1'},
            ],
          },
          'radio2': <String, dynamic>{},
        },
      ];
      luci.handlers['iwinfo.assoclist'] = (params) => [
        0,
        {
          'results': params['device'] == 'wlan0'
              ? [
                  {'mac': 'AA:BB:CC:00:00:01'},
                  {'mac': 'AA:BB:CC:00:00:02'},
                ]
              : <Object>[],
        },
      ];

      final macs = await api.fetchAllAssociatedWirelessMacsWithContext(
        ipAddress: luci.host,
        sysauth: 's',
        useHttps: false,
      );

      expect(macs, {
        'wlan0': {'AA:BB:CC:00:00:01', 'AA:BB:CC:00:00:02'},
      });
      expect(
        luci.calls
            .where((c) => c.call == 'iwinfo.assoclist')
            .map((c) => c.params['device']),
        ['wlan0', 'wlan1'],
      );
    });

    // Some stations missing is fine; all of them failing is an error, not
    // an empty network.
    test('every assoclist failing is reported, not read as empty', () async {
      luci.handlers['luci-rpc.getWirelessDevices'] = (_) => [
        0,
        {
          'radio0': {
            'interfaces': [
              {'ifname': 'wlan0'},
            ],
          },
        },
      ];
      luci.handlers['iwinfo.assoclist'] = (_) => [6];

      await expectLater(
        api.fetchAllAssociatedWirelessMacsWithContext(
          ipAddress: luci.host,
          sysauth: 's',
          useHttps: false,
        ),
        throwsA(isA<RpcException>()),
      );
    });

    test('a malformed wireless device list is an invalid response', () async {
      luci.handlers['luci-rpc.getWirelessDevices'] = (_) => [
        0,
        {
          'radio0': {'interfaces': 'wlan0'},
        },
      ];
      await expectLater(
        api.fetchAllAssociatedWirelessMacsWithContext(
          ipAddress: luci.host,
          sysauth: 's',
          useHttps: false,
        ),
        throwsA(
          isA<RpcException>().having(
            (e) => e.detail,
            'detail',
            'invalid response',
          ),
        ),
      );
    });

    test('station details are keyed by normalised MAC', () async {
      luci.handlers['iwinfo.assoclist'] = (_) => [
        0,
        {
          'results': [
            {
              'mac': 'aa-bb-cc-00-00-01',
              'signal': -55,
              'noise': -95,
              'rx': {'rate': 866700, 'mhz': 80},
              'tx': {'rate': 650000},
            },
            {'signal': -40},
            'junk',
          ],
        },
      ];

      final stations = await api.fetchStationDetails(
        luci.host,
        's',
        false,
        device: 'wlan1',
      );

      final station = stations['AA:BB:CC:00:00:01']!;
      expect(stations, hasLength(1));
      expect(station.interface, 'wlan1');
      expect(station.snr, 40);
      expect(station.rxRateKbps, 866700);
      expect(station.rxMhz, 80);
      expect(station.txRateKbps, 650000);
    });

    test('scan results are read from `results` or any list of rows', () async {
      luci.handlers['iwinfo.scan'] = (_) => [
        0,
        {
          'results': [
            {'ssid': 'A'},
            {'ssid': 'B'},
          ],
        },
      ];
      final first = await api.scanWirelessNetworks(
        ipAddress: luci.host,
        sysauth: 's',
        useHttps: false,
        device: 'phy0-ap0',
      );
      expect(first.map((r) => r['ssid']), ['A', 'B']);

      luci.handlers['iwinfo.scan'] = (_) => [
        0,
        {
          'networks': [
            {'ssid': 'C'},
          ],
        },
      ];
      final second = await api.scanWirelessNetworks(
        ipAddress: luci.host,
        sysauth: 's',
        useHttps: false,
        device: 'phy0-ap0',
      );
      expect(second.map((r) => r['ssid']), ['C']);
      expect(luci.calls.last.params, {'device': 'phy0-ap0'});

      luci.handlers['iwinfo.scan'] = (_) => [0, <String, dynamic>{}];
      expect(
        await api.scanWirelessNetworks(
          ipAddress: luci.host,
          sysauth: 's',
          useHttps: false,
          device: 'phy0-ap0',
        ),
        isEmpty,
      );
    });

    test('WireGuard peers are read from a list or a map of peers', () async {
      luci.handlers['luci.wireguard.getWgInstances'] = (_) => [
        0,
        {
          'wg0': {
            'peers': [
              {
                'public_key': 'KEY1',
                'name': ' laptop ',
                'endpoint': '198.51.100.2:51820',
                'latest_handshake': '1700000000',
                'allowed_ips': ['10.0.0.2/32', '(none)', ' '],
                'transfer_rx': 10,
                'transfer_tx': 20,
              },
              {'name': 'no key'},
            ],
          },
          'wg1': {
            'peers': {
              'KEY2': {'endpoint': null},
            },
          },
          'wg2': {'peers': <Object>[]},
        },
      ];

      final all = await api.fetchWireGuardPeers(
        ipAddress: luci.host,
        sysauth: 's',
        useHttps: false,
        interface: '',
      );
      expect(all!.keys, unorderedEquals(['wg0', 'wg1']));
      final peer = all['wg0']['peers']['KEY1'] as Map<String, dynamic>;
      expect(peer['name'], 'laptop');
      expect(peer['last_handshake'], 1700000000);
      expect(peer['allowed_ips'], ['10.0.0.2/32']);
      expect(peer['transfer_rx'], 10);
      expect(all['wg1']['peers']['KEY2']['endpoint'], 'N/A');

      final one = await api.fetchWireGuardPeers(
        ipAddress: luci.host,
        sysauth: 's',
        useHttps: false,
        interface: 'wg1',
      );
      expect(one!['interface'], 'wg1');
    });

    // WireGuard is optional; a router without it is not an error.
    test('a router without WireGuard has no peers', () async {
      expect(
        await api.fetchWireGuardPeers(
          ipAddress: luci.host,
          sysauth: 's',
          useHttps: false,
          interface: 'wg0',
        ),
        isNull,
      );
    });
  });

  group('LuCI helpers', () {
    test('host hints are keyed by normalised MAC', () async {
      luci.handlers['luci-rpc.getHostHints'] = (_) => [
        0,
        {
          'aa:bb:cc:00:00:01': {'name': 'nas'},
        },
      ];
      final hints = await api.fetchHostHints(luci.host, 's', false);
      expect(hints, {
        'AA:BB:CC:00:00:01': {'name': 'nas'},
      });
    });

    test('realtime stats rows are numbers, parsed when sent as text', () async {
      luci.handlers['luci.getRealtimeStats'] = (_) => [
        0,
        {
          'result': [
            [1700000000, 100, '200', 'x'],
            'not a row',
          ],
        },
      ];
      final rows = await api.luciRealtimeStats(
        luci.host,
        's',
        false,
        mode: 'interface',
        device: 'br-lan',
      );
      expect(rows, [
        [1700000000, 100, 200, 0],
      ]);
      expect(luci.calls.single.params, {
        'mode': 'interface',
        'device': 'br-lan',
      });
    });

    test('services are listed and init failures are reported', () async {
      luci.handlers['rc.list'] = (_) => [
        0,
        {
          'dnsmasq': {'enabled': true, 'running': true, 'start': 19},
          'broken': 'not a map',
        },
      ];
      final services = await api.rcList(luci.host, 's', false);
      expect(services.keys, ['dnsmasq']);
      expect(services['dnsmasq']!.running, isTrue);

      // An init script that exits non-zero still has ubus status 0.
      luci.handlers['rc.init'] = (_) => [
        0,
        {'result': false},
      ];
      expect(
        await api.rcInit(
          luci.host,
          's',
          false,
          name: 'dnsmasq',
          action: 'restart',
        ),
        isFalse,
      );
      expect(luci.calls.last.params, {'name': 'dnsmasq', 'action': 'restart'});

      luci.handlers['rc.init'] = (_) => [0];
      expect(
        await api.rcInit(
          luci.host,
          's',
          false,
          name: 'dnsmasq',
          action: 'restart',
        ),
        isTrue,
      );
    });

    test('setPassword accepts a bare success and reports a refusal', () async {
      luci.handlers['luci.setPassword'] = (_) => [0];
      expect(
        await api.luciSetPassword(
          luci.host,
          's',
          false,
          username: 'root',
          password: 'new',
        ),
        isTrue,
      );

      luci.handlers['luci.setPassword'] = (_) => [
        0,
        {'result': false},
      ];
      expect(
        await api.luciSetPassword(
          luci.host,
          's',
          false,
          username: 'root',
          password: 'new',
        ),
        isFalse,
      );
    });

    test('timezones keep only zones with a TZ string', () async {
      luci.handlers['luci.getTimezones'] = (_) => [
        0,
        {
          'Europe/Berlin': {'tzstring': 'CET-1CEST,M3.5.0,M10.5.0/3'},
          'Etc/Broken': {'other': 1},
          'UTC': 'not a map',
        },
      ];
      expect(await api.luciTimezones(luci.host, 's', false), {
        'Europe/Berlin': 'CET-1CEST,M3.5.0,M10.5.0/3',
      });
    });

    test('features default to none when the router sends no body', () async {
      luci.handlers['luci.getFeatures'] = (_) => [0];
      expect(await api.luciGetFeatures(luci.host, 's', false), isEmpty);

      luci.handlers['luci.getFeatures'] = (_) => [
        0,
        {'wifi': true},
      ];
      expect(await api.luciGetFeatures(luci.host, 's', false), {'wifi': true});
    });

    test('ubus access answers true, false or unknown', () async {
      luci.handlers['session.access'] = (_) => [
        0,
        {'access': true},
      ];
      expect(
        await api.checkUbusAccess(
          luci.host,
          's',
          false,
          object: 'uci',
          function: 'apply',
        ),
        isTrue,
      );
      expect(luci.calls.last.params, {
        'scope': 'ubus',
        'object': 'uci',
        'function': 'apply',
      });

      luci.handlers['session.access'] = (_) => [0, <String, dynamic>{}];
      expect(
        await api.checkUbusAccess(
          luci.host,
          's',
          false,
          object: 'uci',
          function: 'apply',
        ),
        isNull,
      );
    });
  });

  group('session ACLs', () {
    Future<Map<String, Set<String>>?> aclFor(Object? data) {
      luci.handlers['session.list'] = (_) => [0, data];
      return api.fetchSessionAcl(luci.host, 'sid-1', false);
    }

    const acls = {
      'acls': {
        'ubus': {
          'uci': ['get', 'set'],
          'system': 'board',
        },
      },
    };

    // rpcd answers with the session itself or a map of sessions by id,
    // depending on version.
    test('are read from every shape rpcd answers with', () async {
      final expected = {
        'uci': {'get', 'set'},
        'system': {'board'},
      };
      expect(await aclFor(acls), expected);
      expect(await aclFor({'sid-1': acls}), expected);
      expect(await aclFor({'other-sid': acls}), expected);
      expect(luci.calls.last.params, {'ubus_rpc_session': 'sid-1'});
    });

    test('are unknown when the response carries none', () async {
      expect(await aclFor('nope'), isNull);
      expect(await aclFor({'acls': 'nope'}), isNull);
      expect(
        await aclFor({
          'acls': {'file': <String, dynamic>{}},
        }),
        isNull,
      );
    });
  });
}
