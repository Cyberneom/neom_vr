import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:neom_books/neom_books_reader.dart';

import 'auth/vr_ecosystem_session.dart';
import 'content/vr_content_provider.dart';

/// Downloads only the URL issued by the verified EMXI grant, without tokens,
/// redirects, persistent cache or fallback to another application's PDF proxy.
class VrGrantedBookLoader {
  VrGrantedBookLoader(
    this.content, {
    http.Client? client,
    this.deadline = const Duration(seconds: 30),
    this.maxBytes = 32 * 1024 * 1024,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;
  final VrAuthorizedContent content;
  final http.Client _client;
  final bool _ownsClient;
  final Duration deadline;
  final int maxBytes;
  final _abort = Completer<void>();
  bool _started = false;

  void _check() {
    if (_abort.isCompleted ||
        !content.isCurrent ||
        content.source != VrContentSource.emxi ||
        content.item.kind != VrContentKind.book) {
      throw const VrContentUnavailable(
        'El permiso de lectura dejó de estar vigente.',
      );
    }
  }

  Future<Uint8List> load() async {
    _check();
    if (_started) {
      throw StateError('Este permiso ya se utilizó para abrir el libro.');
    }
    _started = true;
    try {
      return await (() async {
        final request =
            http.AbortableRequest(
                'GET',
                content.uri,
                abortTrigger: _abort.future,
              )
              ..followRedirects = false
              ..headers['Accept'] = 'application/pdf';
        final response = await _client.send(request);
        try {
          _check();
          if (response.statusCode != 200 ||
              (response.contentLength ?? 0) > maxBytes) {
            throw const VrContentUnavailable('No se pudo abrir este documento.');
          }
        } catch (_) {
          await response.stream.listen(null).cancel();
          rethrow;
        }
        final data = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          _check();
          if (data.length + chunk.length > maxBytes) {
            throw const VrContentUnavailable(
              'El documento supera el tamaño permitido.',
            );
          }
          data.add(chunk);
        }
        _check();
        final bytes = data.takeBytes();
        if (bytes.length < 5 ||
            bytes[0] != 0x25 ||
            bytes[1] != 0x50 ||
            bytes[2] != 0x44 ||
            bytes[3] != 0x46 ||
            bytes[4] != 0x2d) {
          throw const VrContentUnavailable(
            'El documento no es un PDF compatible.',
          );
        }
        return bytes;
      })().timeout(deadline);
    } catch (_) {
      close();
      rethrow;
    }
  }

  void close() {
    if (_abort.isCompleted) return;
    _abort.complete();
    if (_ownsClient) _client.close();
  }
}

class VrGrantedBookPage extends StatefulWidget {
  const VrGrantedBookPage({
    super.key,
    required this.content,
    required this.session,
  });
  final VrAuthorizedContent content;
  final VrEcosystemSession session;
  @override
  State<VrGrantedBookPage> createState() => _VrGrantedBookPageState();
}

class _VrGrantedBookPageState extends State<VrGrantedBookPage>
    with WidgetsBindingObserver {
  late final _loader = VrGrantedBookLoader(widget.content);
  late final _permit = ValueNotifier(widget.content.isCurrent);
  late final Future<Uint8List> Function() _loadBytes = _loader.load;
  bool _wasCurrent = false;
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant VrGrantedBookPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.session, oldWidget.session)) {
      oldWidget.session.removeListener(_sessionChanged);
      widget.session.addListener(_sessionChanged);
    }
    if (!identical(widget.content, oldWidget.content) ||
        !identical(widget.session, oldWidget.session)) {
      _revoke();
    }
  }

  void _revoke() {
    _permit.value = false;
    _loader.close();
  }

  void _sessionChanged() {
    if (!widget.content.isCurrent) _revoke();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (_wasCurrent && !current) _revoke();
    _wasCurrent = current;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _revoke();
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _loader.close();
    _permit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthorizedPdfReaderPage(
    key: ValueKey(widget.content.grantId),
    title: widget.content.item.title,
    loadVerifiedBytes: _loadBytes,
    permit: _permit,
    expiresAt: widget.content.expiresAt,
    maxBytes: _loader.maxBytes,
    onAccessEnded: _loader.close,
  );
}
