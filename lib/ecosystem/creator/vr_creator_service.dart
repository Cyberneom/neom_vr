import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:vrlizate_apps/vrlizate_apps.dart';

/// A borrowed identity: no account or authentication state is owned here.
class VrCreatorIdentity {
  const VrCreatorIdentity({
    required this.uid,
    required this.profileId,
    required this.isCurrent,
    required this.getIdToken,
  });
  final String uid, profileId;
  final bool Function() isCurrent;
  final Future<String?> Function() getIdToken;
}

class VrCreatorPackage {
  VrCreatorPackage._(this.package, this.bytes, this.sha256);

  factory VrCreatorPackage.validate(Uint8List bytes) {
    // Keep an immutable copy: the upload hash must identify the validated bytes.
    if (bytes.isEmpty || bytes.length > VrlzPackage.maxBytes) {
      throw const FormatException('El archivo supera el límite de 32 MiB.');
    }
    final copy = Uint8List.fromList(bytes).asUnmodifiableView();
    return VrCreatorPackage._(
      VrlzPackage.decode(copy),
      copy,
      crypto.sha256.convert(copy).toString(),
    );
  }

  final VrlzPackage package;
  final Uint8List bytes;
  final String sha256;
}

enum VrCreatorAccess { free, purchase, subscription }

class VrCreatorOffer {
  const VrCreatorOffer({
    this.access = VrCreatorAccess.free,
    this.amountMinor = 0,
    this.currency = 'MXN',
  });
  final VrCreatorAccess access;
  final int amountMinor;
  final String currency;

  Map<String, Object> toJson() {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        amountMinor < 0 ||
        amountMinor > 100000000 ||
        (access != VrCreatorAccess.purchase && amountMinor != 0) ||
        (access == VrCreatorAccess.purchase && amountMinor == 0)) {
      throw ArgumentError('Oferta de distribución inválida.');
    }
    return {
      'access': access.name,
      'amountMinor': amountMinor,
      'currency': currency,
    };
  }
}

class VrCreatorReceipt {
  const VrCreatorReceipt({required this.id, required this.status});
  final String id, status;
}

