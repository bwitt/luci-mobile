import 'dart:convert';
import 'dart:io';

/// What a handler wants sent back: a JSON-RPC `result`, or a whole response.
class RawResponse {
  const RawResponse(this.body, {this.status = 200});
  final Object? body;
  final int status;
}

/// A local stand-in for LuCI: the login form at `/cgi-bin/luci/` and the
/// ubus proxy at `/cgi-bin/luci/admin/ubus`, answering by `object.method`.
class FakeLuci {
  FakeLuci._(this._server);

  static Future<FakeLuci> start([InternetAddress? address]) async {
    final fake = FakeLuci._(
      await HttpServer.bind(address ?? InternetAddress.loopbackIPv4, 0),
    );
    fake._server.listen(fake._handle);
    return fake;
  }

  final HttpServer _server;
  final handlers = <String, Object? Function(Map<String, dynamic> params)>{};
  final calls = <({String sid, String call, Map<String, dynamic> params})>[];
  final logins = <String>[];

  /// The `Set-Cookie` sent on login; null sends none, as LuCI does for a
  /// wrong password on some versions.
  String? loginCookie = 'sysauth_http=abc123==; path=/cgi-bin/luci/; HttpOnly';
  int loginStatus = 200;

  String get host => _server.address.type == InternetAddressType.IPv6
      ? '[${_server.address.address}]:${_server.port}'
      : '${_server.address.address}:${_server.port}';

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final response = request.response;
    if (request.uri.path == '/cgi-bin/luci/') {
      logins.add(body);
      response.statusCode = loginStatus;
      if (loginCookie != null) {
        response.headers.add('set-cookie', loginCookie!);
      }
      await response.close();
      return;
    }

    final payload = jsonDecode(body) as Map<String, dynamic>;
    final params = payload['params'] as List;
    final call = '${params[1]}.${params[2]}';
    final args = Map<String, dynamic>.from(params[3] as Map);
    calls.add((sid: params[0] as String, call: call, params: args));

    final handler = handlers[call];
    final answer = handler == null ? [4] : handler(args);
    if (answer is RawResponse) {
      response.statusCode = answer.status;
      final body = answer.body;
      // A string is an error page, as uhttpd sends one.
      response.headers.contentType = body is String
          ? ContentType.html
          : ContentType.json;
      response.write(body is String ? body : jsonEncode(body));
    } else {
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': answer}));
    }
    await response.close();
  }
}
