import 'package:flutter_test/flutter_test.dart';

/// Mirrors the static _injectCitationLinks logic from chat_page.dart
String injectCitationLinks(String content, Set<int> validIndices) {
  return content.replaceAllMapped(
    RegExp(r'\[(\d+)\]'),
    (m) {
      final num = int.tryParse(m.group(1)!);
      if (num == null || !validIndices.contains(num)) return m.group(0)!;
      return '[`[$num]`](#cite-$num)';
    },
  );
}

void main() {
  group('Citation inline link injection', () {
    test('converts valid citation indices to markdown links', () {
      const input = 'This is a fact [1] and another [2].';
      final result = injectCitationLinks(input, {1, 2, 3});
      expect(result, contains('[`[1]`](#cite-1)'));
      expect(result, contains('[`[2]`](#cite-2)'));
    });

    test('does not convert invalid citation indices', () {
      const input = 'This references [99] which does not exist.';
      final result = injectCitationLinks(input, {1, 2, 3});
      expect(result, contains('[99]'));
      expect(result, isNot(contains('#cite-99')));
    });

    test('handles mixed valid and invalid indices', () {
      const input = 'Valid [1] and invalid [50] and valid [3].';
      final result = injectCitationLinks(input, {1, 3});
      expect(result, contains('[`[1]`](#cite-1)'));
      expect(result, contains('[50]'));
      expect(result, isNot(contains('#cite-50')));
      expect(result, contains('[`[3]`](#cite-3)'));
    });

    test('handles content with no citations', () {
      const input = 'No citations here at all.';
      final result = injectCitationLinks(input, {1, 2});
      expect(result, equals(input));
    });

    test('handles empty valid indices set', () {
      const input = 'Reference [1] should not be linked.';
      final result = injectCitationLinks(input, {});
      expect(result, equals(input));
    });

    test('handles multiple occurrences of same index', () {
      const input = 'First [1] then again [1].';
      final result = injectCitationLinks(input, {1});
      final matches = RegExp(r'#cite-1').allMatches(result);
      expect(matches.length, 2);
    });

    test('does not break markdown list items like [1.', () {
      const input = 'List:\n1. Item one\n2. Item two\nCitation [1].';
      final result = injectCitationLinks(input, {1});
      expect(result, contains('1. Item one'));
      expect(result, contains('[`[1]`](#cite-1)'));
    });
  });
}
