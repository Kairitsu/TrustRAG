import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/services/backend_manager.dart';
import '../../../core/services/mode_manager.dart';
import '../../../core/services/session_reset.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? token;
  final Map<String, dynamic>? user;
  final String? error;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.token,
    this.user,
    this.error,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? token,
    Map<String, dynamic>? user,
    String? error,
  }) {
    return AuthState(
      status: status ?? this.status,
      token: token ?? this.token,
      user: user ?? this.user,
      error: error,
    );
  }
}

/// Server-account auth only. Local mode API session is applied via [applyAuthenticatedSession].
class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _api;
  final Ref _ref;

  AuthNotifier(this._api, this._ref) : super(const AuthState()) {
    _checkAuth();
  }

  Future<void> checkAuthStatus() => _checkAuth();

  void clearSessionState() {
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// After local bootstrap: workspace APIs only; UI must not show internal email.
  void applyAuthenticatedSession({
    required String token,
    Map<String, dynamic>? user,
  }) {
    state = AuthState(
      status: AuthStatus.authenticated,
      token: token,
      user: user,
    );
  }

  Future<void> _checkAuth() async {
    final mode = _ref.read(modeProvider).mode;

    if (mode == AppMode.local) {
      if (kIsWeb || !BackendManager.shouldRunEmbedded) {
        state = const AuthState(status: AuthStatus.unauthenticated);
        return;
      }
      final token = await ApiClient.getToken();
      if (token == null) {
        state = const AuthState(status: AuthStatus.unauthenticated);
        return;
      }
      try {
        final resp = await _api.dio.get('/auth/me');
        final user = resp.data is Map<String, dynamic>
            ? resp.data as Map<String, dynamic>
            : null;
        state = AuthState(
          status: AuthStatus.authenticated,
          token: token,
          user: user,
        );
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          await ApiClient.clearToken();
        }
        state = const AuthState(status: AuthStatus.unauthenticated);
      } catch (_) {
        state = AuthState(status: AuthStatus.authenticated, token: token);
      }
      return;
    }

    final token = await ApiClient.getToken();
    if (token != null) {
      try {
        final resp = await _api.dio.get('/auth/me');
        state = AuthState(
          status: AuthStatus.authenticated,
          token: token,
          user: resp.data is Map<String, dynamic>
              ? resp.data as Map<String, dynamic>
              : null,
        );
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          await ApiClient.clearToken();
          state = const AuthState(status: AuthStatus.unauthenticated);
        } else {
          state = AuthState(
            status: AuthStatus.authenticated,
            token: token,
          );
        }
      } catch (_) {
        state = AuthState(
          status: AuthStatus.authenticated,
          token: token,
        );
      }
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> login(String email, String password, {bool rememberLogin = true}) async {
    final backend = BackendManager();
    final mode = _ref.read(modeProvider).mode;

    if (mode == AppMode.local) {
      state = state.copyWith(
        error: '本地模式无需登录',
      );
      return false;
    }

    final normalizedEmail = email.trim().toLowerCase();

    try {
      state = state.copyWith(error: null);
      resetAccountScopedStateFromRef(_ref);

      if (BackendManager.shouldRunEmbedded) {
        final previousAccount = await ApiClient.getActiveAccount();
        final needRestart = previousAccount != normalizedEmail || !backend.isRunning;

        if (needRestart) {
          if (backend.isRunning && previousAccount != normalizedEmail) {
            await backend.restart(accountId: normalizedEmail);
          } else if (!backend.isRunning) {
            await backend.start(accountId: normalizedEmail);
          }
          await backend.ready;
          if (backend.hasFailed) {
            state = state.copyWith(
              status: AuthStatus.unauthenticated,
              error: '本地后端启动失败: ${backend.startupError ?? "未知错误"}',
            );
            return false;
          }
        }
        _api.dio.options.baseUrl = backend.baseUrl;
      }

      final resp = await _api.dio.post('/auth/login', data: {
        'email': normalizedEmail,
        'password': password,
      });
      final token = (resp.data['token'] ?? resp.data['access_token']) as String;

      await ApiClient.setActiveAccount(normalizedEmail);
      await ApiClient.setLastLoginEmail(normalizedEmail);

      if (rememberLogin) {
        await ApiClient.saveToken(token);
      } else {
        await ApiClient.clearToken();
      }

      state = AuthState(
        status: AuthStatus.authenticated,
        token: token,
        user: resp.data['user'] is Map<String, dynamic>
            ? resp.data['user'] as Map<String, dynamic>
            : null,
      );
      invalidateWorkspaceList(_ref);
      return true;
    } on DioException catch (e) {
      String msg;
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        if (BackendManager.shouldRunEmbedded) {
          if (!backend.isRunning) {
            msg = '本地后端未启动，请先启动后端服务';
          } else if (backend.hasFailed) {
            msg = '本地后端启动失败: ${backend.startupError ?? "请查看应用日志"}';
          } else {
            msg = '本地后端健康检查失败 (${backend.baseUrl})，请稍后重试';
          }
        } else {
          msg = '无法连接服务器，请检查网络连接';
        }
      } else {
        msg = (e.response?.data?['error'] ?? '登录失败').toString();
      }
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: msg,
      );
      return false;
    }
  }

  Future<bool> register(String name, String email, String password) async {
    final backend = BackendManager();
    final mode = _ref.read(modeProvider).mode;

    if (mode == AppMode.local) {
      state = state.copyWith(
        error: '本地模式不支持注册服务器账号，请切换为服务器模式',
      );
      return false;
    }

    final normalizedEmail = email.trim().toLowerCase();

    try {
      state = state.copyWith(error: null);
      resetAccountScopedStateFromRef(_ref);

      if (BackendManager.shouldRunEmbedded) {
        final previousAccount = await ApiClient.getActiveAccount();
        final needRestart = previousAccount != normalizedEmail || !backend.isRunning;

        if (needRestart) {
          if (backend.isRunning && previousAccount != normalizedEmail) {
            await backend.restart(accountId: normalizedEmail);
          } else if (!backend.isRunning) {
            await backend.start(accountId: normalizedEmail);
          }
          await backend.ready;
          if (backend.hasFailed) {
            state = state.copyWith(
              error: '本地后端启动失败: ${backend.startupError ?? "未知错误"}',
            );
            return false;
          }
        }
        _api.dio.options.baseUrl = backend.baseUrl;
      }

      final resp = await _api.dio.post('/auth/register', data: {
        'display_name': name,
        'email': normalizedEmail,
        'password': password,
      });
      final token = (resp.data['token'] ?? resp.data['access_token']) as String;

      await ApiClient.setActiveAccount(normalizedEmail);
      await ApiClient.setLastLoginEmail(normalizedEmail);
      await ApiClient.saveToken(token);

      state = AuthState(
        status: AuthStatus.authenticated,
        token: token,
        user: resp.data['user'] is Map<String, dynamic>
            ? resp.data['user'] as Map<String, dynamic>
            : null,
      );
      invalidateWorkspaceList(_ref);
      return true;
    } on DioException catch (e) {
      String msg;
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        if (BackendManager.shouldRunEmbedded) {
          if (!backend.isRunning) {
            msg = '本地后端未启动，请先启动后端服务';
          } else if (backend.hasFailed) {
            msg = '本地后端启动失败: ${backend.startupError ?? "未知错误"}';
          } else {
            msg = '本地后端健康检查失败 (${backend.baseUrl})，请稍后重试';
          }
        } else {
          msg = '无法连接服务器，请检查网络连接';
        }
      } else {
        msg = (e.response?.data?['error'] ?? '注册失败').toString();
      }
      state = state.copyWith(error: msg);
      return false;
    }
  }

  Future<void> logout() async {
    resetAccountScopedStateFromRef(_ref);
    await ApiClient.clearCurrentServerSession();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Returns null on success, or an error message.
  Future<String?> deleteServerAccount({
    required String password,
    required String confirmEmail,
  }) async {
    try {
      await _api.dio.delete(
        '/auth/me',
        data: {
          'password': password,
          'confirm_email': confirmEmail.trim().toLowerCase(),
        },
      );
      final email = await ApiClient.getActiveAccount();
      if (email != null) {
        await ApiClient.removeSavedServerAccount(email);
      }
      await ApiClient.clearCurrentServerSession();
      state = const AuthState(status: AuthStatus.unauthenticated);
      return null;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) {
        return data['error'].toString();
      }
      return (e.response?.data?.toString() ?? e.message ?? '删除账号失败');
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final api = ref.watch(apiClientProvider);
  return AuthNotifier(api, ref);
});