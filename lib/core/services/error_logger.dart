import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart' show kIsWeb;

enum LogLevel {
  debug(0),
  info(1),
  warning(2),
  error(3),
  critical(4);

  const LogLevel(this.value);
  final int value;

  static LogLevel fromString(String s) {
    switch (s.toLowerCase()) {
      case 'debug': return LogLevel.debug;
      case 'info': return LogLevel.info;
      case 'warning': return LogLevel.warning;
      case 'error': return LogLevel.error;
      case 'critical': return LogLevel.critical;
      default: return LogLevel.info;
    }
  }
}

class ErrorLogger {
  static final ErrorLogger instance = ErrorLogger._init();
  ErrorLogger._init();

  File? _logFile;
  String? _currentLogDate;
  LogLevel minLevel = LogLevel.info;

  Future<File> get logFile async {
    if (_logFile != null) return _logFile!;
    if (kIsWeb) throw UnsupportedError('السجل غير مدعوم على الويب');

    final appDataDir = Platform.environment['APPDATA']
        ?? Platform.environment['HOME']
        ?? '.';
    final logDir = Directory(p.join(appDataDir, 'AHLA_logs'));
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }
    _logFile = File(p.join(logDir.path, 'app_log.txt'));
    await _rotateIfNeeded();
    return _logFile!;
  }

  Future<void> _rotateIfNeeded() async {
    final today = DateTime.now();
    final dateKey = '${today.year}-${_pad(today.month)}-${_pad(today.day)}';
    if (_currentLogDate == dateKey) return;

    _currentLogDate = dateKey;
    final appDataDir = Platform.environment['APPDATA']
        ?? Platform.environment['HOME']
        ?? '.';
    final logDir = Directory(p.join(appDataDir, 'AHLA_logs'));

    // تنظيف الملفات الأقدم من 30 يوم
    final cutoff = today.subtract(const Duration(days: 30));
    if (await logDir.exists()) {
      await for (final entity in logDir.list()) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            if (stat.modified.isBefore(cutoff)) {
              await entity.delete();
            }
          } catch (_) {}
        }
      }
    }
  }

  Future<void> log(String message, {LogLevel level = LogLevel.info, Map<String, dynamic>? data}) async {
    if (level.value < minLevel.value) return;
    try {
      await _rotateIfNeeded();
      final file = await logFile;
      final now = DateTime.now();
      final timestamp = _formatTimestamp(now);
      final entry = _buildJsonEntry(timestamp, level.name.toUpperCase(), message, data);
      await file.writeAsString(entry, mode: FileMode.append);
    } catch (_) {
      // لا نسجّل خطأ في التسجيل نفسه
    }
  }

  Future<void> logError(dynamic error, StackTrace? stack, {String? context, Map<String, dynamic>? data}) async {
    try {
      await _rotateIfNeeded();
      final file = await logFile;
      final now = DateTime.now();
      final timestamp = _formatTimestamp(now);
      final combinedData = <String, dynamic>{
        ...?data,
        'error': error.toString(),
        if (stack != null) 'stack': stack.toString().split('\n').take(20).toList(),
      };
      final entry = _buildJsonEntry(timestamp, 'ERROR', context ?? 'خطأ غير متوقع', combinedData);
      await file.writeAsString(entry, mode: FileMode.append);
    } catch (_) {}
  }

  Future<void> debug(String message, {Map<String, dynamic>? data}) => log(message, level: LogLevel.debug, data: data);
  Future<void> info(String message, {Map<String, dynamic>? data}) => log(message, level: LogLevel.info, data: data);
  Future<void> warning(String message, {Map<String, dynamic>? data}) => log(message, level: LogLevel.warning, data: data);
  Future<void> error(String message, {Map<String, dynamic>? data}) => log(message, level: LogLevel.error, data: data);
  Future<void> critical(String message, {Map<String, dynamic>? data}) => log(message, level: LogLevel.critical, data: data);

  String _formatTimestamp(DateTime dt) => '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}.${dt.millisecond.toString().padLeft(3, '0')}';

  String _buildJsonEntry(String timestamp, String level, String message, Map<String, dynamic>? data) {
    final obj = {
      'timestamp': timestamp,
      'level': level,
      'message': message,
      if (data != null && data.isNotEmpty) 'data': data,
    };
    return '${jsonEncode(obj)}\n';
  }

  Future<String> readLog({int? maxLines}) async {
    try {
      final file = await logFile;
      if (!await file.exists()) return '';
      final content = await file.readAsString();
      if (maxLines == null) return content;
      final lines = content.trim().split('\n');
      return lines.length > maxLines ? lines.sublist(lines.length - maxLines).join('\n') : content;
    } catch (_) {
      return '';
    }
  }

  Future<void> clearLog() async {
    try {
      final file = await logFile;
      if (await file.exists()) {
        await file.writeAsString('');
      }
    } catch (_) {}
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}