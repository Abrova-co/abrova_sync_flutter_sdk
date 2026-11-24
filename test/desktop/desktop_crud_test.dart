// The Flutter API on a computer: every call goes through abrova_sync_desktop's
// Dart engine (no native SDK), with the same paths, headers and answers.
import 'dart:io';

import 'package:abrova_sync/abrova_sync.dart';
import 'package:abrova_sync_desktop/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'fake_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final server = FakeServer();
  final broker = FakeBroker();
  late Directory folder;

  setUpAll(() async {
    folder = await Directory.systemTemp.createTemp('abrova_sync_crud');
    useTestEngine(client: server.client, folder: folder, sockets: broker.factory);
    await AbrovaSync.init(const AbrovaSyncConfig(apiKey: 'ab_live_test'));
  });

  tearDownAll(() => folder.delete(recursive: true));

  const docs = '/databases/app/collections/notes/documents/sdk';

  test('add: POST with the data; headers say who is calling', () async {
    server.route('POST $docs', {'data': FakeServer.doc('n1', {'text': 'hi'})});
    final doc = await AbrovaSync.database('app').collection('notes').add({'text': 'hi'});
    expect(doc.id, 'n1');
    expect(doc.data, {'text': 'hi'});
    expect(doc.createdAt, DateTime.utc(2026, 11, 24, 10).millisecondsSinceEpoch);
    final req = server.called('POST $docs').single;
    expect(server.body(req), {'data': {'text': 'hi'}});
    expect(req.headers['X-API-Key'], 'ab_live_test');
    expect(req.headers['X-Abrova-SDK'], startsWith('flutter-desktop/0.1.0 flutter/'));
    expect(req.headers['X-User-Id'], isNotEmpty, reason: 'a stable id for this install');
    expect(req.headers.containsKey('X-User-Token'), isFalse);
  });

  test('get: a document, and null when the server has none', () async {
    server.route('GET $docs/n1', {'data': FakeServer.doc('n1', {'text': 'hi'}, version: 3)});
    final c = AbrovaSync.database('app').collection('notes');
    expect((await c.get('n1'))?.version, 3);
    expect(await c.get('missing'), isNull);
  });

  test('getAll: every page until the total', () async {
    var page = 0;
    server.routes['GET $docs'] = (req) {
      final skip = int.parse(req.url.queryParameters['skip']!);
      expect(req.url.queryParameters['limit'], '100');
      page++;
      final n = skip == 0 ? 100 : 20;
      return _json({'data': [for (var i = 0; i < n; i++) FakeServer.doc('d${skip + i}', {'i': skip + i})], 'total': 120});
    };
    final all = await AbrovaSync.database('app').collection('notes').getAll();
    expect(all, hasLength(120));
    expect(page, 2);
  });

  test('update PATCH, set PUT with merge, delete (404 counts as deleted)', () async {
    server.route('PATCH $docs/n1', {'data': FakeServer.doc('n1', {'text': 'x'}, version: 2)});
    server.route('PUT $docs/n1', {'data': FakeServer.doc('n1', {'text': 'y'}, version: 3)});
    final c = AbrovaSync.database('app').collection('notes');
    await c.update('n1', {'text': 'x'});
    expect(server.body(server.called('PATCH $docs/n1').single), {'data': {'text': 'x'}});
    await c.set('n1', {'text': 'y'}, merge: true);
    expect(server.body(server.called('PUT $docs/n1').single), {'data': {'text': 'y'}, 'merge': true});
    await c.set('n1', {'text': 'y'});
    expect(server.body(server.called('PUT $docs/n1').last)['merge'], false);
    await c.delete('gone'); // the fake answers 404
  });

  test('query: filters, order, limit, offset as the phones send them', () async {
    server.route('POST $docs/query', {'data': [FakeServer.doc('n2', {'n': 5})]});
    final r = await AbrovaSync.database('app').collection('notes')
        .where('n', QueryOperator.greaterThan, 1)
        .orderBy('n', direction: OrderDirection.descending)
        .limit(10)
        .offset(5)
        .get();
    expect(r.single.id, 'n2');
    expect(server.body(server.called('POST $docs/query').single), {
      'filters': [{'field': 'n', 'operator': '>', 'value': 1}],
      'orderBy': {'field': 'n', 'direction': 'desc'},
      'limit': 10,
      'offset': 5,
    });
  });

  test('a refusal reaches the app typed: 403 query_not_allowed with its fields', () async {
    server.route('POST $docs/query', {'statusCode': 403, 'code': 'query_not_allowed', 'message': 'Not allowed', 'fields': ['teamId']}, status: 403);
    await expectLater(
      AbrovaSync.database('app').collection('notes').where('x', QueryOperator.equal, 1).get(),
      throwsA(isA<AbrovaSyncError>()
          .having((e) => e.code, 'code', AbrovaSyncErrorCode.queryNotAllowed)
          .having((e) => e.fields, 'fields', ['teamId'])
          .having((e) => e.statusCode, 'statusCode', 403)),
    );
  });

  test('batch: one POST /batch/sdk with every operation', () async {
    server.route('POST /batch/sdk', {'success': true});
    final db = AbrovaSync.database('app');
    final b = AbrovaSync.batch()
      ..set(db.collection('notes'), 'a', {'v': 1}, merge: true)
      ..update(db.collection('notes'), 'b', {'v': 2})
      ..delete(db.collection('notes'), 'c')
      ..create(db.collection('notes'), {'v': 3});
    await b.commit();
    final ops = server.body(server.called('POST /batch/sdk').single)['operations'] as List;
    expect(ops.map((o) => (o as Map)['type']), ['set', 'update', 'delete', 'create']);
  });
}

http.Response _json(Object body) => http.Response(jsonEncode(body), 200);