/// Contract v1 for an explicitly configured creator backend.
///
/// The server issues a short-lived upload ticket after checking account,
/// ownership, quota and offer. Finalization validates quarantined bytes before
/// review. This client cannot grant publication, payouts or paid access.
class VrCreatorService {
  VrCreatorService({
    required this.identity,
    this.endpoint,
    Set<String> uploadOrigins = const {},
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : uploadOrigins = Set.unmodifiable(uploadOrigins),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _clock = clock ?? DateTime.now {
    if (timeout <= Duration.zero) throw ArgumentError.value(timeout);
    if (endpoint != null && !_safeEndpoint(endpoint!)) {
      throw ArgumentError('El servicio de creadores requiere HTTPS.');
    }
    for (final origin in uploadOrigins) {
      final uri = Uri.tryParse(origin);
      if (uri == null || !_safeEndpoint(uri) || uri.origin != origin) {
        throw ArgumentError('Origen de subida inválido.');
      }
    }
  }

  final VrCreatorIdentity? Function() identity;
  final Uri? endpoint;
  final Set<String> uploadOrigins;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _clock;
  bool _closed = false, _uploading = false;
  final _pending = <Completer<void>>{};

  bool get configured =>
      !_closed && endpoint != null && uploadOrigins.isNotEmpty;

  static bool _safeEndpoint(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      !uri.hasQuery;

  void _check(VrCreatorIdentity account) {
    if (_closed || !account.isCurrent()) {
      throw StateError('La sesión cambió. Vuelve a entrar antes de continuar.');
    }
  }

  Future<Map<String, dynamic>> _call(
    VrCreatorIdentity account,
    String action,
    Map<String, Object> data,
  ) async {
    _check(account);
    final token = await account.getIdToken().timeout(timeout);
    _check(account);
    if (token == null || token.isEmpty) throw StateError('Inicia sesión.');
    final request = http.Request('POST', endpoint!)
      ..followRedirects = false
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode({'schemaVersion': 1, 'action': action, ...data});
    final response = await _send(request);
    final bytes = response.bodyBytes;
    _check(account);
    if (response.statusCode != 200) {
      throw StateError(
        'El servidor no autorizó la operación (${response.statusCode}).',
      );
    }
    final result = jsonDecode(utf8.decode(bytes));
    if (result is! Map<String, dynamic> || result['schemaVersion'] != 1) {
      throw const FormatException('Respuesta de publicación incompatible.');
    }
    return result;
  }

  Future<http.Response> _send(http.Request request) async {
    final abort = Completer<void>();
    _pending.add(abort);
    final cancellable =
        http.AbortableRequest(
            request.method,
            request.url,
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers.addAll(request.headers)
          ..bodyBytes = request.bodyBytes;
    try {
      return await (() async {
        final response = await _client.send(cancellable);
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (_closed || abort.isCompleted) {
            throw StateError('Operación cancelada.');
          }
          if (bytes.length + chunk.length > 65536) {
            throw StateError('Respuesta demasiado grande.');
          }
          bytes.addAll(chunk);
        }
        return http.Response.bytes(bytes, response.statusCode);
      })().timeout(timeout);
    } finally {
      if (!abort.isCompleted) abort.complete();
      _pending.remove(abort);
    }
  }

  Future<VrCreatorReceipt> submit(
    VrCreatorPackage selected, {
    VrCreatorOffer offer = const VrCreatorOffer(),
    void Function(double)? onProgress,
  }) async {
    if (!configured) {
      throw StateError(
        'La publicación de experiencias aún no está disponible.',
      );
    }
    if (_uploading) throw StateError('Ya hay una subida en curso.');
    if (selected.package.kind != VrlzPackageKind.scene) {
      throw StateError(
        'Solo puedes enviar escenas propias, no referencias a demos de la plataforma.',
      );
    }
    final account = identity();
    if (account == null || account.uid.isEmpty || account.profileId.isEmpty) {
      throw StateError('Inicia sesión con un perfil para subir experiencias.');
    }
    _check(account);
    _uploading = true;
    try {
      final ticket = await _call(account, 'beginUpload', {
        'profileId': account.profileId,
        'packageId': selected.package.id,
        'title': selected.package.title,
        'description': selected.package.description,
        'kind': selected.package.kind.name,
        'sha256': selected.sha256,
        'sizeBytes': selected.bytes.length,
        'offer': offer.toJson(),
      });
      final uploadId = ticket['uploadId'];
      final url = Uri.tryParse(
        ticket['uploadUrl'] is String ? ticket['uploadUrl'] : '',
      );
      final expires = ticket['expiresAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(ticket['expiresAt'])
          : null;
      if (uploadId is! String ||
          !RegExp(r'^[a-zA-Z0-9_-]{16,128}$').hasMatch(uploadId) ||
          ticket['ownerUid'] != account.uid ||
          ticket['profileId'] != account.profileId ||
          ticket['sha256'] != selected.sha256 ||
          ticket['sizeBytes'] != selected.bytes.length ||
          url == null ||
          url.scheme != 'https' ||
          url.host.isEmpty ||
          url.userInfo.isNotEmpty ||
          url.hasFragment ||
          !uploadOrigins.contains(url.origin) ||
          expires == null ||
          !expires.isAfter(_clock()) ||
          expires.isAfter(_clock().add(const Duration(minutes: 15)))) {
        throw const FormatException(
          'El permiso de subida no es válido para este archivo y cuenta.',
        );
      }
      _check(account);
      onProgress?.call(0);
      // The signed storage URL receives bytes, never the Firebase bearer token.
      final request = http.Request('PUT', url)
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/octet-stream'
        ..bodyBytes = selected.bytes;
      final uploaded = await _send(request);
      _check(account);
      if (uploaded.statusCode < 200 ||
          uploaded.statusCode >= 300 ||
          !expires.isAfter(_clock())) {
        throw StateError(
          'La subida no se completó. El archivo no fue publicado.',
        );
      }
      onProgress?.call(1);
      final receipt = await _call(account, 'finalizeUpload', {
        'uploadId': uploadId,
        'profileId': account.profileId,
        'sha256': selected.sha256,
      });
      if (receipt['uploadId'] != uploadId ||
          receipt['ownerUid'] != account.uid ||
          receipt['profileId'] != account.profileId ||
          receipt['packageId'] != selected.package.id ||
          receipt['status'] != 'pendingReview') {
        throw const FormatException(
          'El servidor no confirmó la recepción para revisión.',
        );
      }
      return VrCreatorReceipt(id: uploadId, status: 'pendingReview');
    } finally {
      _uploading = false;
    }
  }

  void close() {
    _closed = true;
    for (final abort in _pending) {
      if (!abort.isCompleted) abort.complete();
    }
    if (_ownsClient) _client.close();
  }
}
