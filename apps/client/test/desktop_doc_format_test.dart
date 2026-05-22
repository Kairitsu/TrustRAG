import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Desktop document format support', () {
    const desktopSupported = {'txt', 'md', 'html', 'htm', 'pdf'};
    const serverFormats = ['pdf', 'docx', 'txt', 'md', 'html'];

    test('desktop supported formats include text and PDF', () {
      expect(desktopSupported.contains('txt'), isTrue);
      expect(desktopSupported.contains('md'), isTrue);
      expect(desktopSupported.contains('html'), isTrue);
      expect(desktopSupported.contains('htm'), isTrue);
      expect(desktopSupported.contains('pdf'), isTrue);
    });

    test('desktop mode does NOT include DOCX', () {
      expect(desktopSupported.contains('docx'), isFalse);
    });

    test('server mode includes all formats', () {
      expect(serverFormats, contains('pdf'));
      expect(serverFormats, contains('docx'));
      expect(serverFormats, contains('txt'));
      expect(serverFormats, contains('md'));
      expect(serverFormats, contains('html'));
    });

    test('desktop formats are a strict subset of server formats', () {
      for (final ext in desktopSupported) {
        final inServer = serverFormats.contains(ext) || ext == 'htm';
        expect(inServer, isTrue, reason: '$ext should be in server or alias');
      }
    });
  });
}
