class Router {
  final String id;
  final String ipAddress;
  final String username;
  final String password;
  final bool useHttps;
  final String? lastKnownHostname;
  final String? alternateAddress;
  final bool? alternateUseHttps;
  final int activeAddressIndex;

  /// A nickname, telling apart routers that share an address and account.
  final String? name;

  Router({
    required this.id,
    required this.ipAddress,
    required this.username,
    required this.password,
    required this.useHttps,
    this.lastKnownHostname,
    this.alternateAddress,
    this.alternateUseHttps,
    this.activeAddressIndex = 0,
    String? name,
  }) : name = name == null || name.trim().isEmpty ? null : name.trim();

  /// Nickname, then live [hostname], last known hostname, then address.
  String displayName({String? hostname, String? address}) {
    for (final candidate in [name, hostname, lastKnownHostname]) {
      if (candidate != null && candidate.isNotEmpty) return candidate;
    }
    return address ?? ipAddress;
  }

  /// Whether this is [ip] signed in to as [user] under the nickname [name].
  bool matches(String ip, String user, String? name) =>
      ipAddress == ip &&
      username == user &&
      (this.name ?? '').toLowerCase() == (name ?? '').trim().toLowerCase();

  /// The address currently in use (based on last successful connection).
  String get activeAddress =>
      activeAddressIndex == 1 && hasFallback ? alternateAddress! : ipAddress;

  /// The protocol for the currently active address.
  bool get activeUseHttps =>
      activeAddressIndex == 1 && hasFallback ? alternateUseHttps! : useHttps;

  /// The other address (if any).
  String? get inactiveAddress => !hasFallback
      ? null
      : activeAddressIndex == 0
      ? alternateAddress
      : ipAddress;

  /// The protocol for the inactive address.
  bool? get inactiveUseHttps => !hasFallback
      ? null
      : activeAddressIndex == 0
      ? alternateUseHttps
      : useHttps;

  /// Whether this router has a fallback address configured.
  bool get hasFallback =>
      alternateAddress != null &&
      alternateAddress!.isNotEmpty &&
      alternateUseHttps != null;

  factory Router.fromJson(Map<String, dynamic> json) {
    return Router(
      id: json['id'] as String,
      ipAddress: json['ipAddress'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
      useHttps: json['useHttps'] == true || json['useHttps'] == 'true',
      lastKnownHostname: json['lastKnownHostname'] as String?,
      alternateAddress: json['alternateAddress'] as String?,
      alternateUseHttps: json['alternateUseHttps'] == null
          ? null
          : json['alternateUseHttps'] == true ||
                json['alternateUseHttps'] == 'true',
      activeAddressIndex: json['activeAddressIndex'] as int? ?? 0,
      name: json['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ipAddress': ipAddress,
    'username': username,
    'password': password,
    'useHttps': useHttps,
    if (lastKnownHostname != null) 'lastKnownHostname': lastKnownHostname,
    if (alternateAddress != null) 'alternateAddress': alternateAddress,
    if (alternateUseHttps != null) 'alternateUseHttps': alternateUseHttps,
    if (activeAddressIndex != 0) 'activeAddressIndex': activeAddressIndex,
    if (name != null) 'name': name,
  };

  Router copyWith({
    String? id,
    String? ipAddress,
    String? username,
    String? password,
    bool? useHttps,
    String? lastKnownHostname,
    String? alternateAddress,
    bool? alternateUseHttps,
    int? activeAddressIndex,
    bool clearAlternate = false,
    String? name,
  }) {
    return Router(
      id: id ?? this.id,
      ipAddress: ipAddress ?? this.ipAddress,
      username: username ?? this.username,
      password: password ?? this.password,
      useHttps: useHttps ?? this.useHttps,
      lastKnownHostname: lastKnownHostname ?? this.lastKnownHostname,
      alternateAddress: clearAlternate
          ? null
          : alternateAddress ?? this.alternateAddress,
      alternateUseHttps: clearAlternate
          ? null
          : alternateUseHttps ?? this.alternateUseHttps,
      activeAddressIndex: clearAlternate
          ? 0
          : activeAddressIndex ?? this.activeAddressIndex,
      // An empty name clears the nickname.
      name: name ?? this.name,
    );
  }
}
