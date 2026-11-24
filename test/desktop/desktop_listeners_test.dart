// Listeners on a computer: server listeners over the real-time connection,
// versioned events, revoke, catch-up after a drop, topics on an older server.
import 'dart:convert';
import 'dart:io';

import 'package:abrova_sync/abrova_sync.dart';
import 'package:abrova_sync_desktop/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fake_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final server = FakeServer();
  final broker = FakeBroker();
  late Directory folder;
  const listen = 'POST /databases/app/collections/notes/listen';

  setUpAll(() async {
    folder = await Directory.systemTemp.createTemp('abrova_sync_listen');
    useTestEngine(client: server.client, folder: folder, sockets: broker.factory);
    server.realtime();
    await AbrovaSync.init(const AbrovaSyncConfig(apiKey: 'ab_live_test'));
    await AbrovaSync.connect();
  });

  tearDownAll(() => folder.delete(recursive: true));

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('connects with the realtime token to the server-given encrypted endpoint', () async {
    final s = broker.current!;
    expect(s.token, 'rt-token');
    expect(s.endpoint.host, 'mqtt-sync.abrova.ir');
    expect(s.endpoint.port, 8885);
    expect(s.endpoint.tls, isTrue);
    expect(s.clientId, startsWith('abrova_sync_desktop_'));
    expect(await AbrovaSync.isConnected(), isTrue);
  });

  test('collection listener: snapshot, newer versions, stale ignored, removed, revoked', () async {
    server.route(listen, {
      'subscriptionId': 's1',
      'topic': 'abrova_sync/p1/s/s1',
      'expiresAt': DateTime.now().add(const Duration(hours: 24)).toUtc().toIso8601String(),
      'documents': [FakeServer.doc('a', {'t': 1}, version: 2)],
    });
    final seen = <List<String>>[];
    final errors = <AbrovaSyncListenerError>[];
    final reg = AbrovaSync.database('app').collection('notes').listen(
      (docs) => seen.add([for (final d in docs) '${d.id}@${d.version}']),
      onError: (e) => errors.add(e as AbrovaSyncListenerError),
    );
    await settle();
    expect(seen.last, ['a@2']);
    final body = server.body(server.called(listen).last);
    expect(body['clientId'], broker.current!.clientId, reason: 'only this connection may receive the events');
    expect(broker.current!.topics, contains('abrova_sync/p1/s/s1'));

    void send(Map<String, Object?> e) => broker.publish('abrova_sync/p1/s/s1', jsonEncode({'subscriptionId': 's1', ...e}));
    send({'type': 'added', 'documentId': 'b', 'data': {'t': 2}, 'version': 1});
    await settle();
    expect(seen.last, ['b@1', 'a@2'], reason: 'no order: the newest on top');
    send({'type': 'modified', 'documentId': 'a', 'data': {'t': 0}, 'version': 1});
    await settle();
    expect(seen.last, ['b@1', 'a@2'], reason: 'a stale version changes nothing');
    send({'type': 'removed', 'documentId': 'b'});
    await settle();
    expect(seen.last, ['a@2']);
    send({'type': 'revoked', 'reason': 'permission'});
    await settle();
    expect(errors.single.code, AbrovaSyncListenerError.listenerRevoked);
    expect(server.called('DELETE /databases/app/listen/s1'), isNotEmpty, reason: 'the subscription is stopped');
    reg.remove();
  });

  test('document listener with query_not_allowed: the app hears it, no retry', () async {
    server.route(listen, {'statusCode': 403, 'code': 'query_not_allowed', 'message': 'No', 'fields': ['owner']}, status: 403);
    final errors = <AbrovaSyncListenerError>[];
    final before = server.called(listen).length;
    final reg = AbrovaSync.database('app').collection('notes').listenDocument('x', (_) {}, onError: (e) => errors.add(e as AbrovaSyncListenerError));
    await settle();
    expect(errors.single.code, AbrovaSyncListenerError.queryNotAllowed);
    expect(errors.single.fields, ['owner']);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(server.called(listen).length, before + 1);
    reg.remove();
  });

  test('after a network drop the listener listens again and catches up', () async {
    var n = 0;
    server.routes[listen] = (_) => _json({
      'subscriptionId': 'q${++n}',
      'topic': 'abrova_sync/p1/s/q$n',
      'expiresAt': DateTime.now().add(const Duration(hours: 24)).toUtc().toIso8601String(),
      'documents': [FakeServer.doc('a', {'round': n}, version: n)],
    });
    final seen = <int>[];
    final reg = AbrovaSync.database('app').collection('notes').query().where('round', QueryOperator.greaterThan, 0).listen(
      (docs) => seen.add(docs.single.data['round'] as int),
    );
    await settle();
    expect(seen, [1]);
    broker.current!.drop();
    expect(await AbrovaSync.isConnected(), isFalse);
    // Reconnects by itself (fresh token) after the 2 s backoff; the listener catches up then.
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    expect(await AbrovaSync.isConnected(), isTrue);
    await settle();
    expect(seen, [1, 2]);
    expect(server.called('POST /connections/token').length, greaterThanOrEqualTo(2), reason: 'a fresh token for the reconnect');
    reg.remove();
  });

  test('a server without listen routes: topics, then a fresh read on each change', () async {
    server.routes.remove(listen); // the fake answers "Cannot POST …"
    var reads = 0;
    server.routes['GET /databases/app/collections/notes/documents/sdk'] = (_) => _json({'data': [FakeServer.doc('z', {'r': ++reads})], 'total': 1});
    final seen = <int>[];
    final reg = AbrovaSync.database('app').collection('notes').listen((docs) => seen.add(docs.single.data['r'] as int));
    await settle();
    expect(seen, [1]);
    expect(broker.current!.topics, contains('abrova_sync/p1/app/notes/changes'));
    broker.publish('abrova_sync/p1/app/notes/changes', jsonEncode({'type': 'update', 'documentId': 'z'}));
    await settle();
    expect(seen, [1, 2]);
    reg.remove();
    expect(broker.current!.topics, isNot(contains('abrova_sync/p1/app/notes/changes')));
  });
}

http.Response _json(Object body) => http.Response(jsonEncode(body), 200);
