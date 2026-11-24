import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The Sync API in memory, for the computer engine's tests: records every
/// request; [route] answers by "METHOD /path" (query string removed).
class FakeServer {
  final requests = <http.Request>[];
  final routes = <String, http.Response Function(http.Request req)>{};

  /// No network at all (the request never gets an answer).
  bool down = false;

  late final client = MockClient((req) async {
    requests.add(req);
    if (down) throw http.ClientException('Connection refused');
    final key = '${req.method} ${req.url.path}';
    final route = routes[key];
    if (route == null) return http.Response(jsonEncode({'statusCode': 404, 'message': 'Cannot ${req.method} ${req.url.path}'}), 404);
    return route(req);
  });

  void route(String key, Object? body, {int status = 200}) =>
      routes[key] = (_) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  Iterable<http.Request> called(String key) => requests.where((r) => '${r.method} ${r.url.path}' == key);

  Map<String, Object?> body(http.Request r) => (jsonDecode(r.body) as Map).cast<String, Object?>();

  static Map<String, Object?> doc(String id, Map<String, Object?> data, {int version = 1, String at = '2026-11-24T10:00:00.000Z'}) =>
      {'id': id, 'data': data, 'version': version, 'createdAt': at, 'updatedAt': at};

  /// The realtime token answer.
  void realtime({String project = 'p1'}) => route('POST /connections/token', {
    'token': 'rt-token',
    'projectId': project,
    'mqtt': {'host': 'mqtt-sync.abrova.ir', 'port': 8885, 'useTls': true},
  });
}
