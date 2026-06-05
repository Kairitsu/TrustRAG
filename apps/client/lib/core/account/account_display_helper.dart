import '../services/local_bootstrap.dart';
import '../services/mode_manager.dart';

/// UI helpers for account display; hides internal embedded-backend identity.
class AccountDisplayHelper {
  AccountDisplayHelper._();

  static bool isInternalLocalAccount(String? email) {
    return email == LocalBootstrap.localAccountId;
  }

  static String sidebarLabel({
    required AppMode mode,
    String? serverEmail,
  }) {
    if (mode == AppMode.local) return '本地模式';
    final email = serverEmail?.trim() ?? '';
    if (email.isEmpty || isInternalLocalAccount(email)) return '未登录';
    return email;
  }

  static String sidebarInitial({
    required AppMode mode,
    String? serverEmail,
  }) {
    if (mode == AppMode.local) return '本';
    final email = serverEmail?.trim() ?? '';
    if (email.isEmpty) return '?';
    return email[0].toUpperCase();
  }

  static String accountInfoEmailLabel({
    required AppMode mode,
    String? serverEmail,
  }) {
    if (mode == AppMode.local) return '本地模式';
    return serverEmail ?? '';
  }
}