class UrlParser {
  static const int defaultHttpPort = 80;
  static const int defaultHttpsPort = 443;

  static ParsedUrl parse(String input) {
    String cleanInput = input.trim();

    // Remove trailing slashes
    while (cleanInput.endsWith('/')) {
      cleanInput = cleanInput.substring(0, cleanInput.length - 1);
    }

    // Check if input already has a scheme
    if (cleanInput.startsWith('http://') || cleanInput.startsWith('https://')) {
      return _parseWithScheme(cleanInput);
    }

    // No scheme provided, need to infer it
    return _parseWithoutScheme(cleanInput);
  }

  static ParsedUrl _parseWithScheme(String input) {
    try {
      final uri = Uri.parse(input);
      final scheme = uri.scheme.toLowerCase();
      final useHttps = scheme == 'https';

      // Extract host and port. Uri drops an IPv6 literal's brackets, without
      // which a port appended later reads as part of the address.
      String host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
      int? port = uri.hasPort ? uri.port : null;

      // If no explicit port, use defaults
      port ??= useHttps ? defaultHttpsPort : defaultHttpPort;

      return ParsedUrl(
        host: host,
        port: port,
        useHttps: useHttps,
        isValid: host.isNotEmpty,
      );
    } catch (e) {
      return ParsedUrl(
        host: '',
        port: defaultHttpPort,
        useHttps: false,
        isValid: false,
        error: 'Invalid URL format',
      );
    }
  }

  static ParsedUrl _parseWithoutScheme(String input) {
    // Check for host:port format
    final parts = input.split(':');

    if (parts.length == 1) {
      // Just hostname/IP, no port
      // Default to HTTP on port 80 (most routers use HTTP by default)
      return ParsedUrl(
        host: parts[0],
        port: defaultHttpPort,
        useHttps: false,
        isValid: _isValidHost(parts[0]),
      );
    } else if (parts.length == 2) {
      // hostname:port format
      final host = parts[0];
      final portStr = parts[1];

      final port = int.tryParse(portStr);
      if (port == null || port < 1 || port > 65535) {
        return ParsedUrl(
          host: '',
          port: defaultHttpPort,
          useHttps: false,
          isValid: false,
          error: 'Invalid port number',
        );
      }

      // Infer HTTPS from common ports
      final useHttps = port == 443 || port == 8443;

      return ParsedUrl(
        host: host,
        port: port,
        useHttps: useHttps,
        isValid: _isValidHost(host),
      );
    } else {
      // Invalid format (too many colons, might be IPv6)
      // Try to handle IPv6 addresses
      if (input.contains('[') && input.contains(']')) {
        return _parseIPv6(input);
      }

      return ParsedUrl(
        host: '',
        port: defaultHttpPort,
        useHttps: false,
        isValid: false,
        error: 'Invalid address format',
      );
    }
  }

  static ParsedUrl _parseIPv6(String input) {
    // Handle [IPv6]:port format
    final match = RegExp(r'\[([^\]]+)\](?::(\d+))?').firstMatch(input);
    if (match != null) {
      final host = match.group(1)!;
      final portStr = match.group(2);

      int port = defaultHttpPort;
      bool useHttps = false;

      if (portStr != null) {
        final parsedPort = int.tryParse(portStr);
        if (parsedPort != null && parsedPort >= 1 && parsedPort <= 65535) {
          port = parsedPort;
          useHttps = port == 443 || port == 8443;
        }
      }

      return ParsedUrl(
        host: '[$host]', // Keep brackets for IPv6
        port: port,
        useHttps: useHttps,
        isValid: true,
      );
    }

    return ParsedUrl(
      host: '',
      port: defaultHttpPort,
      useHttps: false,
      isValid: false,
      error: 'Invalid IPv6 address format',
    );
  }

  static bool _isValidHost(String host) {
    if (host.isEmpty) return false;

    // Check for IPv4
    final ipv4Regex = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
    final ipv4Match = ipv4Regex.firstMatch(host);
    if (ipv4Match != null) {
      // Validate each octet
      for (int i = 1; i <= 4; i++) {
        final octet = int.tryParse(ipv4Match.group(i)!);
        if (octet == null || octet < 0 || octet > 255) {
          return false;
        }
      }
      return true;
    }

    // Check for hostname (basic validation)
    final hostnameRegex = RegExp(
      r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$',
    );

    return hostnameRegex.hasMatch(host);
  }

  static String buildUrl(String host, int port, bool useHttps) {
    final scheme = useHttps ? 'https' : 'http';

    // Don't include default ports in the URL
    if ((useHttps && port == defaultHttpsPort) ||
        (!useHttps && port == defaultHttpPort)) {
      return '$scheme://$host';
    }

    // Handle IPv6 addresses
    if (host.startsWith('[') && host.endsWith(']')) {
      return '$scheme://$host:$port';
    }

    return '$scheme://$host:$port';
  }
}

class ParsedUrl {
  final String host;
  final int port;
  final bool useHttps;
  final bool isValid;
  final String? error;

  ParsedUrl({
    required this.host,
    required this.port,
    required this.useHttps,
    required this.isValid,
    this.error,
  });

  String get displayUrl => UrlParser.buildUrl(host, port, useHttps);

  String get hostWithPort {
    if ((useHttps && port == UrlParser.defaultHttpsPort) ||
        (!useHttps && port == UrlParser.defaultHttpPort)) {
      return host;
    }
    return '$host:$port';
  }
}
