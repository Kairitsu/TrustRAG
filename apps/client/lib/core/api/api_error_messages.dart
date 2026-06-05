import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Maps API/network errors to short, user-facing Chinese messages.
String friendlyApiError(
  Object error, {
  String fallback = '操作失败，请稍后重试',
  String? context,
}) {
  debugPrint('[ApiError]${context != null ? ' ($context)' : ''}: $error');

  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接超时，请检查网络后重试';
      case DioExceptionType.connectionError:
        return '无法连接服务，请确认服务已启动或网络正常';
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode ?? 0;
        final serverMsg = _extractServerMessage(error.response?.data);
        switch (status) {
          case 401:
            return serverMsg ?? '登录已过期，请重新登录';
          case 403:
            return serverMsg ?? '没有权限执行此操作';
          case 404:
            return serverMsg ?? '请求的资源不存在，请重新选择工作区';
          case 409:
            return serverMsg ?? '资源冲突，请刷新后重试';
          case 422:
            return serverMsg ?? '请求参数无效';
          default:
            if (status >= 500) {
              return serverMsg ?? '服务器错误，请稍后重试';
            }
            return serverMsg ?? fallback;
        }
      case DioExceptionType.cancel:
        return '请求已取消';
      default:
        break;
    }
    if (error.message != null && error.message!.isNotEmpty) {
      return error.message!;
    }
  }

  if (error is String && error.isNotEmpty) return error;
  return fallback;
}

String? _extractServerMessage(dynamic data) {
  if (data is Map) {
    for (final key in ['error', 'message', 'detail']) {
      final v = data[key];
      if (v is String && v.isNotEmpty) return v;
    }
  }
  if (data is String && data.isNotEmpty) return data;
  return null;
}