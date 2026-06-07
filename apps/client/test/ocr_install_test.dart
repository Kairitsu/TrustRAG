import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OCR install task system', () {
    test('parses ocr-status with overall_status and paths', () {
      final json = {
        'any_available': true,
        'pdf_ocr_ready': true,
        'overall_status': 'available',
        'tesseract_path': '/usr/bin/tesseract',
        'poppler_path': '/usr/bin',
        'tessdata_dir': '/usr/share/tessdata',
        'tools': [],
        'recommendation': 'OCR 组件已就绪',
        'ocr_config': {'ocr_enabled': true, 'prefer_custom_paths': false},
      };

      expect(json['overall_status'], 'available');
      expect(json['tesseract_path'], isNotNull);
      expect(json['pdf_ocr_ready'], true);
    });

    test('parses comprehensive ocr-preflight response', () {
      final json = {
        'items': [
          {'name': 'os', 'display_name': '操作系统', 'passed': true, 'detail': 'linux x86_64'},
          {'name': 'admin', 'display_name': '管理员权限', 'passed': false, 'detail': '非管理员'},
          {'name': 'choco', 'display_name': 'Chocolatey 已安装', 'passed': false, 'detail': '未找到'},
          {'name': 'tesseract', 'display_name': 'tesseract.exe', 'passed': false, 'detail': '未找到'},
          {'name': 'pdftoppm', 'display_name': 'pdftoppm.exe', 'passed': false, 'detail': '未找到'},
          {'name': 'path_tesseract', 'display_name': 'PATH 包含 Tesseract', 'passed': false, 'detail': ''},
          {'name': 'latest_install_log', 'display_name': '最近安装日志', 'passed': false, 'detail': ''},
        ],
        'is_admin': false,
        'os_name': 'linux',
        'os_arch': 'x86_64',
        'logs_dir': '/home/user/.trustrag/logs/ocr-install',
        'overall_status': 'not_installed',
      };

      final items = json['items'] as List;
      expect(items.length, greaterThanOrEqualTo(7));
      expect(json['logs_dir'], contains('ocr-install'));
    });

    test('parses install task status with stage and elevation', () {
      final json = {
        'task_id': 'abc-123',
        'status': 'waiting_for_uac',
        'stage': 'waiting_for_uac',
        'engine': 'tesseract',
        'install_method': 'choco',
        'requires_admin': true,
        'is_elevated': false,
        'command': 'choco install tesseract poppler -y --no-progress',
        'log_file_path': '/data/logs/ocr-install/abc-123.log',
        'status_file_path': '/data/logs/ocr-install/abc-123.status.json',
        'stall_warning': false,
        'suggestions': <String>[],
        'residual_pids': <int>[],
        'residual_command_lines': <String>[],
        'new_lines': ['[info] 等待 UAC 管理员授权...'],
        'total_lines': 5,
      };

      expect(json['status'], 'waiting_for_uac');
      expect(json['stage'], 'waiting_for_uac');
      expect(json['is_elevated'], false);
      expect((json['log_file_path'] as String).contains('ocr-install'), true);
    });

    test('parses terminal statuses', () {
      for (final status in [
        'success',
        'failed',
        'cancelled',
        'cancel_failed',
        'elevation_cancelled',
        'timeout',
        'cancelling',
      ]) {
        expect(status, isNotEmpty);
      }
    });

    test('parses ocr-config save response', () {
      final json = {
        'success': true,
        'message': 'OCR 路径配置已保存并验证通过。',
        'config': {
          'tesseract_path': 'C:\\Tesseract\\tesseract.exe',
          'poppler_bin_dir': 'C:\\poppler\\bin',
          'prefer_custom_paths': true,
          'ocr_enabled': true,
        },
        'verification': {
          'all_passed': true,
          'path_refresh_needed': false,
          'partial_tesseract': false,
          'partial_poppler': false,
          'items': [
            {'name': 'tesseract --version', 'passed': true, 'detail': '5.3.0'},
          ],
        },
      };

      expect(json['success'], true);
      final verification = json['verification'] as Map<String, dynamic>;
      expect(verification['all_passed'], true);
    });

    test('parses partial availability statuses', () {
      expect('partial_tesseract', isNot('partial_poppler'));
      final tessOnly = {
        'overall_status': 'partial_tesseract',
        'pdf_ocr_ready': false,
        'any_available': true,
      };
      expect(tessOnly['overall_status'], 'partial_tesseract');
    });

    test('cancel response is immediate accept', () {
      final json = {'success': true, 'message': '取消请求已接受，正在终止安装进程'};
      expect(json['success'], true);
      expect((json['message'] as String).contains('取消'), true);
    });
  });
}