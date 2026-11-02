import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// One printable line (plus error and stack trace, if any) per record.
/// Callers must not log secrets such as the device key.
String formatLogRecord(LogRecord r) {
  final buf = StringBuffer('${r.level.name} ${r.loggerName}: ${r.message}');
  if (r.error != null) buf.write('\n${r.error}');
  if (r.stackTrace != null) buf.write('\n${r.stackTrace}');
  return buf.toString();
}

/// Routes `package:logging` records to the console (logcat).
void initLogging() {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) => debugPrint(formatLogRecord(r)));
}
