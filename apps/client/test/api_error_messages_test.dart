import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:client/core/api/api_error_messages.dart';

void main() {
  group('friendlyApiError', () {
    test('maps 404 to user-friendly message', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/workspaces/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/workspaces/x'),
          statusCode: 404,
        ),
        type: DioExceptionType.badResponse,
      );
      expect(
        friendlyApiError(err),
        contains('不存在'),
      );
    });

    test('maps connection error', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/health'),
        type: DioExceptionType.connectionError,
      );
      expect(
        friendlyApiError(err),
        contains('无法连接'),
      );
    });
  });
}