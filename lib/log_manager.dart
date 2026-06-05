import 'package:flutter/foundation.dart';

class LogEntry {
  final String message;
  final DateTime timestamp;
  final bool isError;

  LogEntry({
    required this.message,
    DateTime? timestamp,
    this.isError = false,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() {
    final timeStr = timestamp.toString().substring(11, 19);
    final prefix = isError ? '[ERROR] ' : '';
    return '$timeStr $prefix$message';
  }
}

class LogManager extends ChangeNotifier {
  static final LogManager _instance = LogManager._internal();
  factory LogManager() => _instance;
  LogManager._internal();

  final List<LogEntry> _logs = [];
  static const int _maxLogs = 1000;

  List<LogEntry> get logs => List.unmodifiable(_logs);

  void addLog(String message, {bool isError = false}) {
    final entry = LogEntry(message: message, isError: isError);
    _logs.add(entry);

    // 限制日志数量
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }

    // 控制台输出
    if (isError) {
      debugPrint('❌ $message');
    } else {
      debugPrint('ℹ️ $message');
    }

    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  String getLogsAsString() {
    return _logs.map((e) => e.toString()).join('\n');
  }
}
