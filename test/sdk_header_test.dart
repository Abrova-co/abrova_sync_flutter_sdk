import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abrova_sync/abrova_sync.dart';

/// The plugin hands its identity to the native SDK, which sends
/// `X-Abrova-SDK: flutter/<version> android|ios/<native version>`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('abrovaSyncSdkVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(abrovaSyncSdkVersion, match!.group(1));
    expect(abrovaSyncSdkName, 'flutter');
  });

  test('AbrovaSyncConfig forwards the wrapper identity', () {
    final map = const AbrovaSyncConfig(apiKey: 'ab_live_test').toMap();
    expect(map['wrapperSdkName'], 'flutter');
    expect(map['wrapperSdkVersion'], abrovaSyncSdkVersion);
  });

  test('init sends the wrapper identity to the native SDK', () async {
    const channel = MethodChannel('ir.abrova.sync/abrova_sync');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));

    await AbrovaSync.init(const AbrovaSyncConfig(apiKey: 'ab_live_test'));

    final args = calls.singleWhere((c) => c.method == 'init').arguments as Map;
    expect(args['apiKey'], 'ab_live_test');
    expect(args['wrapperSdkName'], 'flutter');
    expect(args['wrapperSdkVersion'], abrovaSyncSdkVersion);
  });
}
