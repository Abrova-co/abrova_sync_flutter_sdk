# AbrovaSync Flutter SDK

Realtime database SDK for Flutter with offline-first sync.

[![Flutter 3.3+](https://img.shields.io/badge/Flutter-3.3+-blue.svg)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Installation

The package is published on [Abrova Center](https://center.abrova.ir). Add to your `pubspec.yaml`:

```yaml
dependencies:
  abrova_sync:
    hosted: https://center.abrova.ir/api/packages/abrova/pub
    version: ^0.3.1
```

Then run:

```bash
flutter pub get
```

Android needs no setup: the plugin adds the Abrova Center repository for the native Android SDK itself.

iOS needs no setup either: the plugin includes the native SDK and brings its protocol library from Abrova Center.

If your app uses CocoaPods instead of Swift Package Manager, add these two lines at the top of `ios/Podfile`:

```ruby
source 'https://center.abrova.ir/abrova/specs.git'
source 'https://cdn.cocoapods.org/'
```

## Usage

Databases and collections are addressed by their **name**, exactly as shown in
Abrova Console:

```dart
await AbrovaSync.init(AbrovaSyncConfig(apiKey: 'YOUR_API_KEY'));
await AbrovaSync.connect();

final todos = AbrovaSync.database('my-app').collection('todos');

await todos.add({'title': 'Buy milk', 'completed': false});

final listener = todos.listen((documents) {
  print('Todos updated: ${documents.length}');
});
```

Use names, not UUIDs. Realtime updates are published per database and
collection name, so a UUID still works for plain reads and writes but live
updates never arrive.

## Writing documents

`set()` writes a document with the id you choose. The document becomes exactly
the data you pass:

```dart
await todos.set('todo-1', {'title': 'Buy milk', 'completed': false});
```

To change some fields and keep the others, merge instead:

```dart
await todos.set('todo-1', {'completed': true}, merge: true);
```

`WriteBatch.set()` takes the same `merge` option.

## Listener errors

Your security rules decide what a listener may receive. Pass `onError` to hear
why a listener stopped; after an error it receives nothing more:

```dart
final listener = todos
    .where('teamId', QueryOperator.equal, teamId)
    .listen(
      (documents) => print('Team todos: ${documents.length}'),
      onError: (error) {
        if (error is AbrovaSyncListenerError && error.isQueryNotAllowed) {
          // The rules do not allow this query. error.fields names the
          // filters that would make it allowed.
        } else if (error is AbrovaSyncListenerError && error.isListenerRevoked) {
          // The rules no longer allow it (for example the user left the team).
        }
      },
    );
```

`listen()` and `listenDocument()` take the same `onError`. A query's `get()`
throws a `AbrovaSyncError` with code `AbrovaSyncErrorCode.queryNotAllowed` (and
its `fields`) when the rules do not allow the query.

## Verified user identity

Security Rules check `auth.uid`. The API key ships inside your app, so the app
cannot be trusted to say who the user is - only your own server can. Have your
backend mint a short-lived user token and give the SDK a way to get it:

```dart
await AbrovaSync.init(AbrovaSyncConfig(
  apiKey: 'ab_live_your_api_key',
  // Return null when no one is signed in.
  tokenProvider: () => myBackend.fetchAbrovaToken(),
));

// When the user signs in or out:
await AbrovaSync.refreshUserToken();
```

The SDK asks for a token at start and again before the old one expires. It is
the same Abrova user token Abrova Push and Abrova Chat use, so one function can
serve all three. Your backend mints it with your project's server secret, which
must stay on your server and never ship in an app.

If you would rather fetch the token yourself, call
`AbrovaSync.setUserToken(token)` after `init` and again whenever you refresh it.

If your project has **Require signed user tokens** turned on in the Console, a
token is required; without it, requests are refused. You can still call
`connect()` before anyone is signed in: the SDK waits
(`AbrovaSync.onAwaitingUserToken`) and connects by itself once it has a token.

## Documentation

- [Abrova Cloud](https://abrova.ir/cloud)
- [Abrova Console](https://console.abrova.ir)

## License

MIT
