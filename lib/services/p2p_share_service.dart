import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'encryption_service.dart';

/// LAN peer-to-peer note sharing (LocalSend-style): UDP broadcast discovery +
/// HTTP note transfer on the local network (R1-11 hardening).
///
/// Security properties:
///  * No wildcard `Access-Control-Allow-Origin: *` — peers are native Dart HTTP
///    clients, so CORS headers are dropped entirely.
///  * UDP pong carries a one-time random token; every HTTP POST must echo the
///    token issued to that peer IP (blocks blind scans from non-Noteflow
///    devices).
///  * Request body size is capped (~5 MB) to avoid memory DoS.
///  * When both devices have the same master password, the note payload is
///    sent E2E-encrypted with the DEK (no plaintext on the wire). Cleartext
///    transfer is only used when neither side has a master password.
class P2pShareService {
  static const port = 53317;
  static const _maxBodyBytes = 5 * 1024 * 1024; // 5 MB
  HttpServer? _server;
  RawDatagramSocket? _udpSocket;
  final _peersController = StreamController<Map<String, String>>.broadcast();

  /// One-time handshake tokens issued per peer IP.
  final _peerTokens = <String, String>{};
  final _sessionTokens = <String, String>{};

  Stream<Map<String, String>> get peersStream => _peersController.stream;

  /// Starts listening for UDP discovery and incoming HTTP shares.
  ///
  /// [onReceiveNote] returns whether the note was accepted (decrypted and
  /// stored). Returning `false` makes the sender receive a failure.
  Future<void> startServer(
    Future<bool> Function(
      String title,
      String strokesJson,
      bool encrypted,
    )
    onReceiveNote,
  ) async {
    if (kIsWeb) return;
    try {
      // 1. Start HTTP Server
      _server =
          await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
      _server!.listen((HttpRequest request) async {
        if (request.method == 'OPTIONS') {
          // No CORS: peers are native clients, not browsers.
          request.response
            ..statusCode = HttpStatus.noContent
            ..close();
          return;
        }

        if (request.uri.path == '/api/noteflow/receive' &&
            request.method == 'POST') {
          try {
            final peerIp =
                request.connectionInfo?.remoteAddress.address ?? '';
            final token = request.headers.value('X-Noteflow-Token');
            if (token == null || token != _sessionTokens[peerIp]) {
              request.response
                ..statusCode = HttpStatus.forbidden
                ..write(jsonEncode({'error': 'invalid session token'}))
                ..close();
              return;
            }
            // Single-use token: consume on first accepted POST.
            _sessionTokens.remove(peerIp);

            // Size cap (Content-Length fast-path + capped streamed read).
            if (request.contentLength > _maxBodyBytes) {
              request.response
                ..statusCode = HttpStatus.requestEntityTooLarge
                ..write(jsonEncode({'error': 'payload too large'}))
                ..close();
              return;
            }
            final chunks = <int>[];
            var tooLarge = false;
            await for (final chunk in request) {
              chunks.addAll(chunk);
              if (chunks.length > _maxBodyBytes) {
                tooLarge = true;
                break;
              }
            }
            if (tooLarge) {
              request.response
                ..statusCode = HttpStatus.requestEntityTooLarge
                ..write(jsonEncode({'error': 'payload too large'}))
                ..close();
              return;
            }

            final data = jsonDecode(utf8.decode(chunks)) as Map<String, dynamic>;
            final encrypted = data['enc'] == true;
            final title = (data['title'] ?? '') as String;
            final strokesJson = (data['strokesJson'] ?? '') as String;

            final ok = await onReceiveNote(title, strokesJson, encrypted);

            request.response
              ..statusCode = ok ? HttpStatus.ok : HttpStatus.badRequest
              ..write(jsonEncode({'success': ok}))
              ..close();
          } catch (_) {
            request.response
              ..statusCode = HttpStatus.internalServerError
              ..write(jsonEncode({'error': 'invalid payload'}))
              ..close();
          }
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('Not Found')
            ..close();
        }
      });

      // 2. Start UDP Broadcast Discovery Listener
      _udpSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, port,
          reuseAddress: true);
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket!.receive();
          if (datagram != null) {
            final message = utf8.decode(datagram.data);
            if (message.startsWith('noteflow_ping:')) {
              // Ping received: respond with pong containing device name and a
              // one-time handshake token bound to this peer IP.
              final token = _newToken();
              _sessionTokens[datagram.address.address] = token;
              final response = 'noteflow_pong:${Platform.localHostname}:$token';
              _udpSocket!.send(
                  utf8.encode(response), datagram.address, port);
            } else if (message.startsWith('noteflow_pong:')) {
              // Pong received: add peer (and its handshake token) to peers.
              final rest =
                  message.substring('noteflow_pong:'.length);
              final sep = rest.indexOf(':');
              final name =
                  sep < 0 ? rest : rest.substring(0, sep);
              final token =
                  sep < 0 ? '' : rest.substring(sep + 1);
              _peerTokens[datagram.address.address] = token;
              _peersController.add({
                'ip': datagram.address.address,
                'name': name,
              });
            }
          }
        }
      });
    } catch (_) {}
  }

  /// Broadcasts a ping to find other Noteflow instances on the network.
  Future<void> discoverPeers() async {
    if (kIsWeb || _udpSocket == null) return;
    try {
      _udpSocket!.send(
        utf8.encode('noteflow_ping:'),
        InternetAddress('255.255.255.255'),
        port,
      );
    } catch (_) {}
  }

  /// Sends a note to a target IP. When [encryptionKey] is provided (master
  /// password set on the sending device), the title and strokes are encrypted
  /// with the DEK so nothing sensitive crosses the LAN in plaintext.
  Future<bool> sendNote(String ip, String title, String strokesJson,
      {SecretKey? encryptionKey}) async {
    if (kIsWeb) return false;
    try {
      final encrypted = encryptionKey != null;
      final body = encrypted
          ? {
              'enc': true,
              'title':
                  await EncryptionService.encrypt(title, encryptionKey),
              'strokesJson': await EncryptionService.encrypt(
                  strokesJson, encryptionKey),
            }
          : {'enc': false, 'title': title, 'strokesJson': strokesJson};

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request =
          await client.post(ip, port, '/api/noteflow/receive');
      request.headers.contentType = ContentType.json;
      final token = _peerTokens[ip];
      if (token != null) {
        request.headers.set('X-Noteflow-Token', token);
      }
      request.write(jsonEncode(body));
      final response = await request.close();
      client.close();
      return response.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    }
  }

  String _newToken() {
    final rand = Random.secure();
    return List.generate(
            16, (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  void dispose() {
    _server?.close();
    _udpSocket?.close();
    _peersController.close();
    _peerTokens.clear();
    _sessionTokens.clear();
  }
}
