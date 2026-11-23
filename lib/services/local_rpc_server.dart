import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef RpcAddUri = Future<Map<String, dynamic>> Function(Map<String, dynamic> params);

class LocalRpcServer {
  HttpServer? _server;
  final String bindAddress;
  final int port;
  final String? secret;
  final RpcAddUri onAddUri;
  bool get isRunning => _server != null;

  LocalRpcServer({
    this.bindAddress = '127.0.0.1',
    this.port = 16800,
    required this.secret,
    required this.onAddUri,
  });

  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port, shared: false);
    _server!.listen(_handle, onError: (_) {});
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.method != 'POST') {
        req.response.statusCode = 405;
        await req.response.close();
        return;
      }
      final body = await utf8.decoder.bind(req).join();
      final jsonBody = json.decode(body) as Map<String, dynamic>;
      final provided = req.headers.value('x-cineflow-token') ?? jsonBody['token']?.toString();
      if ((secret ?? '').isNotEmpty && provided != secret) {
        _json(req, 403, {'jsonrpc': '2.0', 'error': {'code': 403, 'message': 'Unauthorized'}, 'id': jsonBody['id']});
        return;
      }
      final method = jsonBody['method']?.toString();
      if (method == 'cineflow.addUri') {
        final params = (jsonBody['params'] as Map?)?.map((k, v) => MapEntry('$k', v)) ?? <String, dynamic>{};
        final result = await onAddUri(Map<String, dynamic>.from(params));
        _json(req, 200, {'jsonrpc': '2.0', 'result': result, 'id': jsonBody['id']});
        return;
      }
      _json(req, 404, {'jsonrpc': '2.0', 'error': {'code': 404, 'message': 'Method not found'}, 'id': jsonBody['id']});
    } catch (e) {
      _json(req, 400, {'jsonrpc': '2.0', 'error': {'code': 400, 'message': '$e'}, 'id': null});
    }
  }

  void _json(HttpRequest req, int status, Map<String, dynamic> body) {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(json.encode(body));
    req.response.close();
  }
}
