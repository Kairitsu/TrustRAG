import 'package:flutter_test/flutter_test.dart';

import 'package:client/features/chat/services/chat_sse_parser.dart';

void main() {
  group('SseLineBuffer', () {
    test('splits complete lines within a single chunk', () {
      final buffer = SseLineBuffer();
      final lines = buffer.drainLines('event: text_delta\ndata: {"delta":"hi"}\n\n');
      expect(lines, ['event: text_delta', 'data: {"delta":"hi"}', '']);
    });

    test('preserves partial line across chunks', () {
      final buffer = SseLineBuffer();
      expect(buffer.drainLines('event: text_del'), isEmpty);
      final lines = buffer.drainLines('ta\ndata: {"delta":"x"}\n');
      expect(lines, ['event: text_delta', 'data: {"delta":"x"}']);
    });

    test('handles CRLF line endings', () {
      final buffer = SseLineBuffer();
      final lines = buffer.drainLines('event: message_end\r\ndata: {}\r\n');
      expect(lines, ['event: message_end', 'data: {}']);
    });
  });

  group('SseEventParser', () {
    test('pairs event type with following data line', () {
      final parser = SseEventParser();
      expect(parser.feedLine('event: text_delta'), isNull);
      final event = parser.feedLine('data: {"delta":"hello"}');
      expect(event, isNotNull);
      expect(event!.eventType, 'text_delta');
      expect(event.data, '{"delta":"hello"}');
    });

    test('resets event type after blank line', () {
      final parser = SseEventParser();
      parser.feedLine('event: error');
      parser.feedLine('data: boom');
      parser.feedLine('');
      final event = parser.feedLine('data: orphan');
      expect(event!.eventType, '');
    });
  });

  group('ChatStreamOutcome', () {
    test('does not warn after message_end with text', () {
      final outcome = ChatStreamOutcome()
        ..receivedAnyText = true
        ..receivedMessageEnd = true
        ..assistantMessageCommitted = true;
      expect(outcome.shouldShowNoContentWarning, isFalse);
    });

    test('warns only when stream produced nothing', () {
      expect(ChatStreamOutcome().shouldShowNoContentWarning, isTrue);

      final withError = ChatStreamOutcome()..receivedStreamError = true;
      expect(withError.shouldShowNoContentWarning, isFalse);

      final withEnd = ChatStreamOutcome()..receivedMessageEnd = true;
      expect(withEnd.shouldShowNoContentWarning, isFalse);
    });
  });

  group('message_end flow simulation', () {
    test('committed assistant response prevents empty-content warning', () {
      final lineBuffer = SseLineBuffer();
      final eventParser = SseEventParser();
      final outcome = ChatStreamOutcome();
      var streamingContent = '';

      void processChunk(String chunk) {
        for (final line in lineBuffer.drainLines(chunk)) {
          final parsed = eventParser.feedLine(line);
          if (parsed == null) continue;

          switch (parsed.eventType) {
            case 'text_delta':
              final delta = parseTextDelta(parsed.data);
              if (delta != null) {
                outcome.receivedAnyText = true;
                streamingContent += delta;
              }
            case 'message_end':
              outcome.receivedMessageEnd = true;
              if (streamingContent.isNotEmpty) {
                outcome.assistantMessageCommitted = true;
                streamingContent = '';
              }
            case 'error':
              outcome.receivedStreamError = true;
          }
        }
      }

      processChunk('event: text_delta\ndata: {"delta":"回答内容"}\n\n');
      processChunk('event: message_end\ndata: {"message_id":"abc"}\n\n');

      expect(outcome.receivedAnyText, isTrue);
      expect(outcome.receivedMessageEnd, isTrue);
      expect(outcome.assistantMessageCommitted, isTrue);
      expect(streamingContent, isEmpty);
      expect(outcome.shouldShowNoContentWarning, isFalse);
    });
  });
}