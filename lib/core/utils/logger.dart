import 'package:logging/logging.dart';

/// Central application logger.
///
/// Replaces ad-hoc `print()` calls (which are disabled in production builds
/// and flagged by the `avoid_print` lint) with a proper logging framework.
///
/// Usage:
/// ```dart
/// import 'package:wasalny_rider/core/utils/logger.dart';
/// logInfo('SomeComponent', 'message');
/// logWarning('SomeComponent', 'warning');
/// logError('SomeComponent', 'error', e, stack);
/// ```

/// Severity-based console printer.
typedef LogPrinter = void Function(LogRecord record);

/// Configures the root logger. Call this once from `main()` before the app
/// starts doing any work.
void setupLogging({Level level = Level.ALL, LogPrinter? printer}) {
  Logger.root.level = level;
  Logger.root.onRecord.listen(printer ?? _defaultPrinter);
}

void _defaultPrinter(LogRecord record) {
  final emoji = switch (record.level) {
    Level.SHOUT => '🔥',
    Level.SEVERE => '❌',
    Level.WARNING => '⚠️',
    Level.INFO => 'ℹ️',
    Level.CONFIG => '⚙️',
    Level.FINE => '🐛',
    _ => '  ',
  };
  final buffer = StringBuffer()
    ..write(emoji)
    ..write(' [')
    ..write(record.loggerName)
    ..write('] ')
    ..write(record.message);
  if (record.error != null) {
    buffer
      ..write('\n    error: ')
      ..write(record.error);
  }
  if (record.stackTrace != null) {
    buffer
      ..write('\n    stack: ')
      ..write(record.stackTrace);
  }
  // ignore: avoid_print
  print(buffer.toString());
}

/// Returns a named logger for the given component.
Logger getLogger(String name) => Logger(name);

/// Convenience helpers built on top of a named logger.
void logFine(String name, Object? message) => Logger(name).fine(message);
void logConfig(String name, Object? message) => Logger(name).config(message);
void logInfo(String name, Object? message) => Logger(name).info(message);
void logWarning(String name, Object? message) => Logger(name).warning(message);
void logError(
  String name,
  Object? message, [
  Object? error,
  StackTrace? stackTrace,
]) => Logger(name).severe(message, error, stackTrace);
