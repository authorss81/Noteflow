import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class P2pShareService {
  static const port = 53317;
  HttpServer? _server;
  RawDatagramSocket? _udpSocket;
  final _peersController = StreamController<Map<String, String>>.broadcast();

  Stream<Map<String, String>> get peersStream => _peersController.stream;

  /// Starts listening for UDP discovery and incoming HTTP shares.
  Future<void> startServer(Function(String title, String strokesJson) onReceiveNote) async {
    if (kIsWeb) return;
    try {
      // 1. Start HTTP Server
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
      _server!.listen((HttpRequest request) async {
        // Support CORS options requests if any
        if (request.method == 'OPTIONS') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.add('Access-Control-Allow-Origin', '*')
            ..headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS')
            ..headers.add('Access-Control-Allow-Headers', 'Content-Type')
            ..close();
          return;
        }

        if (request.uri.path == '/api/noteflow/receive' && request.method == 'POST') {
          try {
            final body = await utf8.decoder.bind(request).join();
            final data = jsonDecode(body) as Map<String, dynamic>;
            final title = data['title'] as String;
            final strokesJson = data['strokesJson'] as String;

            onReceiveNote(title, strokesJson);

            request.response
              ..statusCode = HttpStatus.ok
              ..headers.add('Access-Control-Allow-Origin', '*')
              ..write(jsonEncode({'success': true}))
              ..close();
          } catch (e) {
            request.response
              ..statusCode = HttpStatus.internalServerError
              ..headers.add('Access-Control-Allow-Origin', '*')
              ..write(jsonEncode({'error': e.toString()}))
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
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket!.receive();
          if (datagram != null) {
            final message = utf8.decode(datagram.data);
            if (message.startsWith('noteflow_ping:')) {
              // Ping received: respond with pong containing device details
              final response = 'noteflow_pong:${Platform.localHostname}';
              _udpSocket!.send(utf8.encode(response), datagram.address, port);
            } else if (message.startsWith('noteflow_pong:')) {
              // Pong received: add peer to active peers list
              final name = message.substring('noteflow_pong:'.length);
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

  /// Sends a note to a target IP.
  Future<bool> sendNote(String ip, String title, String strokesJson) async {
    if (kIsWeb) return false;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.post(ip, port, '/api/noteflow/receive');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'title': title,
        'strokesJson': strokesJson,
      }));
      final response = await request.close();
      client.close();
      return response.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _server?.close();
    _udpSocket?.close();
    _peersController.close();
  }
}
