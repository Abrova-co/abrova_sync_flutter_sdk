/// Name this plugin reports to the Abrova backend as its SDK identity
/// (`X-Abrova-SDK: flutter/<version> android|ios/<native version>`).
const String abrovaSyncSdkName = 'flutter';

/// Version of the abrova_sync plugin.
///
/// Must match `version` in pubspec.yaml (enforced by a unit test).
const String abrovaSyncSdkVersion = '0.3.0';
