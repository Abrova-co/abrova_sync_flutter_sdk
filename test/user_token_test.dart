import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abrova_sync/abrova_sync.dart';

/// A token shaped like the real one: only `sub` and `exp` matter here.
String tokenFor(String user, {required Duration expiresIn}) {
  String part(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final exp = DateTime.now().add(expiresIn).millisecondsSinceEpoch ~/ 1000;
  return '${part({'alg': 'ES256'})}.${part({'sub': user, 'exp': exp})}.sig';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ir.abrova.sync/abrova_sync');
  final calls = <MethodCall>[];
  var awaiting = false;

  List<String?> tokensSet() => calls
      .where((c) => c.method == 'setUserToken')
      .map((c) => (c.arguments as Map)['token'] as String?)
      .toList();

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'isAwaitingUserToken') return awaiting;
      return null;
    });
  });

  // AbrovaSync keeps static state, so the order of these tests matters: the
  // first one initialises the SDK for the rest.
  String? next;
  var providerCalls = 0;
  var providerFails = false;
  Future<String?> provider() async {
    providerCalls++;
    if (providerFails) throw StateError('backend unreachable');
    return next;
  }

  test('init asks the provider and starts with its token', () async {
    next = tokenFor('user-1', expiresIn: const Duration(hours: 1));
    await AbrovaSync.init(AbrovaSyncConfig(apiKey: 'ab_live_key', tokenProvider: provider));

    expect(providerCalls, 1);
    final args = calls.singleWhere((c) => c.method == 'init').arguments as Map;
    expect(args['userToken'], next);
  });

  test('refreshUserToken hands the provider\'s token to the SDK', () async {
    next = tokenFor('user-2', expiresIn: const Duration(hours: 1));
    await AbrovaSync.refreshUserToken();

    expect(tokensSet(), [next]);
  });

  test('a signed-out provider clears the token', () async {
    next = null;
    await AbrovaSync.refreshUserToken();

    expect(tokensSet(), [null]);
  });

  test('a failing provider leaves the SDK\'s token alone', () async {
    providerFails = true;
    await AbrovaSync.refreshUserToken();
    providerFails = false;

    expect(tokensSet(), isEmpty);
  });

  testWidgets('renews the token shortly before it expires', (tester) async {
    // Expires in 90 s, so the renewal is due about 30 s from now.
    next = tokenFor('user-1', expiresIn: const Duration(seconds: 90));
    await AbrovaSync.refreshUserToken();
    final renewed = tokenFor('user-1', expiresIn: const Duration(hours: 1));
    next = renewed;
    calls.clear();

    await tester.pump(const Duration(seconds: 20));
    expect(tokensSet(), isEmpty);

    await tester.pump(const Duration(seconds: 15));
    expect(tokensSet(), [renewed]);

    // Stop the renewal planned for the one-hour token.
    await AbrovaSync.setTokenProvider(null);
  });

  test('reports when connect is waiting for a user token', () async {
    var notified = 0;
    AbrovaSync.onAwaitingUserToken(() => notified++);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('onAwaitingUserToken')),
      (_) {},
    );
    expect(notified, 1);

    awaiting = true;
    expect(await AbrovaSync.isAwaitingUserToken(), true);
  });

  test('connect completes normally while waiting for a token', () async {
    await AbrovaSync.connect(); // native parks the connect; no exception
    expect(calls.where((c) => c.method == 'connect').length, 1);
  });
}
