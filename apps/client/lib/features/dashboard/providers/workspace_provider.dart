import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../features/auth/providers/auth_provider.dart';

const _kLastWorkspaceId = 'last_workspace_id';

class Workspace {
  final String id;
  final String name;
  final String? description;
  final int documentCount;
  final DateTime createdAt;

  Workspace({
    required this.id,
    required this.name,
    this.description,
    this.documentCount = 0,
    required this.createdAt,
  });

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      documentCount: json['document_count'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class WorkspaceNotifier extends StateNotifier<AsyncValue<List<Workspace>>> {
  final Ref ref;

  WorkspaceNotifier(this.ref) : super(const AsyncValue.loading()) {
    loadWorkspaces();
  }

  Future<void> loadWorkspaces() async {
    state = const AsyncValue.loading();
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get('/workspaces');
      final list = (resp.data as List)
          .map((j) => Workspace.fromJson(j))
          .toList();
      state = AsyncValue.data(list);
      await _restoreLastWorkspace(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> _restoreLastWorkspace(List<Workspace> list) async {
    if (list.isEmpty) return;
    final current = ref.read(selectedWorkspaceProvider);
    if (current != null) return;

    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_kLastWorkspaceId);
    Workspace target;
    if (savedId != null) {
      target = list.firstWhere((w) => w.id == savedId, orElse: () => list.first);
    } else {
      target = list.first;
    }
    ref.read(selectedWorkspaceProvider.notifier).state = target;
    await prefs.setString(_kLastWorkspaceId, target.id);
  }

  Future<Workspace?> createWorkspace(String name, String? description) async {
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.post('/workspaces', data: {
        'name': name,
        'description': description,
      });
      final ws = Workspace.fromJson(resp.data);
      state = AsyncValue.data([...state.value ?? [], ws]);
      return ws;
    } catch (_) {
      return null;
    }
  }
}

final workspaceProvider =
    StateNotifierProvider<WorkspaceNotifier, AsyncValue<List<Workspace>>>((ref) {
  return WorkspaceNotifier(ref);
});

final selectedWorkspaceProvider = StateProvider<Workspace?>((ref) => null);

Future<void> saveLastWorkspaceId(String id) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kLastWorkspaceId, id);
}
