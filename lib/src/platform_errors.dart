import 'package:flutter/services.dart';

import 'abrova_sync_error.dart';

/// Runs [call] and turns the native side's errors into [AbrovaSyncError]s,
/// with the HTTP status the server answered with ([AbrovaSyncError.statusCode])
/// and, for a `query_not_allowed` answer, [AbrovaSyncErrorCode.queryNotAllowed]
/// and its `fields`.
Future<T> withTypedErrors<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on PlatformException catch (e) {
    throw AbrovaSyncError.fromPlatformException(e);
  }
}

/// The error a listener event carries, or null when it carries none.
AbrovaSyncListenerError? listenerErrorOf(Map<dynamic, dynamic> event) {
  final error = event['error'];
  if (error == null) return null;
  if (error is Map) return AbrovaSyncListenerError.fromMap(error);
  return AbrovaSyncListenerError(code: 'UNKNOWN_ERROR', message: error.toString());
}
