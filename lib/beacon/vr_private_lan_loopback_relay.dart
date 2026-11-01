import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:vrlizate_apps/vrlizate_apps.dart'
    show isPrivateLanOrLoopbackHost;

/// Ephemeral `127.0.0.1` loopback HTTP capability tunnel running on the
/// Smartphone Visor when paired with a private-LAN **VRlizate Desktop Bóveda**.
///
/// Why this exists:
/// 1. Android's `network_security_config.xml` enforces strict
///    `cleartextTrafficPermitted="false"` globally and only permits `127.0.0.1`
///    for verified local origins (blocking direct `http://192.168.x.x` in both
///    `dart:io` `HttpClient` and Android `WebView`).
/// 2. Chromium / Android `WebView` treats `http://127.0.0.1:<port>` as a W3C
///    **Secure Context** (`window.isSecureContext === true`), unlocking WebGL2,
///    `COOP`/`COEP`, and WebAudio for `3D-VR` Dual-Eye Stereo projection while
///    preserving strict anti-cleartext enforcement for the public Internet.
class VrPrivateLanLoopbackRelay {
  VrPrivateLanLoopbackRelay({
    required this.upstreamHost,
    required this.upstreamPort,
    required this.vaultToken,
  }) : assert(vaultToken.isNotEmpty);

  final String upstreamHost;
  final int upstreamPort;
  final String vaultToken;

  HttpServer? _server;
  bool _closed = false;

  int? get boundPort => _server?.port;
  bool get isRunning => _server != null && !_closed;

  Uri? get localCatalogUri {
    final port = boundPort;
    if (port == null) return null;
    return Uri.parse('http://127.0.0.1:$port/$vaultToken/api/catalog.json');
  }

  /// Rewrites a private-LAN Vault URI to this `127.0.0.1` relay while keeping
  /// path and query intact.
  Uri rewriteUri(Uri uri) {
    final port = boundPort;
    if (port == null) return uri;
    return uri.replace(scheme: 'http', host: '127.0.0.1', port: port);
  }

  Future<bool> start() async {
    if (kIsWeb || _closed) return false;
    if (!isPrivateLanOrLoopbackHost(upstreamHost) ||
        upstreamPort < 1 ||
        upstreamPort > 65535) {
      return false;
    }
    if (_server != null) return true;
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (_closed) {
        await server.close(force: true);
        return false;
      }
      _server = server;
      unawaited(
        server.forEach((request) {
          unawaited(_forwardRequest(request));
        }),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    _closed = true;
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
  }

  static const Set<String> _forwardedRequestHeaders = {
    'accept',
    'accept-language',
    'content-type',
    'if-match',
    'if-modified-since',
    'if-none-match',
    'if-range',
    'origin',
    'range',
    'user-agent',
  };

  static const Set<String> _hopByHopResponseHeaders = {
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
  };

  Future<void> _forwardRequest(HttpRequest req) async {
    final res = req.response;
    final localPort = boundPort;
    if (_closed || localPort == null) {
      res.statusCode = HttpStatus.serviceUnavailable;
      await res.close();
      return;
    }

    final segments = req.uri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty || segments.first != vaultToken) {
      res.statusCode = HttpStatus.forbidden;
      res.write('Relay LAN: token inválido.');
      await res.close();
      return;
    }

    Socket? upstream;
    try {
      // Collect bounded request body (Vault uses GET/HEAD/OPTIONS and tiny POSTs).
      final reqBodyBuilder = BytesBuilder(copy: false);
      await for (final chunk in req) {
        if (reqBodyBuilder.length + chunk.length > 256 * 1024) {
          res.statusCode = HttpStatus.requestEntityTooLarge;
          await res.close();
          return;
        }
        reqBodyBuilder.add(chunk);
      }
      final reqBody = reqBodyBuilder.takeBytes();

      upstream = await Socket.connect(
        upstreamHost,
        upstreamPort,
        timeout: const Duration(seconds: 4),
      );
      upstream.setOption(SocketOption.tcpNoDelay, true);

      final pathAndQuery = req.uri.hasQuery
          ? '${req.uri.path}?${req.uri.query}'
          : req.uri.path;
      final headerBuf = StringBuffer()
        // HTTP/1.0 guarantees raw unchunked response bodies terminated by EOF
        // while preserving Host, Range (HTTP 206), Content-Length, and ETag.
        ..write('${req.method} $pathAndQuery HTTP/1.0\r\n')
        ..write('Host: 127.0.0.1:$localPort\r\n')
        ..write('Connection: close\r\n');

      req.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (_forwardedRequestHeaders.contains(lower) && values.isNotEmpty) {
          headerBuf.write('$name: ${values.join(', ')}\r\n');
        }
      });
      if (reqBody.isNotEmpty) {
        headerBuf.write('Content-Length: ${reqBody.length}\r\n');
      }
      headerBuf.write('\r\n');

