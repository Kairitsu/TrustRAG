import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../../../core/services/backend_manager.dart';
import '../../../core/services/desktop_auto_setup.dart';
import '../../../core/services/local_bootstrap.dart';
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

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _api;
  final Ref _ref;

  AuthNotifier(this._api, this._ref) : super(const AuthState()) {
    _checkAuth();
  }

  Future<void> checkAuthStatus() => _checkAuth();

  Future<void> _checkAuth() async {
    final mode = _ref.read(modeProvider).mode;

    if (mode == AppMode.local &&
        !kIsWeb &&
        BackendManager.shouldRunEmbedded) {
      final existingToken = await ApiClient.getToken();
      if (existingToken != null) {
        try {
          final resp = await _api.dio.get('/auth/me');
          state = AuthState(
            status: AuthStatus.authenticated,
            token: existingToken,
            user: resp.data is Map<String, dynamic>
                ? resp.data as Map<String, dynamic>
                : null,
          );
          return;
        } on DioException catch (e) {
          if (e.response?.statusCode == 401) {
            await ApiClient.clearToken();
          }
        }
      }

      final result = await LocalBootstrap.bootstrap(_api, ref: _ref);
      if (result.isSuccess) {
        return;
      }
      if (DesktopAutoSetup.shouldAutoSetup) {
        await DesktopAutoSetup.ensureLocalIdentity(_api);
      }
    } else if (DesktopAutoSetup.shouldAutoSetup) {
      await DesktopAutoSetup.ensureLocalIdentity(_api);
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
        error: '本地模式无需登录，请使用自动进入',
      );
      return false;
    }

    try {
      state = state.copyWith(error: null);
      resetAccountScopedStateFromRef(_ref);

      if (BackendManager.shouldRunEmbedded) {
        final previousAccount = await ApiClient.getActiveAccount();
        final needRestart = previousAccount != email || !backend.isRunning;

        if (needRestart) {
          if (backend.isRunning && previousAccount != email) {
            await backend.restart(accountId: email);
          } else if (!backend.isRunning) {
            await backend.start(accountId: email);
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
        'email': email,
        'password': password,
      });
      final token = (resp.data['token'] ?? resp.data['access_token']) as String;

      await ApiClient.setActiveAccount(email);

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
      _ref.invalidate(workspaceProvider);
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

    try {
      state = state.copyWith(error: null);
      resetAccountScopedStateFromRef(_ref);

      if (BackendManager.shouldRunEmbedded) {
        final previousAccount = await ApiClient.getActiveAccount();
        final needRestart = previousAccount != email || !backend.isRunning;

        if (needRestart) {
          if (backend.isRunning && previousAccount != email) {
            await backend.restart(accountId: email);
          } else if (!backend.isRunning) {
            await backend.start(accountId: email);
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
        'email': email,
        'password': password,
      });
      final token = (resp.data['token'] ?? resp.data['access_token']) as String;

      await ApiClient.setActiveAccount(email);
      await ApiClient.saveToken(token);

      state = AuthState(
        status: AuthStatus.authenticated,
        token: token,
        user: resp.data['user'] is Map<String, dynamic>
            ? resp.data['user'] as Map<String, dynamic>
            : null,
      );
      _ref.invalidate(workspaceProvider);
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
        msg = (e.response?.data?['error'] ?? '注册失败').toString();
      }
      state = state.copyWith(error: msg);
      return false;
    }
  }

  Future<void> logout({bool clearData = false}) async {
    final mode = _ref.read(modeProvider).mode;
    final email = await ApiClient.getActiveAccount();

    resetAccountScopedStateFromRef(_ref);

    if (clearData) {
      if (email != null) {
        if (BackendManager.shouldRunEmbedded) {
          try {
            await BackendManager().stop();
            await BackendManager().deleteAccountData(
              mode == AppMode.local ? LocalBootstrap.localAccountId : email,
            );
          } catch (e) {
            debugPrint('[Auth] Failed to delete account data: $e');
          }
        }
        await ApiClient.removeAccount(email);
      }
      await ApiClient.clearAllAccountData();
      if (mode == AppMode.local) {
        await LocalBootstrap.resetLocalData();
      }
    } else {
      await ApiClient.clearToken();
      if (mode == AppMode.local) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('active_account_email');
      }
    }
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final api = ref.watch(apiClientProvider);
  return AuthNotifier(api, ref);
});