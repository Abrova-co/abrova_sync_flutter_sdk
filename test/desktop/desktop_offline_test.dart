// Offline on a computer: queue while offline, replay when back, roll back what
// the server refuses, and survive a restart (files on disk).
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
  const docs = '/databases/app/collections/notes/documents/sdk';
  final states = <SyncState>[];
  final counts = <int>[];
  final rejected = <(String, SyncOperationType, AbrovaSyncError)>[];

  setUpAll(() async {
    folder = await Directory.systemTemp.createTemp('abrova_sync_offline');
    useTestEngine(client: server.client, folder: folder, sockets: broker.factory);
    AbrovaSync.onSyncState(states.add);
    AbrovaSync.onPendingCount(counts.add);
    AbrovaSync.onDocumentRejected((id, op, e) => rejected.add((id, op, e)));
    await AbrovaSync.init(const AbrovaSyncConfig(apiKey: 'ab_live_test', offlineEnabled: true));
  });

  tearDownAll(() => folder.delete(recursive: true));

  Future<void> settle([int ms = 30]) => Future<void>.delayed(Duration(milliseconds: ms));

  test('before the connection says anything, writes go to the network', () async {
    server.route('POST $docs', {'data': FakeServer.doc('s1', {'v': 0})});
    final d = await AbrovaSync.database('app').collection('notes').add({'v': 0});
    expect(d.id, 's1');
  });

  test('offline: add gets a local id, is queued and shown', () async {
    server.down = true;
    await expectLater(AbrovaSync.connect(), throwsA(isA<AbrovaSyncError>()));
    await settle();
    expect(await AbrovaSync.getSyncState(), SyncState.offline);
    final c = AbrovaSync.database('app').collection('notes');
    final d = await c.add({'v': 1});
    expect(d.id, startsWith('local_'));
    await c.set('s1', {'v': 9}, merge: true);
    await settle();
    expect(await AbrovaSync.getPendingCount(), 2);
    expect(counts.last, 2);
    final all = await c.getAll();
    expect(all.map((x) => x.data['v']), containsAll([1, 9]));
    final q = await c.where('v', QueryOperator.greaterThan, 5).get();
    expect(q.single.id, 's1', reason: 'queries run on the cache while offline');
  });

  test('back online: the queue replays in order, local ids become server ids', () async {
    server.down = false;
    server.realtime();
    var made = 0;
    server.routes['POST $docs'] = (req) => _json({'data': FakeServer.doc('srv${++made}', (jsonDecode(req.body) as Map)['data'] as Map<String, Object?>)});
    server.route('GET $docs/s1', {'data': FakeServer.doc('s1', {'v': 0})});
    server.route('PUT $docs/s1', {'data': FakeServer.doc('s1', {'v': 9}, version: 2)});
    await Future<void>.delayed(const Duration(milliseconds: 2300)); // the 2 s retry
    await settle(100);
    expect(await AbrovaSync.isConnected(), isTrue);
    expect(await AbrovaSync.getPendingCount(), 0);
    expect(states, containsAllInOrder([SyncState.offline, SyncState.syncing, SyncState.idle]));
    expect(server.body(server.called('PUT $docs/s1').single), {'data': {'v': 9}, 'merge': true});
    expect(server.called('POST $docs').length, 2, reason: 'the first add online, then the queued one');
  });

  test('a queued write the server refuses is rolled back and reported', () async {
    broker.current!.drop();
    await settle();
    final c = AbrovaSync.database('app').collection('notes');
    await c.update('s1', {'v': 10});
    expect(await AbrovaSync.getPendingCount(), 1);
    server.route('GET $docs/s1', {'data': FakeServer.doc('s1', {'v': 9}, version: 2)});
    server.route('PATCH $docs/s1', {'statusCode': 403, 'message': 'Denied by rules'}, status: 403);
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    await settle(100);
    expect(rejected.single.$1, 's1');
    expect(rejected.single.$2, SyncOperationType.update);
    expect(rejected.single.$3.statusCode, 403);
    expect((await c.get('s1'))!.data['v'], 9, reason: 'back to the server copy');
    expect(await AbrovaSync.getPendingCount(), 0);
  });

  test('the queue survives a restart (files on disk)', () async {
    broker.current!.drop();
    await settle();
    await AbrovaSync.database('app').collection('notes').add({'kept': true});
    await AbrovaSync.forceSyncNow(); // offline: nothing to send
    await settle(300); // written to disk
    final files = folder.listSync(recursive: true).whereType<File>().where((f) => f.path.contains('/cache/'));
    final text = files.map((f) => f.readAsStringSync()).join();
    expect(text, contains('"kept":true'));
    expect(text, contains('pendingCreate'));
  });
}

http.Response _json(Object body) => http.Response(jsonEncode(body), 200);
