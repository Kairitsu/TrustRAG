import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart' show MarkdownBody, MarkdownStyleSheet;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_markdown/streaming_markdown.dart' hide MarkdownStyleSheet;

import '../../../core/utils/ai_icon_helper.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/providers/dev_mode_provider.dart';
import '../../dashboard/providers/workspace_provider.dart';
import '../../reader/pages/pdf_viewer_page.dart';
import '../../settings/providers/model_config_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/review_provider.dart';

enum SendMode { enter, ctrlEnter }

final sendModeProvider = StateProvider<SendMode>((ref) => SendMode.enter);

Future<void> _initSendMode(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  final mode = prefs.getString('send_mode') ?? 'enter';
  ref.read(sendModeProvider.notifier).state =
      mode == 'ctrlEnter' ? SendMode.ctrlEnter : SendMode.enter;
}

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  Citation? _selectedCitation;
  bool _isSending = false;
  double _convPanelWidth = 260;
  double _citationPanelWidth = 340;
  static const double _minPanelWidth = 180;
  static const double _maxConvPanelWidth = 400;
  static const double _maxCitationPanelWidth = 500;
  String _streamingContent = '';
  String _streamingPhase = '';
  List<Citation> _streamingCitations = [];
  StreamController<String>? _streamingTextController;
  http.Client? _activeClient;
  Timer? _firstTokenTimer;

  @override
  void initState() {
    super.initState();
    _initSendMode(ref);
    _restorePanelWidths();
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws != null) {
      ref.read(conversationProvider.notifier).loadConversations(ws.id);
    }
  }

  Future<void> _restorePanelWidths() async {
    final prefs = await SharedPreferences.getInstance();
    final cw = prefs.getDouble('conv_panel_width');
    final ciw = prefs.getDouble('citation_panel_width');
    if (cw != null || ciw != null) {
      setState(() {
        if (cw != null) _convPanelWidth = cw.clamp(_minPanelWidth, _maxConvPanelWidth);
        if (ciw != null) _citationPanelWidth = ciw.clamp(_minPanelWidth, _maxCitationPanelWidth);
      });
    }
  }

  Future<void> _savePanelWidths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('conv_panel_width', _convPanelWidth);
    await prefs.setDouble('citation_panel_width', _citationPanelWidth);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _firstTokenTimer?.cancel();
    _activeClient?.close();
    super.dispose();
  }

  void _stopGenerating() {
    _firstTokenTimer?.cancel();
    _firstTokenTimer = null;
    _activeClient?.close();
    _activeClient = null;

    if (_streamingContent.isNotEmpty) {
      final truncatedMsg = ChatMessage(
        id: 'truncated-${DateTime.now().millisecondsSinceEpoch}',
        role: 'assistant',
        content: '$_streamingContent\n\n---\n*回答已中断*',
        citations: List.from(_streamingCitations),
        createdAt: DateTime.now(),
      );
      ref.read(messagesProvider.notifier).state = [
        ...ref.read(messagesProvider),
        truncatedMsg,
      ];
    }

    _streamingTextController?.close();
    _streamingTextController = null;
    if (mounted) {
      setState(() {
        _isSending = false;
        _streamingContent = '';
        _streamingPhase = '';
        _streamingCitations = [];
      });
    }
  }

  Future<void> _sendMessage() async {
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws == null || _controller.text.trim().isEmpty) return;

    var conv = ref.read(selectedConversationProvider);
    if (conv == null) {
      conv = await ref
          .read(conversationProvider.notifier)
          .createConversation(ws.id, _controller.text.trim());
      if (conv == null) return;
      ref.read(selectedConversationProvider.notifier).state = conv;
    }

    final userText = _controller.text.trim();
    _controller.clear();

    final userMsg = ChatMessage(
      id: 'temp-${DateTime.now().millisecondsSinceEpoch}',
      role: 'user',
      content: userText,
      createdAt: DateTime.now(),
    );

    final msgs = ref.read(messagesProvider);
    ref.read(messagesProvider.notifier).state = [...msgs, userMsg];

    _streamingTextController?.close();
    _streamingTextController = StreamController<String>.broadcast();
    setState(() {
      _isSending = true;
      _streamingContent = '';
      _streamingPhase = '正在连接...';
      _streamingCitations = [];
    });

    _scrollToBottom();

    DebugLogBuffer().add('CHAT 发送消息: ${userText.length > 50 ? '${userText.substring(0, 50)}...' : userText}');
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final api = ref.read(apiClientProvider);
      var baseUrl = api.dio.options.baseUrl;
      if (baseUrl.startsWith('/')) {
        baseUrl = Uri.base.origin + baseUrl;
      }

      final request = http.Request(
        'POST',
        Uri.parse(
            '$baseUrl/workspaces/${ws.id}/conversations/${conv.id}/messages'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'text/event-stream';
      request.body = jsonEncode({
        'content': userText,
        'stream': true,
      });

      final client = http.Client();
      _activeClient = client;

      _firstTokenTimer?.cancel();
      _firstTokenTimer = Timer(const Duration(seconds: 30), () {
        if (_isSending && _streamingContent.isEmpty && mounted) {
          setState(() {
            _streamingPhase = '后端响应超时 (30s)，请检查 LLM 配置或重试';
          });
        }
      });

      try {
        final response = await client.send(request);

        if (response.statusCode != 200) {
          final body = await response.stream.transform(utf8.decoder).join();
          throw Exception('HTTP ${response.statusCode}: $body');
        }

        if (mounted) setState(() => _streamingPhase = '正在检索资料库...');

        String assistantId = '';
        String currentEventType = '';

        await for (final chunk
            in response.stream.transform(utf8.decoder)) {
          for (final line in chunk.split('\n')) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) {
              currentEventType = '';
              continue;
            }
            if (trimmed.startsWith('event: ')) {
              currentEventType = trimmed.substring(7).trim();
              continue;
            }
            if (!trimmed.startsWith('data:')) continue;
            final jsonStr = trimmed.substring(5).trim();
            if (jsonStr.isEmpty) continue;

            final eventType = currentEventType;

            if (eventType == 'error') {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('AI 错误: $jsonStr'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 6),
                  ),
                );
              }
              continue;
            }

            try {
              final event = jsonDecode(jsonStr);
              if (eventType == 'message_start') {
                assistantId = event['message_id'] ?? '';
                if (mounted) setState(() => _streamingPhase = '正在生成回答...');
              } else if (eventType == 'citation') {
                setState(() {
                  _streamingCitations.add(Citation.fromJson(event));
                });
              } else if (eventType == 'text_delta') {
                _firstTokenTimer?.cancel();
                _firstTokenTimer = null;
                final delta = event['delta'] ?? event['text'] ?? '';
                setState(() {
                  _streamingContent += delta;
                });
                _streamingTextController?.add(delta);
                _scrollToBottom();
              } else if (eventType == 'suggestions') {
                final questions = (event['questions'] as List?)
                    ?.map((e) => e.toString())
                    .toList() ?? [];
                final msgs = ref.read(messagesProvider);
                if (msgs.isNotEmpty && msgs.last.role == 'assistant') {
                  final updated = msgs.last.copyWith(suggestions: questions);
                  ref.read(messagesProvider.notifier).state = [
                    ...msgs.sublist(0, msgs.length - 1),
                    updated,
                  ];
                }
              } else if (eventType == 'citations_stored') {
                final stored = event['stored'] as List? ?? [];
                setState(() {
                  for (final item in stored) {
                    final idx = item['index'] as int? ?? 0;
                    final citId = item['citation_id']?.toString() ?? '';
                    for (int i = 0; i < _streamingCitations.length; i++) {
                      if (_streamingCitations[i].index == idx && _streamingCitations[i].id.isEmpty) {
                        _streamingCitations[i] = Citation(
                          id: citId,
                          index: _streamingCitations[i].index,
                          chunkId: _streamingCitations[i].chunkId,
                          documentId: _streamingCitations[i].documentId,
                          heading: _streamingCitations[i].heading,
                          page: _streamingCitations[i].page,
                          score: _streamingCitations[i].score,
                          text: _streamingCitations[i].text,
                          embeddingRank: _streamingCitations[i].embeddingRank,
                          rerankScore: _streamingCitations[i].rerankScore,
                        );
                        break;
                      }
                    }
                  }
                });
              } else if (eventType == 'message_end') {
                final fullContent = _streamingContent;
                if (fullContent.isNotEmpty) {
                  final aiMsg = ChatMessage(
                    id: assistantId,
                    role: 'assistant',
                    content: fullContent,
                    citations: List.from(_streamingCitations),
                    createdAt: DateTime.now(),
                  );
                  ref.read(messagesProvider.notifier).state = [
                    ...ref.read(messagesProvider),
                    aiMsg,
                  ];
                }
                _streamingTextController?.close();
                _streamingTextController = null;
                setState(() {
                  _streamingContent = '';
                  _streamingCitations = [];
                });
              }
            } catch (_) {}
          }
        }
      } finally {
        client.close();
      }

      if (_streamingContent.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI 未返回任何内容，请检查 LLM 模型配置和资料库状态'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      DebugLogBuffer().add('ERROR CHAT 发送失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('发送失败: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ));
      }
    } finally {
      _firstTokenTimer?.cancel();
      _firstTokenTimer = null;
      _activeClient = null;
      DebugLogBuffer().add('CHAT 流式响应结束，引用数: ${_streamingCitations.length}');
      if (mounted) {
        setState(() {
          _isSending = false;
          _streamingPhase = '';
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _selectConversation(Conversation conv) async {
    ref.read(selectedConversationProvider.notifier).state = conv;
    if (_isCompact && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get(
          '/workspaces/${conv.workspaceId}/conversations/${conv.id}/messages');
      final list =
          (resp.data as List).map((j) => ChatMessage.fromJson(j)).toList();
      ref.read(messagesProvider.notifier).state = list;
    } catch (_) {}
  }

  bool get _isCompact => MediaQuery.of(context).size.width < 600;

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(selectedWorkspaceProvider);
    final convs = ref.watch(conversationProvider);
    final messages = ref.watch(messagesProvider);
    final selectedConv = ref.watch(selectedConversationProvider);

    if (ws == null) {
      return Center(
        child:
            Text('请先选择工作区', style: TextStyle(color: Colors.grey.shade500)),
      );
    }

    final conversationPanel = _buildConversationPanel(convs, ws, selectedConv);
    final chatPanel = Column(
      children: [
        if (!_isCompact) _buildWorkspaceBar(ws),
        Expanded(
          child: messages.isEmpty && !_isSending && _streamingContent.isEmpty
              ? _buildEmptyChat()
              : _buildMessageList(messages),
        ),
        _buildInputBar(),
      ],
    );

    if (_isCompact) {
      return Scaffold(
        key: _scaffoldKey,
        drawer: Drawer(
          child: SafeArea(child: conversationPanel),
        ),
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          title: Text(
            selectedConv?.title ?? ws.name,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          titleSpacing: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.add, size: 22),
              tooltip: '新对话',
              onPressed: () {
                ref.read(selectedConversationProvider.notifier).state = null;
                ref.read(messagesProvider.notifier).state = [];
              },
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: chatPanel,
        ),
      );
    }

    return Row(
      children: [
        SizedBox(width: _convPanelWidth, child: conversationPanel),
        _ResizeHandle(
          onDrag: (dx) => setState(() {
            _convPanelWidth = (_convPanelWidth + dx)
                .clamp(_minPanelWidth, _maxConvPanelWidth);
          }),
          onDragEnd: _savePanelWidths,
        ),
        Expanded(child: chatPanel),
        if (_selectedCitation != null) ...[
          _ResizeHandle(
            onDrag: (dx) => setState(() {
              _citationPanelWidth = (_citationPanelWidth - dx)
                  .clamp(_minPanelWidth, _maxCitationPanelWidth);
            }),
            onDragEnd: _savePanelWidths,
          ),
          SizedBox(
            width: _citationPanelWidth,
            child: _CitationPanel(
              citation: _selectedCitation!,
              parentRef: ref,
              onClose: () => setState(() => _selectedCitation = null),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildConversationPanel(
    AsyncValue<List<Conversation>> convs,
    dynamic ws,
    Conversation? selectedConv,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                ref.read(selectedConversationProvider.notifier).state = null;
                ref.read(messagesProvider.notifier).state = [];
                if (_isCompact) Navigator.of(context).pop();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新对话'),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: convs.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (list) {
              if (list.isEmpty) {
                return Center(
                  child: Text('暂无对话',
                      style: TextStyle(color: Colors.grey.shade500)),
                );
              }
              return _buildGroupedConversationList(list, ws, selectedConv);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceBar(dynamic ws) {
    final workspaces = ref.watch(workspaceProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.outline, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.workspaces_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            ws.name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 4),
          workspaces.when(
            data: (list) {
              if (list.length <= 1) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                tooltip: '切换工作区',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.unfold_more, size: 16, color: Colors.grey.shade600),
                onSelected: (id) {
                  final target = list.firstWhere((w) => w.id == id);
                  ref.read(selectedWorkspaceProvider.notifier).state = target;
                  saveLastWorkspaceId(target.id);
                  ref.read(conversationProvider.notifier).loadConversations(target.id);
                  ref.read(selectedConversationProvider.notifier).state = null;
                  ref.read(messagesProvider.notifier).state = [];
                },
                itemBuilder: (_) => list
                    .map((w) => PopupMenuItem<String>(
                          value: w.id,
                          child: Row(
                            children: [
                              Icon(
                                w.id == ws.id ? Icons.check_circle : Icons.circle_outlined,
                                size: 16,
                                color: w.id == ws.id
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Text(w.name),
                            ],
                          ),
                        ))
                    .toList(),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const Spacer(),
          if (ws.description != null && ws.description!.isNotEmpty)
            Text(
              ws.description!,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _buildGroupedConversationList(
      List<Conversation> list, dynamic ws, Conversation? selectedConv) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final todayList = <Conversation>[];
    final yesterdayList = <Conversation>[];
    final earlierList = <Conversation>[];

    for (final conv in list) {
      final d = DateTime(conv.updatedAt.year, conv.updatedAt.month, conv.updatedAt.day);
      if (d.isAtSameMomentAs(today) || d.isAfter(today)) {
        todayList.add(conv);
      } else if (d.isAtSameMomentAs(yesterday)) {
        yesterdayList.add(conv);
      } else {
        earlierList.add(conv);
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        if (todayList.isNotEmpty) ...[
          _buildGroupHeader('今天'),
          ...todayList.map((c) => _buildConvTile(c, ws, selectedConv)),
        ],
        if (yesterdayList.isNotEmpty) ...[
          _buildGroupHeader('昨天'),
          ...yesterdayList.map((c) => _buildConvTile(c, ws, selectedConv)),
        ],
        if (earlierList.isNotEmpty) ...[
          _buildGroupHeader('更早'),
          ...earlierList.map((c) => _buildConvTile(c, ws, selectedConv)),
        ],
      ],
    );
  }

  Widget _buildGroupHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildConvTile(Conversation conv, dynamic ws, Conversation? selectedConv) {
    final isSelected = selectedConv?.id == conv.id;
    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: Theme.of(context)
          .colorScheme
          .primaryContainer
          .withValues(alpha: 0.3),
      leading: const Icon(Icons.chat_bubble_outline, size: 16),
      title: Text(
        conv.title ?? '对话',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      onTap: () => _selectConversation(conv),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 14),
        onPressed: () {
          ref.read(conversationProvider.notifier).deleteConversation(ws.id, conv.id);
          if (selectedConv?.id == conv.id) {
            ref.read(selectedConversationProvider.notifier).state = null;
            ref.read(messagesProvider.notifier).state = [];
          }
        },
      ),
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('开始一段新对话',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: Colors.grey)),
          const SizedBox(height: 8),
          Text('基于你的文档进行 AI 问答',
              style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildMessageList(List<ChatMessage> messages) {
    final hPad = _isCompact ? 12.0 : 24.0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
          itemCount: messages.length + (_isSending || _streamingContent.isNotEmpty ? 1 : 0),
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          itemBuilder: (context, i) {
            if (i < messages.length) {
              return RepaintBoundary(
                key: ValueKey(messages[i].id),
                child: _buildMessageBubble(messages[i]),
              );
            }
            return _buildStreamingBubble();
          },
        ),
      ),
    );
  }

  static String _injectCitationLinks(String content, Set<int> validIndices) {
    return content.replaceAllMapped(
      RegExp(r'\[(\d+)\]'),
      (m) {
        final num = int.tryParse(m.group(1)!);
        if (num == null || !validIndices.contains(num)) return m.group(0)!;
        return '[**\u2060[$num]**](#cite-$num)';
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isUser = msg.role == 'user';
    final theme = Theme.of(context);

    if (isUser) {
      final maxBubbleWidth = _isCompact ? 280.0 : 560.0;
      return Align(
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(msg.content, style: theme.textTheme.bodyLarge),
            ),
            _buildMessageActions(msg, isUser: true),
          ],
        ),
      );
    }

    final modelLabel = _resolveModelLabel(msg);
    final processedContent = msg.citations.isNotEmpty
        ? _injectCitationLinks(
            msg.content,
            msg.citations.map((c) => c.index).toSet(),
          )
        : msg.content;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: AIIconHelper.buildIcon(modelLabel, size: 22,
                color: theme.colorScheme.onSurface),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarkdownBody(
                  data: processedContent,
                  selectable: true,
                  onTapLink: (text, href, title) {
                    if (href != null && href.startsWith('#cite-')) {
                      final idx = int.tryParse(href.substring(6));
                      if (idx != null) {
                        final match = msg.citations.where((c) => c.index == idx);
                        if (match.isNotEmpty) {
                          _showCitationDetail(match.first);
                        }
                      }
                    }
                  },
                  styleSheet: MarkdownStyleSheet(
                    p: theme.textTheme.bodyLarge,
                    h1: theme.textTheme.headlineMedium,
                    h2: theme.textTheme.titleLarge,
                    code: GoogleFonts.jetBrainsMono(fontSize: 14, height: 1.5),
                    a: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      decoration: TextDecoration.none,
                      backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                    ),
                    codeblockDecoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                  ),
                ),
                _buildMessageActions(msg, isUser: false),
                if (msg.citations.isNotEmpty) _buildCollapsibleCitations(msg.citations),
                if (msg.suggestions.isNotEmpty) _buildSuggestionPills(msg.suggestions),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _resolveModelLabel(ChatMessage msg) {
    if (msg.modelName != null && msg.modelName!.isNotEmpty) {
      return msg.modelName!;
    }
    final configs = ref.read(modelConfigProvider);
    final list = configs.valueOrNull ?? [];
    final defaultCfg = list.where((c) => c.isDefault).firstOrNull;
    if (defaultCfg != null) return defaultCfg.modelName;
    if (list.isNotEmpty) return list.first.modelName;
    return 'AI';
  }

  Widget _buildMessageActions(ChatMessage msg, {required bool isUser}) {
    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    const iconSize = 16.0;
    const btnPadding = EdgeInsets.all(6);

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _actionBtn(Icons.copy_rounded, '复制', iconColor, iconSize, btnPadding, () {
            Clipboard.setData(ClipboardData(text: msg.content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
            );
          }),
          if (!isUser) ...[
            const SizedBox(width: 2),
            _actionBtn(Icons.refresh_rounded, '重试', iconColor, iconSize, btnPadding, () {
              _retryMessage(msg);
            }),
          ],
          const SizedBox(width: 2),
          _actionBtn(Icons.edit_rounded, '编辑', iconColor, iconSize, btnPadding, () {
            _editMessage(msg);
          }),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String tooltip, Color color, double size,
      EdgeInsets padding, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }

  void _retryMessage(ChatMessage msg) {
    final msgs = ref.read(messagesProvider);
    final idx = msgs.indexWhere((m) => m.id == msg.id);
    if (idx <= 0) return;
    final userMsg = msgs[idx - 1];
    if (userMsg.role != 'user') return;
    ref.read(messagesProvider.notifier).state = msgs.sublist(0, idx);
    _controller.text = userMsg.content;
    _sendMessage();
  }

  void _editMessage(ChatMessage msg) {
    final editController = TextEditingController(text: msg.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑消息'),
        content: TextField(
          controller: editController,
          maxLines: 8,
          minLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '编辑消息内容...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          if (msg.role == 'user')
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                final msgs = ref.read(messagesProvider);
                final idx = msgs.indexWhere((m) => m.id == msg.id);
                if (idx < 0) return;
                ref.read(messagesProvider.notifier).state = msgs.sublist(0, idx);
                _controller.text = editController.text;
                _sendMessage();
              },
              child: const Text('重新发送'),
            )
          else
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: editController.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制编辑内容'), duration: Duration(seconds: 1)),
                );
              },
              child: const Text('复制'),
            ),
        ],
      ),
    );
  }

  Widget _buildSuggestionPills(List<String> suggestions) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: suggestions.map((q) {
          return ActionChip(
            label: Text(q, style: const TextStyle(fontSize: 13)),
            avatar: Icon(Icons.arrow_forward_ios,
                size: 12, color: Theme.of(context).colorScheme.primary),
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            side: BorderSide(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            ),
            onPressed: () {
              _controller.text = q;
              _sendMessage();
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCollapsibleCitations(List<Citation> citations) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.only(left: 4, right: 4),
          childrenPadding: const EdgeInsets.only(left: 4, bottom: 8),
          initiallyExpanded: false,
          dense: true,
          title: Text(
            S.of(context).citationSources(citations.length),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: citations.map((c) => _buildCitationChip(c)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCitationChip(Citation citation) {
    final scorePercent = (citation.score * 100).toStringAsFixed(0);
    final previewText = citation.text.length > 80
        ? '${citation.text.substring(0, 80)}...'
        : citation.text;
    return Tooltip(
      message: previewText,
      preferBelow: true,
      verticalOffset: 12,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showCitationDetail(citation),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${citation.index}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (citation.heading != null && citation.heading!.isNotEmpty)
                      Text(
                        citation.heading!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    Row(
                      children: [
                        if (citation.page != null)
                          Text(
                            'p.${citation.page}',
                            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        if (citation.page != null) const SizedBox(width: 6),
                        Text(
                          '$scorePercent%',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCitationDetail(Citation citation) {
    if (_isCompact) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollCtrl) => _CitationPanel(
            citation: citation,
            parentRef: ref,
            scrollController: scrollCtrl,
            onClose: () => Navigator.pop(ctx),
          ),
        ),
      );
    } else {
      setState(() => _selectedCitation = citation);
    }
  }

  Widget _buildStreamingBubble() {
    final modelLabel = _resolveModelLabel(ChatMessage(
      id: '',
      role: 'assistant',
      content: '',
      createdAt: DateTime.now(),
    ));
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 10),
            child: AIIconHelper.buildIcon(modelLabel, size: 22,
                color: Theme.of(context).colorScheme.onSurface),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_streamingContent.isEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _streamingPhase.isNotEmpty ? _streamingPhase : '思考中...',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  )
                else if (_streamingTextController != null)
                  AnimatedMarkdown(
                    stream: _streamingTextController!.stream,
                    config: const AnimationConfig(
                      mode: AnimationMode.token,
                      chunkSize: 3,
                    ),
                    selectable: true,
                  )
                else
                  MarkdownBody(
                    data: _streamingContent,
                    selectable: true,
                  ),
                if (_streamingCitations.isNotEmpty)
                  _buildCollapsibleCitations(_streamingCitations),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSendMode() async {
    final current = ref.read(sendModeProvider);
    final next = current == SendMode.enter ? SendMode.ctrlEnter : SendMode.enter;
    ref.read(sendModeProvider.notifier).state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'send_mode', next == SendMode.ctrlEnter ? 'ctrlEnter' : 'enter');
  }

  Widget _buildInputBar() {
    final sendMode = ref.watch(sendModeProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(
                color: Theme.of(context).colorScheme.outline, width: 1)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Focus(
                      onKeyEvent: (node, event) {
                        if (event is! KeyDownEvent) return KeyEventResult.ignored;
                        final isEnter = event.logicalKey == LogicalKeyboardKey.enter;
                        if (!isEnter) return KeyEventResult.ignored;

                        final keyboard = HardwareKeyboard.instance;
                        if (sendMode == SendMode.enter) {
                          if (keyboard.isShiftPressed) return KeyEventResult.ignored;
                          if (!_isSending) {
                            _sendMessage();
                          }
                          return KeyEventResult.handled;
                        } else {
                          if (keyboard.isControlPressed || keyboard.isMetaPressed) {
                            if (!_isSending) {
                              _sendMessage();
                            }
                            return KeyEventResult.handled;
                          }
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: '输入你的问题...',
                            filled: true,
                            fillColor:
                                Theme.of(context).colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                        ),
                      ),
                  ),
                  const SizedBox(width: 8),
                  if (_isSending)
                    IconButton.filled(
                      onPressed: _stopGenerating,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.shade400,
                      ),
                      icon: const Icon(Icons.stop_rounded, color: Colors.white),
                      tooltip: '停止生成',
                    )
                  else
                    IconButton.filled(
                      onPressed: _sendMessage,
                      icon: const Icon(Icons.send),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  InkWell(
                    onTap: _toggleSendMode,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        sendMode == SendMode.enter
                            ? 'Enter 发送'
                            : 'Ctrl+Enter 发送',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.swap_horiz, size: 12, color: Colors.grey.shade400),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CitationDetailDialog extends ConsumerStatefulWidget {
  final Citation citation;
  final WidgetRef parentRef;

  const _CitationDetailDialog({
    required this.citation,
    required this.parentRef,
  });

  @override
  ConsumerState<_CitationDetailDialog> createState() =>
      _CitationDetailDialogState();
}

class _CitationDetailDialogState
    extends ConsumerState<_CitationDetailDialog> {
  List<ReviewRecord>? _reviews;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final svc = ref.read(reviewServiceProvider);
      final citId = widget.citation.id;
      if (citId.isEmpty) {
        if (mounted) setState(() { _reviews = []; _loading = false; });
        return;
      }
      final reviews = await svc.listReviews(citId);
      if (mounted) setState(() { _reviews = reviews; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _reviews = []; _loading = false; });
    }
  }

  Future<void> _submitReview(String status, {String? comment}) async {
    if (widget.citation.id.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('引用ID未就绪，请稍后重试')),
        );
      }
      return;
    }
    setState(() => _submitting = true);
    try {
      final svc = ref.read(reviewServiceProvider);
      await svc.createReview(widget.citation.id, status: status, comment: comment);
      await _loadReviews();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('审核提交失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showReviewCommentDialog(String status) {
    final commentCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(status == 'rejected' ? '标记为错误' : '标记为存疑'),
        content: TextField(
          controller: commentCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '备注（可选）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _submitReview(status,
                  comment: commentCtrl.text.isEmpty
                      ? null
                      : commentCtrl.text);
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'flagged':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return '已通过';
      case 'rejected':
        return '已拒绝';
      case 'flagged':
        return '存疑';
      case 'pending':
        return '待审核';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.citation;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${c.index}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              c.heading ?? '引用 ${c.index}',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c.page != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.description_outlined,
                        size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('第 ${c.page} 页',
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
                    const Spacer(),
                    Text(
                        '相关度: ${(c.score * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        )),
                  ],
                ),
              ),
            const Divider(),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Text(
                  c.text,
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('审核操作',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                _ReviewActionButton(
                  icon: Icons.check_circle_outline,
                  label: '通过',
                  color: Colors.green,
                  loading: _submitting,
                  onTap: () => _submitReview('approved'),
                ),
                const SizedBox(width: 8),
                _ReviewActionButton(
                  icon: Icons.cancel_outlined,
                  label: '错误',
                  color: Colors.red,
                  loading: _submitting,
                  onTap: () => _showReviewCommentDialog('rejected'),
                ),
                const SizedBox(width: 8),
                _ReviewActionButton(
                  icon: Icons.flag_outlined,
                  label: '存疑',
                  color: Colors.orange,
                  loading: _submitting,
                  onTap: () => _showReviewCommentDialog('flagged'),
                ),
              ],
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (_reviews != null && _reviews!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('审核记录',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _reviews!.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = _reviews![i];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        r.status == 'approved'
                            ? Icons.check_circle
                            : r.status == 'rejected'
                                ? Icons.cancel
                                : Icons.flag,
                        color: _statusColor(r.status),
                        size: 18,
                      ),
                      title: Text(_statusLabel(r.status),
                          style: const TextStyle(fontSize: 13)),
                      subtitle: r.comment != null
                          ? Text(r.comment!,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis)
                          : null,
                      trailing: Text(
                        r.createdAt.length >= 16
                            ? r.createdAt.substring(0, 16).replaceFirst('T', ' ')
                            : r.createdAt,
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (c.page != null)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              final ws = widget.parentRef.read(selectedWorkspaceProvider);
              if (ws != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PdfViewerPage(
                      workspaceId: ws.id,
                      documentId: c.documentId,
                      title: c.heading ?? S.of(context).citationSource,
                      initialPage: c.page,
                      highlightText: c.text.length > 50
                          ? c.text.substring(0, 50)
                          : c.text,
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('查看原文'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;
  const _ResizeHandle({required this.onDrag, this.onDragEnd});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      onHorizontalDragEnd: (_) => onDragEnd?.call(),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: SizedBox(
          width: 6,
          child: Center(
            child: Container(
              width: 1,
              color: Theme.of(context).dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _CitationPanel extends ConsumerStatefulWidget {
  final Citation citation;
  final WidgetRef parentRef;
  final VoidCallback onClose;
  final ScrollController? scrollController;

  const _CitationPanel({
    required this.citation,
    required this.parentRef,
    required this.onClose,
    this.scrollController,
  });

  @override
  ConsumerState<_CitationPanel> createState() => _CitationPanelState();
}

class _CitationPanelState extends ConsumerState<_CitationPanel> {
  List<ReviewRecord>? _reviews;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  @override
  void didUpdateWidget(covariant _CitationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.citation.id != widget.citation.id) {
      _loadReviews();
    }
  }

  Future<void> _loadReviews() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final svc = ref.read(reviewServiceProvider);
      final citId = widget.citation.id;
      if (citId.isEmpty) {
        if (mounted) setState(() { _reviews = []; _loading = false; });
        return;
      }
      final reviews = await svc.listReviews(citId);
      if (mounted) setState(() { _reviews = reviews; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _reviews = []; _loading = false; });
    }
  }

  Future<void> _submitReview(String status, {String? comment}) async {
    if (widget.citation.id.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final svc = ref.read(reviewServiceProvider);
      await svc.createReview(widget.citation.id, status: status, comment: comment);
      await _loadReviews();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('审核提交失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showReviewCommentDialog(String status) {
    final commentCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(status == 'rejected' ? '标记为错误' : '标记为存疑'),
        content: TextField(
          controller: commentCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '备注（可选）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _submitReview(status,
                  comment: commentCtrl.text.isEmpty ? null : commentCtrl.text);
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved': return Colors.green;
      case 'rejected': return Colors.red;
      case 'flagged': return Colors.orange;
      default: return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved': return '已通过';
      case 'rejected': return '已拒绝';
      case 'flagged': return '存疑';
      case 'pending': return '待审核';
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.citation;
    final theme = Theme.of(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outline, width: 1),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${c.index}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimary)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(c.heading ?? '引用 ${c.index}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: widget.onClose,
                tooltip: '关闭',
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(12),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (c.page != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.description_outlined,
                              size: 16, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text('第 ${c.page} 页',
                              style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
                        ],
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.score, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                            '相关度: ${(c.score * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            )),
                      ],
                    ),
                    if (c.embeddingRank != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.format_list_numbered, size: 16, color: Colors.teal.shade400),
                          const SizedBox(width: 4),
                          Text('向量排名: #${c.embeddingRank}',
                              style: TextStyle(color: Colors.teal.shade600, fontSize: 13)),
                        ],
                      ),
                    if (c.rerankScore != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_vert, size: 16, color: Colors.deepPurple.shade300),
                          const SizedBox(width: 4),
                          Text('重排分: ${(c.rerankScore! * 100).toStringAsFixed(1)}%',
                              style: TextStyle(color: Colors.deepPurple.shade500, fontSize: 13)),
                        ],
                      ),
                  ],
                ),
              ),
              const Divider(),
              const SizedBox(height: 8),
              Text(c.text, style: const TextStyle(fontSize: 14, height: 1.6)),
              const SizedBox(height: 16),
              Text('审核操作',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _ReviewActionButton(
                    icon: Icons.check_circle_outline,
                    label: '通过',
                    color: Colors.green,
                    loading: _submitting,
                    onTap: () => _submitReview('approved'),
                  ),
                  const SizedBox(width: 8),
                  _ReviewActionButton(
                    icon: Icons.cancel_outlined,
                    label: '错误',
                    color: Colors.red,
                    loading: _submitting,
                    onTap: () => _showReviewCommentDialog('rejected'),
                  ),
                  const SizedBox(width: 8),
                  _ReviewActionButton(
                    icon: Icons.flag_outlined,
                    label: '存疑',
                    color: Colors.orange,
                    loading: _submitting,
                    onTap: () => _showReviewCommentDialog('flagged'),
                  ),
                ],
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))),
                )
              else if (_reviews != null && _reviews!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('审核记录',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                ...(_reviews!.map((r) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        r.status == 'approved'
                            ? Icons.check_circle
                            : r.status == 'rejected'
                                ? Icons.cancel
                                : Icons.flag,
                        color: _statusColor(r.status),
                        size: 18,
                      ),
                      title: Text(_statusLabel(r.status),
                          style: const TextStyle(fontSize: 13)),
                      subtitle: r.comment != null
                          ? Text(r.comment!,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis)
                          : null,
                      trailing: Text(
                        r.createdAt.length >= 16
                            ? r.createdAt
                                .substring(0, 16)
                                .replaceFirst('T', ' ')
                            : r.createdAt,
                        style: TextStyle(
                            fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ))),
              ],
              if (c.page != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    final ws = widget.parentRef.read(selectedWorkspaceProvider);
                    if (ws != null) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PdfViewerPage(
                            workspaceId: ws.id,
                            documentId: c.documentId,
                            title: c.heading ?? S.of(context).citationSource,
                            initialPage: c.page,
                            highlightText: c.text.length > 50
                                ? c.text.substring(0, 50)
                                : c.text,
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('查看原文'),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    return content;
  }
}

class _ReviewActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  const _ReviewActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: loading ? null : onTap,
      icon: Icon(icon, size: 16, color: loading ? Colors.grey : color),
      label: Text(label,
          style: TextStyle(
              color: loading ? Colors.grey : color, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
    );
  }
}