      upstream.add(ascii.encode(headerBuf.toString()));
      if (reqBody.isNotEmpty) {
        upstream.add(reqBody);
      }
      await upstream.flush();

      var headersParsed = false;
      var isChunked = false;
      final rawHeaderBytes = BytesBuilder(copy: false);
      final chunkBuffer = BytesBuilder(copy: false);

      await for (final chunk in upstream) {
        if (!headersParsed) {
          rawHeaderBytes.add(chunk);
          final accumulated = rawHeaderBytes.toBytes();
          final splitIdx = _findHeaderTerminator(accumulated);
          if (splitIdx < 0) {
            if (accumulated.length > 32 * 1024) {
              throw const HttpException('Upstream header overflow');
            }
            continue;
          }
          headersParsed = true;
          final headerText = latin1.decode(accumulated.sublist(0, splitIdx));
          final lines = headerText.split('\r\n');
          if (lines.isEmpty) {
            throw const HttpException('Empty upstream status line');
          }
          final statusParts = lines.first.split(' ');
          final parsedCode = statusParts.length >= 2
              ? int.tryParse(statusParts[1])
              : null;
          res.statusCode = parsedCode ?? HttpStatus.badGateway;
          res.bufferOutput = false;

          for (var i = 1; i < lines.length; i++) {
            final line = lines[i];
            final colon = line.indexOf(':');
            if (colon <= 0) continue;
            final hName = line.substring(0, colon).trim();
            final hVal = line.substring(colon + 1).trim();
            final lower = hName.toLowerCase();
            if (lower == 'transfer-encoding' &&
                hVal.toLowerCase().contains('chunked')) {
              isChunked = true;
              continue;
            }
            if (_hopByHopResponseHeaders.contains(lower)) continue;
            if (lower == 'content-length') {
              final len = int.tryParse(hVal);
              if (len != null && len >= 0) {
                res.contentLength = len;
              }
              continue;
            }
            res.headers.add(hName, hVal, preserveHeaderCase: true);
          }

          final bodyRemainder = accumulated.sublist(splitIdx + 4);
          if (bodyRemainder.isNotEmpty) {
            if (isChunked) {
              chunkBuffer.add(bodyRemainder);
              _drainChunkedBody(chunkBuffer, res);
            } else {
              res.add(bodyRemainder);
            }
          }
        } else {
          if (isChunked) {
            chunkBuffer.add(chunk);
            _drainChunkedBody(chunkBuffer, res);
          } else {
            res.add(chunk);
          }
        }
      }

      if (!headersParsed) {
        res.statusCode = HttpStatus.badGateway;
      }
      await res.close();
    } catch (_) {
      try {
        res.statusCode = HttpStatus.badGateway;
      } catch (_) {}
      try {
        await res.close();
      } catch (_) {}
    } finally {
      upstream?.destroy();
    }
  }

  static int _findHeaderTerminator(Uint8List bytes) {
    for (var i = 0; i <= bytes.length - 4; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  static void _drainChunkedBody(BytesBuilder buffer, HttpResponse out) {
    var data = buffer.takeBytes();
    var offset = 0;
    while (offset < data.length) {
      var crlf = -1;
      for (var i = offset; i <= data.length - 2; i++) {
        if (data[i] == 13 && data[i + 1] == 10) {
          crlf = i;
          break;
        }
      }
      if (crlf < 0) break;
      final sizeLine = ascii
          .decode(data.sublist(offset, crlf), allowInvalid: true)
          .split(';')
          .first
          .trim();
      final chunkSize = int.tryParse(sizeLine, radix: 16);
      if (chunkSize == null) return;
      if (chunkSize == 0) {
        offset = data.length;
        break;
      }
      final chunkStart = crlf + 2;
      final chunkEnd = chunkStart + chunkSize;
      if (chunkEnd + 2 > data.length) break;
      out.add(Uint8List.sublistView(data, chunkStart, chunkEnd));
      offset = chunkEnd + 2;
    }
    if (offset < data.length) {
      buffer.add(Uint8List.sublistView(data, offset));
    }
  }
}
