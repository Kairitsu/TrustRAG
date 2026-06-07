import 'dart:convert';

/// Splits incoming UTF-8 chunks into complete SSE lines, preserving partial lines
/// across network fragments.
class SseLineBuffer {
  String _buffer = '';

  List<String> drainLines(String chunk) {
    _buffer += chunk;
    final lines = <String>[];
    var start = 0;
    for (var i = 0; i < _buffer.length; i++) {
      if (_buffer.codeUnitAt(i) == 10) {
        var line = _buffer.substring(start, i);
        if (line.endsWith('\r')) {
          line = line.substring(0, line.length - 1);
        }
        lines.add(line);
        start = i + 1;
      }
    }
    _buffer = _buffer.substring(start);
    return lines;
  }

  List<String> flushRemaining() {
    if (_buffer.isEmpty) return const [];
    final line = _buffer.endsWith('\r')
        ? _buffer.substring(0, _buffer.length - 1)
        : _buffer;
    _buffer = '';
    return [line];
  }
}

class ParsedSseEvent {
  final String eventType;
  final String data;

  const ParsedSseEvent({required this.eventType, required this.data});
}

/// Parses SSE `event:` / `data:` lines into discrete events.
class SseEventParser {
  String _currentEventType = '';

  ParsedSseEvent? feedLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      _currentEventType = '';
      return null;
    }
    if (trimmed.startsWith('event: ')) {
      _currentEventType = trimmed.substring(7).trim();
      return null;
    }
    if (!trimmed.startsWith('data:')) return null;

    final jsonStr = trimmed.substring(5).trim();
    if (jsonStr.isEmpty) return null;

    return ParsedSseEvent(eventType: _currentEventType, data: jsonStr);
  }
}

/// Tracks whether the assistant stream produced a committed response.
class ChatStreamOutcome {
  bool receivedAnyText = false;
  bool receivedMessageEnd = false;
  bool receivedStreamError = false;
  bool assistantMessageCommitted = false;

  bool get shouldShowNoContentWarning =>
      !receivedAnyText &&
      !receivedMessageEnd &&
      !receivedStreamError &&
      !assistantMessageCommitted;
}

/// Returns the text delta from a `text_delta` SSE payload.
String? parseTextDelta(String data) {
  try {
    final event = jsonDecode(data);
    if (event is! Map) return null;
    final delta = event['delta'] ?? event['text'];
    if (delta == null) return null;
    final text = delta.toString();
    return text.isEmpty ? null : text;
  } catch (_) {
    return null;
  }
}

/// Returns a human-readable error message from an `error` SSE payload.
String parseStreamErrorMessage(String data) {
  try {
    final decoded = jsonDecode(data);
    if (decoded is String) return decoded;
    if (decoded is Map && decoded['message'] != null) {
      return decoded['message'].toString();
    }
  } catch (_) {}
  return data;
}