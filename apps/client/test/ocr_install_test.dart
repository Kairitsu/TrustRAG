import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OCR install options model', () {
    test('parses ocr-status response', () {
      final json = {
        'any_available': true,
        'tools': [
          {'name': 'tesseract', 'available': true, 'version': '5.3.0', 'path': '/usr/bin/tesseract'},
          {'name': 'paddleocr', 'available': false, 'version': null, 'path': null},
        ],
        'recommendation': '已检测到 OCR 工具',
      };

      expect(json['any_available'], true);
      final tools = json['tools'] as List;
      expect(tools.length, 2);
      expect(tools[0]['name'], 'tesseract');
      expect(tools[0]['available'], true);
      expect(tools[0]['version'], '5.3.0');
      expect(tools[1]['available'], false);
    });

    test('parses ocr-install-options response', () {
      final json = {
        'platform': 'linux',
        'available_package_managers': ['apt', 'pip'],
        'methods': [
          {
            'package_manager': 'apt',
            'engine': 'tesseract',
            'command': 'sudo apt install -y tesseract-ocr tesseract-ocr-chi-sim',
            'needs_sudo': true,
            'description': '通过 apt 安装 Tesseract OCR',
          },
          {
            'package_manager': 'pip',
            'engine': 'paddleocr',
            'command': 'pip3 install paddleocr paddlepaddle',
            'needs_sudo': false,
            'description': '通过 pip 安装 PaddleOCR',
          },
        ],
        'recommended': 'tesseract',
      };

      expect(json['platform'], 'linux');
      final managers = json['available_package_managers'] as List;
      expect(managers, contains('apt'));
      expect(managers, contains('pip'));

      final methods = json['methods'] as List;
      expect(methods.length, 2);

      final apt = methods[0] as Map<String, dynamic>;
      expect(apt['engine'], 'tesseract');
      expect(apt['package_manager'], 'apt');
      expect(apt['needs_sudo'], true);
      expect(apt['command'], contains('tesseract-ocr'));

      final pip = methods[1] as Map<String, dynamic>;
      expect(pip['engine'], 'paddleocr');
      expect(pip['needs_sudo'], false);

      expect(json['recommended'], 'tesseract');
    });

    test('parses ocr-install response', () {
      final json = {
        'success': true,
        'engine': 'tesseract',
        'package_manager': 'apt',
        'output': 'Reading package lists...\nDone.',
        'message': 'tesseract 安装成功！',
      };

      expect(json['success'], true);
      expect(json['engine'], 'tesseract');
      expect(json['package_manager'], 'apt');
      expect((json['output'] as String).isNotEmpty, true);
    });

    test('handles empty methods for unsupported platform', () {
      final json = {
        'platform': 'unknown',
        'available_package_managers': <String>[],
        'methods': <Map<String, dynamic>>[],
        'recommended': null,
      };

      expect((json['methods'] as List).isEmpty, true);
      expect(json['recommended'], null);
    });

    test('parses ocr-status with no tools available', () {
      final json = {
        'any_available': false,
        'tools': [
          {'name': 'tesseract', 'available': false, 'version': null, 'path': null},
          {'name': 'paddleocr', 'available': false, 'version': null, 'path': null},
        ],
        'recommendation': '未检测到 OCR 工具。',
      };

      expect(json['any_available'], false);
      final tools = json['tools'] as List;
      expect(tools.every((t) => t['available'] == false), true);
    });

    test('method selection with needs_sudo flag', () {
      final methods = [
        {'engine': 'tesseract', 'package_manager': 'apt', 'needs_sudo': true},
        {'engine': 'tesseract', 'package_manager': 'brew', 'needs_sudo': false},
        {'engine': 'paddleocr', 'package_manager': 'pip', 'needs_sudo': false},
      ];

      final sudoMethods = methods.where((m) => m['needs_sudo'] == true).toList();
      expect(sudoMethods.length, 1);
      expect(sudoMethods[0]['package_manager'], 'apt');

      final nonSudoMethods = methods.where((m) => m['needs_sudo'] == false).toList();
      expect(nonSudoMethods.length, 2);
    });
  });
}
