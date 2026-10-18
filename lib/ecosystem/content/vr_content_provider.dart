import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

enum VrContentSource {
  emxi('EMXI'),
  gigmeout('Gigmeout'),
  cyberneom('Cyberneom');

  const VrContentSource(this.title);
  final String title;
}

enum VrContentKind { book, audiobook, music, meditation }

/// A borrowed, immutable identity snapshot from the app's account session.
class VrContentIdentity {
  const VrContentIdentity({
    required this.userId,
    required this.profileId,
    required this.revision,
    required this.isCurrent,
    required this.getIdToken,
  });
  final String userId, profileId;
  final int revision;
  final bool Function() isCurrent;
  final Future<String?> Function() getIdToken;
}

class VrContentUnavailable implements Exception {
  const VrContentUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Explicit deployment configuration. No provider's existing endpoint is
/// assumed to implement this new catalog/access contract.
class VrContentEndpoint {
  VrContentEndpoint({
    required this.catalog,
    required this.access,
    required Set<String> mediaHosts,
  }) : mediaHosts = Set.unmodifiable(mediaHosts) {
    if (!_https(catalog) ||
        !_https(access) ||
        catalog.origin != access.origin ||
        catalog.hasQuery ||
        access.hasQuery ||
        mediaHosts.isEmpty ||
        mediaHosts.any((host) => !_host.hasMatch(host))) {
      throw const FormatException('Invalid content endpoint configuration.');
    }
  }
  final Uri catalog, access;
  final Set<String> mediaHosts;
  static final _host = RegExp(r'^[a-z0-9]+(?:[.-][a-z0-9]+)*$');

  bool allowsMedia(Uri uri) => _https(uri) && mediaHosts.contains(uri.host);
  static bool _https(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      uri.port == 443;
}

class VrContentItem {
  const VrContentItem._({
    required this.id,
    required this.title,
    required this.kind,
    required this.paid,
  });
  final String id, title;
  final VrContentKind kind;

