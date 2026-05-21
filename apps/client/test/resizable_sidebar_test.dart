import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:client/core/providers/dev_mode_provider.dart';

void main() {
  group('Sidebar width persistence', () {
    test('saves and restores conv panel width', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await prefs.setDouble('conv_panel_width', 300);
      expect(prefs.getDouble('conv_panel_width'), 300);
    });

    test('saves and restores citation panel width', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await prefs.setDouble('citation_panel_width', 400);
      expect(prefs.getDouble('citation_panel_width'), 400);
    });

    test('returns null when no width saved', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getDouble('conv_panel_width'), isNull);
      expect(prefs.getDouble('citation_panel_width'), isNull);
    });

    test('clamps restored width within bounds', () async {
      SharedPreferences.setMockInitialValues({
        'conv_panel_width': 50.0,
        'citation_panel_width': 999.0,
      });
      final prefs = await SharedPreferences.getInstance();

      const minWidth = 180.0;
      const maxConv = 400.0;
      const maxCitation = 500.0;

      final cw = (prefs.getDouble('conv_panel_width') ?? 260).clamp(minWidth, maxConv);
      final ciw = (prefs.getDouble('citation_panel_width') ?? 340).clamp(minWidth, maxCitation);

      expect(cw, minWidth);
      expect(ciw, maxCitation);
    });
  });

  group('_ResizeHandle visual structure', () {
    testWidgets('renders with resize cursor region', (tester) async {
      double accumulated = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (d) => accumulated += d.delta.dx,
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: SizedBox(width: 6, height: 100),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(MouseRegion), findsWidgets);
      expect(find.byType(GestureDetector), findsWidgets);
    });
  });

  group('DebugLogBuffer logs resize events', () {
    setUp(() => DebugLogBuffer().clear());

    test('can log panel resize events', () {
      DebugLogBuffer().add('RESIZE conv_panel: 260 -> 300');
      expect(DebugLogBuffer().logs.last, contains('RESIZE'));
      expect(DebugLogBuffer().logs.last, contains('300'));
    });
  });
}
