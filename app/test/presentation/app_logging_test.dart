import 'package:bar_tab/presentation/app_logging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  test('formats level, logger, message', () {
    final r = LogRecord(Level.INFO, 'hello', 'sync');
    expect(formatLogRecord(r), 'INFO sync: hello');
  });

  test('appends error and stack trace', () {
    final r = LogRecord(
      Level.SEVERE,
      'failed',
      'order',
      StateError('boom'),
      StackTrace.fromString('#0 frame'),
    );
    expect(
      formatLogRecord(r),
      'SEVERE order: failed\nBad state: boom\n#0 frame',
    );
  });
}