  /// Presentation only. Paid and public items both require a server grant.
  final bool paid;
}

class VrAuthorizedContent {
  const VrAuthorizedContent._({
    required this.source,
    required this.item,
    required this.uri,
    required this.expiresAt,
    required this.grantId,
    required this.identity,
  });
  final VrContentSource source;
  final VrContentItem item;
  final Uri uri;
  final DateTime expiresAt;
  final String grantId;
  final VrContentIdentity identity;
  bool get isCurrent =>
      identity.isCurrent() && DateTime.now().isBefore(expiresAt);
}

/// Bounded HTTPS client for the proposed provider contract, not a webhook.
/// A deployment must verify the token, account/profile ownership and purchases
/// on its server before issuing a short-lived media URL. The client cannot
/// establish an entitlement from catalog metadata or local flags.
class VrContentProvider {
  VrContentProvider({
    required this.source,
    this.endpoint,
    http.Client? client,
    this.deadline = const Duration(seconds: 15),
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _now = now ?? DateTime.now {
    if (deadline <= Duration.zero) throw ArgumentError.value(deadline);
  }
  final VrContentSource source;
  final VrContentEndpoint? endpoint;
  final Duration deadline;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  final _pending = <Completer<void>>{};
  bool _closed = false;
  static const maxBytes = 1024 * 1024;

  bool get configured => endpoint != null && !_closed;
  String get unavailableReason =>
      'El servicio de ${source.title} todavía no está configurado en VRlizate.';

  Future<List<VrContentItem>> catalog(VrContentIdentity identity) async {
    final config = _configuration();
    final data = await _request(config.catalog, identity, {
      'operation': 'catalog',
    });
    _envelope(data, identity);
    final entries = data['items'];
    if (entries is! List || entries.length > 200) throw _invalid;
    final ids = <String>{};
    return List.unmodifiable(
      entries.map((entry) {
        final value = _map(entry);
        final id = _id(value['id']);
        final title = _text(value['title'], 200);
        final kind = VrContentKind.values.where(
          (kind) => kind.name == value['kind'],
        );
        if (!ids.add(id) || kind.length != 1 || value['paid'] is! bool) {
          throw _invalid;
        }
        final parsedKind = kind.single;
        final allowed = switch (source) {
          VrContentSource.emxi => const {
            VrContentKind.book,
            VrContentKind.audiobook,
          },
          VrContentSource.gigmeout => const {VrContentKind.music},
          VrContentSource.cyberneom => const {VrContentKind.meditation},
        };
        if (!allowed.contains(parsedKind)) throw _invalid;
        return VrContentItem._(
          id: id,
          title: title,
          kind: parsedKind,
          paid: value['paid'] as bool,
        );
      }),
    );
  }

  Future<VrAuthorizedContent> authorize(
    VrContentItem item,
    VrContentIdentity identity,
  ) async {
    final config = _configuration();
    final data = await _request(config.access, identity, {
      'operation': 'authorize',
      'itemId': item.id,
    });
    _envelope(data, identity);
    if (data['itemId'] != item.id || data['kind'] != item.kind.name) {
      throw _invalid;
    }
    if (data['authorized'] != true) {
      throw const VrContentUnavailable(
        'Tu cuenta no tiene acceso a este contenido.',
      );
    }
    final grant = _id(data['grantId']);
    final uri = Uri.tryParse(_text(data['url'], 8192));
    final expires = DateTime.tryParse(_text(data['expiresAt'], 50));
    final now = _now();
    if (uri == null ||
        !config.allowsMedia(uri) ||
        expires == null ||
        !expires.isUtc ||
        !expires.isAfter(now) ||
        expires.isAfter(now.add(const Duration(hours: 1)))) {
      throw _invalid;
    }
    _identity(identity);
    return VrAuthorizedContent._(
      source: source,
      item: item,
      uri: uri,
      expiresAt: expires,
      grantId: grant,
      identity: identity,
    );
  }

  VrContentEndpoint _configuration() {
    if (!configured) throw VrContentUnavailable(unavailableReason);
    return endpoint!;
  }

  void _envelope(Map<String, dynamic> data, VrContentIdentity identity) {
    _identity(identity);
    if (data['version'] != 1 ||
        data['provider'] != source.name ||
        data['userId'] != identity.userId ||
        data['profileId'] != identity.profileId) {
      throw _invalid;
    }
  }

  void _identity(VrContentIdentity identity) {
    if (_closed ||
        !identity.isCurrent() ||
        identity.userId.isEmpty ||
        identity.profileId.isEmpty) {
      throw const VrContentUnavailable(
        'La sesión cambió. Vuelve a abrir la sala.',
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    Uri endpoint,
    VrContentIdentity identity,
    Map<String, Object> payload,
  ) async {
    _identity(identity);
    final abort = Completer<void>();
    _pending.add(abort);
    void current() {
      _identity(identity);
      if (abort.isCompleted) {
        throw const VrContentUnavailable('La solicitud de contenido terminó.');
      }
    }

    try {
      return await (() async {
        final token = await identity.getIdToken();
        current();
        if (token == null || token.isEmpty) {
          throw const VrContentUnavailable(
            'Inicia sesión para abrir este contenido.',
          );
        }
        final request =
            http.AbortableRequest('POST', endpoint, abortTrigger: abort.future)
              ..followRedirects = false
              ..headers.addAll({
                'authorization': 'Bearer $token',
                'content-type': 'application/json',
                'accept': 'application/json',
              })
              ..body = jsonEncode({
                'version': 1,
                'provider': source.name,
                'userId': identity.userId,
                'profileId': identity.profileId,
                ...payload,
              });
        final response = await _client.send(request);
        try {
          current();
        } catch (_) {
          await response.stream.listen((_) {}).cancel();
          rethrow;
        }
        if (response.statusCode != 200 ||
            response.contentLength != null &&
                response.contentLength! > maxBytes) {
          await response.stream.listen((_) {}).cancel();
          throw const VrContentUnavailable(
            'El proveedor no autorizó la solicitud.',
          );
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          current();
          if (bytes.length + chunk.length > maxBytes) throw _invalid;
          bytes.add(chunk);
        }
        current();
        return _map(jsonDecode(utf8.decode(bytes.takeBytes())));
      })().timeout(
        deadline,
        onTimeout: () {
          if (!abort.isCompleted) abort.complete();
          throw const VrContentUnavailable(
            'El proveedor tardó demasiado. Inténtalo de nuevo.',
          );
        },
      );
    } on FormatException {
      throw _invalid;
    } on VrContentUnavailable {
      rethrow;
    } catch (_) {
      throw const VrContentUnavailable('No se pudo conectar con el proveedor.');
    } finally {
      if (!abort.isCompleted) abort.complete();
      _pending.remove(abort);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final abort in _pending) {
      if (!abort.isCompleted) abort.complete();
    }
    if (_ownsClient) _client.close();
  }

  static const _invalid = VrContentUnavailable(
    'El proveedor devolvió contenido no válido.',
  );
  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map<String, dynamic>) throw _invalid;
    return value;
  }

  static String _text(Object? value, int max) {
    if (value is! String || value.trim().isEmpty || value.length > max) {
      throw _invalid;
    }
    return value;
  }

  static String _id(Object? value) {
    final id = _text(value, 180);
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]*$').hasMatch(id)) throw _invalid;
    return id;
  }
}
