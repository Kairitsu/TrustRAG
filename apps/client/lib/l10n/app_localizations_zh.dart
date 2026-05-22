// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class SZh extends S {
  SZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'TrustRAG';

  @override
  String get navChat => '对话';

  @override
  String get navDocuments => '资料库';

  @override
  String get navReview => '审核';

  @override
  String get navWorkspaces => '工作区';

  @override
  String get navSearch => '搜索';

  @override
  String get navSettings => '设置';

  @override
  String get selectWorkspaceFirst => '请先选择工作区';

  @override
  String loadFailed(String error) {
    return '加载失败: $error';
  }

  @override
  String get newConversation => '新对话';

  @override
  String get startNewConversation => '开始一段新对话';

  @override
  String get aiChatDescription => '基于你的文档进行 AI 问答';

  @override
  String get noConversations => '暂无对话';

  @override
  String get conversation => '对话';

  @override
  String get today => '今天';

  @override
  String get yesterday => '昨天';

  @override
  String get earlier => '更早';

  @override
  String get inputHint => '输入你的问题...';

  @override
  String get thinking => '思考中...';

  @override
  String get copy => '复制';

  @override
  String get retry => '重试';

  @override
  String get edit => '编辑';

  @override
  String get copied => '已复制';

  @override
  String get editMessage => '编辑消息';

  @override
  String get editMessageHint => '编辑消息内容...';

  @override
  String get cancel => '取消';

  @override
  String get resend => '重新发送';

  @override
  String citationSources(int count) {
    return '引用来源 ($count)';
  }

  @override
  String aiError(String error) {
    return 'AI 错误: $error';
  }

  @override
  String sendFailed(String error) {
    return '发送失败: $error';
  }

  @override
  String get switchWorkspace => '切换工作区';

  @override
  String get documents => '资料库';

  @override
  String get uploadDocument => '上传文档';

  @override
  String get selectItems => '选择';

  @override
  String selectedCount(int count) {
    return '已选 $count 项';
  }

  @override
  String get batchDelete => '批量删除';

  @override
  String batchDeleteConfirm(int count) {
    return '确认删除 $count 个文档？此操作不可恢复。';
  }

  @override
  String get batchDeleteDone => '批量删除完成';

  @override
  String uploadSuccessCount(int count) {
    return '成功上传 $count 个文件';
  }

  @override
  String get delete => '删除';

  @override
  String get noDocuments => '暂无文档';

  @override
  String get desktopUploadHint => '点击\"上传文档\"添加 PDF、TXT、MD 或 HTML 文件';

  @override
  String get serverUploadHint => '点击\"上传文档\"添加 PDF、DOCX 或 TXT 文件';

  @override
  String get desktopFormatTooltip => '桌面模式支持 TXT/MD/HTML/PDF\nDOCX 需要部署服务器模式';

  @override
  String get desktopDocxWarning => '桌面模式暂不支持 DOCX 解析，如需解析这些格式请部署服务器模式';

  @override
  String folderEmpty(String folder) {
    return '文件夹 \"$folder\" 中暂无文档';
  }

  @override
  String chunkCount(int count) {
    return '$count 分块';
  }

  @override
  String get moveToFolder => '移动到文件夹';

  @override
  String get all => '全部';

  @override
  String get newFolder => '新建文件夹';

  @override
  String get folderName => '文件夹名称';

  @override
  String get create => '创建';

  @override
  String get moveToFolderTitle => '移动到文件夹';

  @override
  String currentFolder(String name) {
    return '当前文件夹: $name';
  }

  @override
  String get selectExistingFolder => '选择已有文件夹:';

  @override
  String get noFolder => '无文件夹';

  @override
  String get orEnterNewFolder => '或输入新文件夹:';

  @override
  String get enterFolderName => '输入文件夹名称:';

  @override
  String get newFolderName => '新文件夹名';

  @override
  String get confirm => '确认';

  @override
  String get switchWorkspaceTooltip => '切换工作区/资料库';

  @override
  String get switchLabel => '切换';

  @override
  String get statusReady => '就绪';

  @override
  String get statusProcessing => '解析中';

  @override
  String get statusChunking => '分块中';

  @override
  String get statusEmbedding => '向量化中';

  @override
  String get statusFailed => '失败';

  @override
  String get statusPending => '等待';

  @override
  String get reviewRecords => '审核记录';

  @override
  String get refresh => '刷新';

  @override
  String get noReviews => '暂无审核记录';

  @override
  String get noReviewsDescription => '在对话中审核 AI 引用后，记录将在此处显示';

  @override
  String correction(String text) {
    return '修正';
  }

  @override
  String citationId(String id) {
    return '引用 ID: $id...';
  }

  @override
  String get statusApproved => '通过';

  @override
  String get statusRejected => '拒绝';

  @override
  String get statusFlagged => '存疑';

  @override
  String get statusPendingReview => '待定';

  @override
  String get workspaces => '工作区';

  @override
  String get createNew => '新建';

  @override
  String get noWorkspaces => '还没有工作区';

  @override
  String get createFirstWorkspace => '创建第一个工作区';

  @override
  String get noDescription => '无描述';

  @override
  String get createWorkspace => '新建工作区';

  @override
  String get nameLabel => '名称';

  @override
  String get descriptionLabel => '描述（可选）';

  @override
  String get settings => '设置';

  @override
  String get modelConfig => '模型配置';

  @override
  String get modelConfigSubtitle => '管理 LLM 和 Embedding 模型';

  @override
  String get teamMembers => '团队成员';

  @override
  String get teamMembersSubtitle => '管理工作区的成员和权限';

  @override
  String get accountInfo => '账户信息';

  @override
  String get unknown => '未知';

  @override
  String get appearance => '外观';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get developerMode => '开发者模式';

  @override
  String get devModeOn => '已开启 — 显示调试工具';

  @override
  String get devModeOff => '开启后可查看日志、API 请求等调试信息';

  @override
  String get debugLog => '调试日志';

  @override
  String get debugLogSubtitle => '查看运行时日志和 API 请求记录';

  @override
  String get runtimeEnv => '运行环境';

  @override
  String get envInfoCopied => '环境信息已复制';

  @override
  String get checkUpdate => '检查更新';

  @override
  String currentVersion(String version) {
    return '当前版本 v$version';
  }

  @override
  String get about => '关于';

  @override
  String get alreadyLatest => '已是最新版本';

  @override
  String checkUpdateFailed(String error) {
    return '检查更新失败: $error';
  }

  @override
  String get debugLogTitle => '调试日志';

  @override
  String get clearLog => '清空';

  @override
  String get noLogs => '暂无日志';

  @override
  String get logCopied => '日志已复制到剪贴板';

  @override
  String get copyAll => '复制全部';

  @override
  String get close => '关闭';

  @override
  String get accountInfoTitle => '账户信息';

  @override
  String get username => '用户名';

  @override
  String get email => '邮箱';

  @override
  String get role => '角色';

  @override
  String get aboutTrustRAG => '关于 TrustRAG';

  @override
  String get trustragDescription => 'TrustRAG - 可信赖的 RAG 知识工作台';

  @override
  String get version => '版本';

  @override
  String get backend => '后端';

  @override
  String get frontend => '前端';

  @override
  String get database => '数据库';

  @override
  String get storage => '存储';

  @override
  String get aboutDescription => '基于文档检索增强生成（RAG）技术，提供带引用溯源的可信赖 AI 问答。';

  @override
  String get logout => '退出登录';

  @override
  String get newVersionFound => '发现新版本';

  @override
  String get releaseNotes => '更新内容';

  @override
  String get skipThisVersion => '跳过此版本';

  @override
  String get remindLater => '稍后提醒';

  @override
  String get goToDownload => '前往下载';

  @override
  String cannotOpenLink(String error) {
    return '无法打开链接: $error';
  }

  @override
  String get inviteMember => '邀请成员';

  @override
  String get emailAddress => '邮箱地址';

  @override
  String get roleLabel => '角色';

  @override
  String get viewer => '查看者';

  @override
  String get editor => '编辑者';

  @override
  String get owner => '所有者';

  @override
  String get admin => '管理员';

  @override
  String get invite => '邀请';

  @override
  String invited(String email) {
    return '已邀请 $email';
  }

  @override
  String inviteFailed(String error) {
    return '邀请失败: $error';
  }

  @override
  String get changeRole => '修改角色';

  @override
  String changeRoleTitle(String name) {
    return '修改 $name 的角色';
  }

  @override
  String changeRoleFailed(String error) {
    return '修改失败: $error';
  }

  @override
  String get removeMember => '移除成员';

  @override
  String removeMemberConfirm(String name) {
    return '确认将 $name 从工作区中移除？';
  }

  @override
  String get remove => '移除';

  @override
  String removeFailed(String error) {
    return '移除失败: $error';
  }

  @override
  String get ownerPermission => '完全控制权限，可管理成员和设置';

  @override
  String get editorPermission => '可编辑文档和对话，管理成员';

  @override
  String get viewerPermission => '仅可查看文档和对话';

  @override
  String get memberManagement => '成员管理';

  @override
  String memberManagementWithWs(String name) {
    return '成员管理 — $name';
  }

  @override
  String get noMembers => '暂无成员';

  @override
  String get me => '我';

  @override
  String get language => '语言';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageEn => 'English';

  @override
  String get languageJa => '日本語';

  @override
  String get languageKo => '한국어';

  @override
  String get navKnowledgeGraph => '图谱';

  @override
  String get knowledgeGraph => '知识图谱';

  @override
  String knowledgeGraphDesc(String name) {
    return '「$name」中的实体与关系';
  }

  @override
  String get graphView => '关系图';

  @override
  String get entityList => '实体列表';

  @override
  String get noGraphData => '暂无图谱数据';

  @override
  String get noGraphDataHint => '上传文档并完成解析后，知识图谱将自动生成';

  @override
  String get noEntities => '暂无实体';

  @override
  String get searchEntities => '搜索实体名称或类型...';

  @override
  String get entitiesCount => '个实体';

  @override
  String get typesCount => '种类型';

  @override
  String get entityType => '类型';

  @override
  String get relatedEntities => '关联实体';

  @override
  String get nodes => '节点';

  @override
  String get edges => '关系';

  @override
  String get noReviewRecords => '暂无审核记录';

  @override
  String get reviewRecordsHint => '在对话中审核 AI 引用后，记录将在此处显示';

  @override
  String get exportReport => '导出报告';

  @override
  String get reviewReport => '审核报告';

  @override
  String get generating => '生成中...';

  @override
  String reportGeneratedAt(String time) {
    return '生成时间: $time';
  }

  @override
  String get totalCitations => '总引用数';

  @override
  String get reviewed => '已审核';

  @override
  String get unreviewedCount => '未审核';

  @override
  String get reviewCoverage => '审核覆盖率';

  @override
  String get approvalRate => '通过率';

  @override
  String get rejectionRate => '拒绝率';

  @override
  String get hallucinationRate => '幻觉率';

  @override
  String get keyMetrics => '关键指标';

  @override
  String get reviewResults => '审核结果分布';

  @override
  String get reviewDetails => '审核明细';

  @override
  String get approved => '通过';

  @override
  String get rejected => '拒绝';

  @override
  String get flagged => '存疑';

  @override
  String get pending => '待定';

  @override
  String get document => '文档';

  @override
  String get section => '章节';

  @override
  String get page => '页码';

  @override
  String get quote => '引用';

  @override
  String get copyMarkdown => '复制 Markdown';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get reportLoadFailed => '报告生成失败';

  @override
  String get overview => '概览';

  @override
  String get personalSpace => '个人空间';

  @override
  String get teamSpace => '团队空间';

  @override
  String get createTeam => '创建团队';

  @override
  String get joinTeam => '加入团队';

  @override
  String get teamName => '团队名称';

  @override
  String get teamDescription => '团队描述（可选）';

  @override
  String get inviteCode => '邀请码';

  @override
  String get enterInviteCode => '输入 8 位邀请码';

  @override
  String get joinButton => '加入';

  @override
  String teamCreated(Object name, Object code) {
    return '团队「$name」创建成功！邀请码: $code';
  }

  @override
  String joinedTeam(Object name) {
    return '已加入团队「$name」！';
  }

  @override
  String get joinFailed => '加入失败，请检查邀请码是否正确';

  @override
  String get teamSettings => '团队设置';

  @override
  String manageTeam(Object name) {
    return '管理「$name」团队';
  }

  @override
  String get regenerateInviteCode => '重新生成邀请码';

  @override
  String get regenerateConfirm => '重新生成后，旧邀请码将失效。确认继续？';

  @override
  String newInviteCode(Object code) {
    return '新邀请码: $code';
  }

  @override
  String get copyInviteCode => '复制邀请码';

  @override
  String get inviteCodeCopied => '邀请码已复制';

  @override
  String get shareInvite => '分享邀请';

  @override
  String get shareInviteSubtitle => '将邀请码发送给团队成员';

  @override
  String inviteMessage(Object name, Object code) {
    return '邀请你加入 TrustRAG 团队「$name」\n邀请码: $code';
  }

  @override
  String get inviteInfoCopied => '邀请信息已复制到剪贴板';

  @override
  String get memberManagementSubtitle => '查看和管理团队成员';

  @override
  String get transferOwnership => '转让管理员';

  @override
  String get transferOwnershipDesc => '将团队所有权转让给其他成员';

  @override
  String get goToMemberManagement => '前往成员管理';

  @override
  String get disbandTeam => '解散团队';

  @override
  String get disbandTeamDesc => '永久删除团队及所有数据';

  @override
  String get disbandWarning => '此操作不可撤销！团队中的所有文档、对话和审核记录将被永久删除。';

  @override
  String disbandConfirmPrompt(Object name) {
    return '请输入团队名称「$name」确认：';
  }

  @override
  String get confirmDisband => '确认解散';

  @override
  String get teamNameMismatch => '团队名称不匹配';

  @override
  String get teamDisbanded => '团队已解散';

  @override
  String disbandFailed(Object error) {
    return '解散失败: $error';
  }

  @override
  String get roleOwner => '所有者';

  @override
  String get roleAdmin => '管理员';

  @override
  String get roleEditor => '编辑者';

  @override
  String get roleViewer => '查看者';

  @override
  String get roleOwnerDesc => '完全控制权限，可管理成员、设置和 API 配置';

  @override
  String get roleAdminDesc => '可管理成员、LLM 配置和 API Key';

  @override
  String get roleEditorDesc => '可编辑文档和对话';

  @override
  String get roleViewerDesc => '仅可查看文档和对话，提交审核';

  @override
  String get team => '团队';

  @override
  String get collapseSidebar => '收起侧栏';

  @override
  String get expandSidebar => '展开侧栏';
}
