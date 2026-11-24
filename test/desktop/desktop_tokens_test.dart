// Signed user tokens on a computer: wait for one when the project requires
// it, connect when it comes, reconnect when the signed-in user changes.
import 'dart:convert';
import 'dart:io';

import 'package:abrova_sync/abrova_sync.dart';
import 'package:abrova_sync_desktop/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_server.dart';

String jwt(String sub) {
  String part(Map<String, Object?> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  return '${part({'alg': 'HS256'})}.${part({'sub': sub, 'exp': exp})}.sig';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final server = FakeServer();
  final broker = FakeBroker();
  late Directory folder;
  var waited = 0;

  setUpAll(() async {
    folder = await Directory.systemTemp.createTemp('abrova_sync_tokens');
    useTestEngine(client: server.client, folder: folder, sockets: broker.factory);
    AbrovaSync.onAwaitingUserToken(() => waited++);
    await AbrovaSync.init(const AbrovaSyncConfig(apiKey: 'ab_live_test'));
  });

  tearDownAll(() => folder.delete(recursive: true));

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

  test('token required: connect() succeeds and waits, no retries', () async {
    server.route('POST /connections/token', {'statusCode': 401, 'code': 'token_required', 'message': 'Sign in'}, status: 401);
    await AbrovaSync.connect();
    await settle();
    expect(waited, 1);
    expect(await AbrovaSync.isAwaitingUserToken(), isTrue);
    expect(await AbrovaSync.isConnected(), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    expect(server.called('POST /connections/token').length, 1, reason: 'no retry loop while waiting');
  });

  test('a token arrives: it connects as that user, requests carry X-User-Token', () async {
    server.realtime();
    final userA = jwt('user-a');
    await AbrovaSync.setUserToken(userA);
    await settle();
    expect(await AbrovaSync.isConnected(), isTrue);
    expect(await AbrovaSync.isAwaitingUserToken(), isFalse);
    final req = server.called('POST /connections/token').last;
    expect(req.headers['X-User-Token'], userA);
    expect(req.headers.containsKey('X-User-Id'), isFalse);
  });

  test('another user signs in: one reconnect; the same user with a new token: none', () async {
    final sockets = broker.sockets.length;
    await AbrovaSync.setUserToken(jwt('user-a'));
    await settle();
    expect(broker.sockets.length, sockets, reason: 'same user, nothing to do');
    await AbrovaSync.setUserToken(jwt('user-b'));
    await settle();
    expect(broker.sockets.length, sockets + 1);
    expect(await AbrovaSync.isConnected(), isTrue);
  });
}
