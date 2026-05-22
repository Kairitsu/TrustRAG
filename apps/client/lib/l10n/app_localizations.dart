import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of S
/// returned by `S.of(context)`.
///
/// Applications need to include `S.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: S.localizationsDelegates,
///   supportedLocales: S.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the S.supportedLocales
/// property.
abstract class S {
  S(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static S of(BuildContext context) {
    return Localizations.of<S>(context, S)!;
  }

  static const LocalizationsDelegate<S> delegate = _SDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'TrustRAG'**
  String get appTitle;

  /// No description provided for @navChat.
  ///
  /// In zh, this message translates to:
  /// **'对话'**
  String get navChat;

  /// No description provided for @navDocuments.
  ///
  /// In zh, this message translates to:
  /// **'资料库'**
  String get navDocuments;

  /// No description provided for @navReview.
  ///
  /// In zh, this message translates to:
  /// **'审核'**
  String get navReview;

  /// No description provided for @navWorkspaces.
  ///
  /// In zh, this message translates to:
  /// **'工作区'**
  String get navWorkspaces;

  /// No description provided for @navSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get navSearch;

  /// No description provided for @navSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get navSettings;

  /// No description provided for @selectWorkspaceFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先选择工作区'**
  String get selectWorkspaceFirst;

  /// No description provided for @loadFailed.
  ///
  /// In zh, this message translates to:
  /// **'加载失败: {error}'**
  String loadFailed(String error);

  /// No description provided for @newConversation.
  ///
  /// In zh, this message translates to:
  /// **'新对话'**
  String get newConversation;

  /// No description provided for @startNewConversation.
  ///
  /// In zh, this message translates to:
  /// **'开始一段新对话'**
  String get startNewConversation;

  /// No description provided for @aiChatDescription.
  ///
  /// In zh, this message translates to:
  /// **'基于你的文档进行 AI 问答'**
  String get aiChatDescription;

  /// No description provided for @noConversations.
  ///
  /// In zh, this message translates to:
  /// **'暂无对话'**
  String get noConversations;

  /// No description provided for @conversation.
  ///
  /// In zh, this message translates to:
  /// **'对话'**
  String get conversation;

  /// No description provided for @today.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In zh, this message translates to:
  /// **'昨天'**
  String get yesterday;

  /// No description provided for @earlier.
  ///
  /// In zh, this message translates to:
  /// **'更早'**
  String get earlier;

  /// No description provided for @inputHint.
  ///
  /// In zh, this message translates to:
  /// **'输入你的问题...'**
  String get inputHint;

  /// No description provided for @thinking.
  ///
  /// In zh, this message translates to:
  /// **'思考中...'**
  String get thinking;

  /// No description provided for @copy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get copy;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get edit;

  /// No description provided for @copied.
  ///
  /// In zh, this message translates to:
  /// **'已复制'**
  String get copied;

  /// No description provided for @editMessage.
  ///
  /// In zh, this message translates to:
  /// **'编辑消息'**
  String get editMessage;

  /// No description provided for @editMessageHint.
  ///
  /// In zh, this message translates to:
  /// **'编辑消息内容...'**
  String get editMessageHint;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @resend.
  ///
  /// In zh, this message translates to:
  /// **'重新发送'**
  String get resend;

  /// No description provided for @citationSources.
  ///
  /// In zh, this message translates to:
  /// **'引用来源 ({count})'**
  String citationSources(int count);

  /// No description provided for @aiError.
  ///
  /// In zh, this message translates to:
  /// **'AI 错误: {error}'**
  String aiError(String error);

  /// No description provided for @sendFailed.
  ///
  /// In zh, this message translates to:
  /// **'发送失败: {error}'**
  String sendFailed(String error);

  /// No description provided for @switchWorkspace.
  ///
  /// In zh, this message translates to:
  /// **'切换工作区'**
  String get switchWorkspace;

  /// No description provided for @documents.
  ///
  /// In zh, this message translates to:
  /// **'资料库'**
  String get documents;

  /// No description provided for @uploadDocument.
  ///
  /// In zh, this message translates to:
  /// **'上传文档'**
  String get uploadDocument;

  /// No description provided for @selectItems.
  ///
  /// In zh, this message translates to:
  /// **'选择'**
  String get selectItems;

  /// No description provided for @selectedCount.
  ///
  /// In zh, this message translates to:
  /// **'已选 {count} 项'**
  String selectedCount(int count);

  /// No description provided for @batchDelete.
  ///
  /// In zh, this message translates to:
  /// **'批量删除'**
  String get batchDelete;

  /// No description provided for @batchDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认删除 {count} 个文档？此操作不可恢复。'**
  String batchDeleteConfirm(int count);

  /// No description provided for @batchDeleteDone.
  ///
  /// In zh, this message translates to:
  /// **'批量删除完成'**
  String get batchDeleteDone;

  /// No description provided for @uploadSuccessCount.
  ///
  /// In zh, this message translates to:
  /// **'成功上传 {count} 个文件'**
  String uploadSuccessCount(int count);

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @noDocuments.
  ///
  /// In zh, this message translates to:
  /// **'暂无文档'**
  String get noDocuments;

  /// No description provided for @desktopUploadHint.
  ///
  /// In zh, this message translates to:
  /// **'点击\"上传文档\"添加 PDF、TXT、MD 或 HTML 文件'**
  String get desktopUploadHint;

  /// No description provided for @serverUploadHint.
  ///
  /// In zh, this message translates to:
  /// **'点击\"上传文档\"添加 PDF、DOCX 或 TXT 文件'**
  String get serverUploadHint;

  /// No description provided for @desktopFormatTooltip.
  ///
  /// In zh, this message translates to:
  /// **'桌面模式支持 TXT/MD/HTML/PDF\nDOCX 需要部署服务器模式'**
  String get desktopFormatTooltip;

  /// No description provided for @desktopDocxWarning.
  ///
  /// In zh, this message translates to:
  /// **'桌面模式暂不支持 DOCX 解析，如需解析这些格式请部署服务器模式'**
  String get desktopDocxWarning;

  /// No description provided for @folderEmpty.
  ///
  /// In zh, this message translates to:
  /// **'文件夹 \"{folder}\" 中暂无文档'**
  String folderEmpty(String folder);

  /// No description provided for @chunkCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 分块'**
  String chunkCount(int count);

  /// No description provided for @moveToFolder.
  ///
  /// In zh, this message translates to:
  /// **'移动到文件夹'**
  String get moveToFolder;

  /// No description provided for @all.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get all;

  /// No description provided for @newFolder.
  ///
  /// In zh, this message translates to:
  /// **'新建文件夹'**
  String get newFolder;

  /// No description provided for @folderName.
  ///
  /// In zh, this message translates to:
  /// **'文件夹名称'**
  String get folderName;

  /// No description provided for @create.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get create;

  /// No description provided for @moveToFolderTitle.
  ///
  /// In zh, this message translates to:
  /// **'移动到文件夹'**
  String get moveToFolderTitle;

  /// No description provided for @currentFolder.
  ///
  /// In zh, this message translates to:
  /// **'当前文件夹: {name}'**
  String currentFolder(String name);

  /// No description provided for @selectExistingFolder.
  ///
  /// In zh, this message translates to:
  /// **'选择已有文件夹:'**
  String get selectExistingFolder;

  /// No description provided for @noFolder.
  ///
  /// In zh, this message translates to:
  /// **'无文件夹'**
  String get noFolder;

  /// No description provided for @orEnterNewFolder.
  ///
  /// In zh, this message translates to:
  /// **'或输入新文件夹:'**
  String get orEnterNewFolder;

  /// No description provided for @enterFolderName.
  ///
  /// In zh, this message translates to:
  /// **'输入文件夹名称:'**
  String get enterFolderName;

  /// No description provided for @newFolderName.
  ///
  /// In zh, this message translates to:
  /// **'新文件夹名'**
  String get newFolderName;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get confirm;

  /// No description provided for @switchWorkspaceTooltip.
  ///
  /// In zh, this message translates to:
  /// **'切换工作区/资料库'**
  String get switchWorkspaceTooltip;

  /// No description provided for @switchLabel.
  ///
  /// In zh, this message translates to:
  /// **'切换'**
  String get switchLabel;

  /// No description provided for @statusReady.
  ///
  /// In zh, this message translates to:
  /// **'就绪'**
  String get statusReady;

  /// No description provided for @statusProcessing.
  ///
  /// In zh, this message translates to:
  /// **'解析中'**
  String get statusProcessing;

  /// No description provided for @statusChunking.
  ///
  /// In zh, this message translates to:
  /// **'分块中'**
  String get statusChunking;

  /// No description provided for @statusEmbedding.
  ///
  /// In zh, this message translates to:
  /// **'向量化中'**
  String get statusEmbedding;

  /// No description provided for @statusFailed.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get statusFailed;

  /// No description provided for @statusPending.
  ///
  /// In zh, this message translates to:
  /// **'等待'**
  String get statusPending;

  /// No description provided for @reviewRecords.
  ///
  /// In zh, this message translates to:
  /// **'审核记录'**
  String get reviewRecords;

  /// No description provided for @refresh.
  ///
  /// In zh, this message translates to:
  /// **'刷新'**
  String get refresh;

  /// No description provided for @noReviews.
  ///
  /// In zh, this message translates to:
  /// **'暂无审核记录'**
  String get noReviews;

  /// No description provided for @noReviewsDescription.
  ///
  /// In zh, this message translates to:
  /// **'在对话中审核 AI 引用后，记录将在此处显示'**
  String get noReviewsDescription;

  /// No description provided for @correction.
  ///
  /// In zh, this message translates to:
  /// **'修正'**
  String correction(String text);

  /// No description provided for @citationId.
  ///
  /// In zh, this message translates to:
  /// **'引用 ID: {id}...'**
  String citationId(String id);

  /// No description provided for @statusApproved.
  ///
  /// In zh, this message translates to:
  /// **'通过'**
  String get statusApproved;

  /// No description provided for @statusRejected.
  ///
  /// In zh, this message translates to:
  /// **'拒绝'**
  String get statusRejected;

  /// No description provided for @statusFlagged.
  ///
  /// In zh, this message translates to:
  /// **'存疑'**
  String get statusFlagged;

  /// No description provided for @statusPendingReview.
  ///
  /// In zh, this message translates to:
  /// **'待定'**
  String get statusPendingReview;

  /// No description provided for @workspaces.
  ///
  /// In zh, this message translates to:
  /// **'工作区'**
  String get workspaces;

  /// No description provided for @createNew.
  ///
  /// In zh, this message translates to:
  /// **'新建'**
  String get createNew;

  /// No description provided for @noWorkspaces.
  ///
  /// In zh, this message translates to:
  /// **'还没有工作区'**
  String get noWorkspaces;

  /// No description provided for @createFirstWorkspace.
  ///
  /// In zh, this message translates to:
  /// **'创建第一个工作区'**
  String get createFirstWorkspace;

  /// No description provided for @noDescription.
  ///
  /// In zh, this message translates to:
  /// **'无描述'**
  String get noDescription;

  /// No description provided for @createWorkspace.
  ///
  /// In zh, this message translates to:
  /// **'新建工作区'**
  String get createWorkspace;

  /// No description provided for @nameLabel.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get nameLabel;

  /// No description provided for @descriptionLabel.
  ///
  /// In zh, this message translates to:
  /// **'描述（可选）'**
  String get descriptionLabel;

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @modelConfig.
  ///
  /// In zh, this message translates to:
  /// **'模型配置'**
  String get modelConfig;

  /// No description provided for @modelConfigSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'管理 LLM 和 Embedding 模型'**
  String get modelConfigSubtitle;

  /// No description provided for @teamMembers.
  ///
  /// In zh, this message translates to:
  /// **'团队成员'**
  String get teamMembers;

  /// No description provided for @teamMembersSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'管理工作区的成员和权限'**
  String get teamMembersSubtitle;

  /// No description provided for @accountInfo.
  ///
  /// In zh, this message translates to:
  /// **'账户信息'**
  String get accountInfo;

  /// No description provided for @unknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get unknown;

  /// No description provided for @appearance.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get appearance;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get themeDark;

  /// No description provided for @themeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get themeSystem;

  /// No description provided for @developerMode.
  ///
  /// In zh, this message translates to:
  /// **'开发者模式'**
  String get developerMode;

  /// No description provided for @devModeOn.
  ///
  /// In zh, this message translates to:
  /// **'已开启 — 显示调试工具'**
  String get devModeOn;

  /// No description provided for @devModeOff.
  ///
  /// In zh, this message translates to:
  /// **'开启后可查看日志、API 请求等调试信息'**
  String get devModeOff;

  /// No description provided for @debugLog.
  ///
  /// In zh, this message translates to:
  /// **'调试日志'**
  String get debugLog;

  /// No description provided for @debugLogSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看运行时日志和 API 请求记录'**
  String get debugLogSubtitle;

  /// No description provided for @runtimeEnv.
  ///
  /// In zh, this message translates to:
  /// **'运行环境'**
  String get runtimeEnv;

  /// No description provided for @envInfoCopied.
  ///
  /// In zh, this message translates to:
  /// **'环境信息已复制'**
  String get envInfoCopied;

  /// No description provided for @checkUpdate.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get checkUpdate;

  /// No description provided for @currentVersion.
  ///
  /// In zh, this message translates to:
  /// **'当前版本 v{version}'**
  String currentVersion(String version);

  /// No description provided for @about.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get about;

  /// No description provided for @alreadyLatest.
  ///
  /// In zh, this message translates to:
  /// **'已是最新版本'**
  String get alreadyLatest;

  /// No description provided for @checkUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'检查更新失败: {error}'**
  String checkUpdateFailed(String error);

  /// No description provided for @debugLogTitle.
  ///
  /// In zh, this message translates to:
  /// **'调试日志'**
  String get debugLogTitle;

  /// No description provided for @clearLog.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get clearLog;

  /// No description provided for @noLogs.
  ///
  /// In zh, this message translates to:
  /// **'暂无日志'**
  String get noLogs;

  /// No description provided for @logCopied.
  ///
  /// In zh, this message translates to:
  /// **'日志已复制到剪贴板'**
  String get logCopied;

  /// No description provided for @copyAll.
  ///
  /// In zh, this message translates to:
  /// **'复制全部'**
  String get copyAll;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @accountInfoTitle.
  ///
  /// In zh, this message translates to:
  /// **'账户信息'**
  String get accountInfoTitle;

  /// No description provided for @username.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get username;

  /// No description provided for @email.
  ///
  /// In zh, this message translates to:
  /// **'邮箱'**
  String get email;

  /// No description provided for @role.
  ///
  /// In zh, this message translates to:
  /// **'角色'**
  String get role;

  /// No description provided for @aboutTrustRAG.
  ///
  /// In zh, this message translates to:
  /// **'关于 TrustRAG'**
  String get aboutTrustRAG;

  /// No description provided for @trustragDescription.
  ///
  /// In zh, this message translates to:
  /// **'TrustRAG - 可信赖的 RAG 知识工作台'**
  String get trustragDescription;

  /// No description provided for @version.
  ///
  /// In zh, this message translates to:
  /// **'版本'**
  String get version;

  /// No description provided for @backend.
  ///
  /// In zh, this message translates to:
  /// **'后端'**
  String get backend;

  /// No description provided for @frontend.
  ///
  /// In zh, this message translates to:
  /// **'前端'**
  String get frontend;

  /// No description provided for @database.
  ///
  /// In zh, this message translates to:
  /// **'数据库'**
  String get database;

  /// No description provided for @storage.
  ///
  /// In zh, this message translates to:
  /// **'存储'**
  String get storage;

  /// No description provided for @aboutDescription.
  ///
  /// In zh, this message translates to:
  /// **'基于文档检索增强生成（RAG）技术，提供带引用溯源的可信赖 AI 问答。'**
  String get aboutDescription;

  /// No description provided for @logout.
  ///
  /// In zh, this message translates to:
  /// **'退出登录'**
  String get logout;

  /// No description provided for @newVersionFound.
  ///
  /// In zh, this message translates to:
  /// **'发现新版本'**
  String get newVersionFound;

  /// No description provided for @releaseNotes.
  ///
  /// In zh, this message translates to:
  /// **'更新内容'**
  String get releaseNotes;

  /// No description provided for @skipThisVersion.
  ///
  /// In zh, this message translates to:
  /// **'跳过此版本'**
  String get skipThisVersion;

  /// No description provided for @remindLater.
  ///
  /// In zh, this message translates to:
  /// **'稍后提醒'**
  String get remindLater;

  /// No description provided for @goToDownload.
  ///
  /// In zh, this message translates to:
  /// **'前往下载'**
  String get goToDownload;

  /// No description provided for @cannotOpenLink.
  ///
  /// In zh, this message translates to:
  /// **'无法打开链接: {error}'**
  String cannotOpenLink(String error);

  /// No description provided for @inviteMember.
  ///
  /// In zh, this message translates to:
  /// **'邀请成员'**
  String get inviteMember;

  /// No description provided for @emailAddress.
  ///
  /// In zh, this message translates to:
  /// **'邮箱地址'**
  String get emailAddress;

  /// No description provided for @roleLabel.
  ///
  /// In zh, this message translates to:
  /// **'角色'**
  String get roleLabel;

  /// No description provided for @viewer.
  ///
  /// In zh, this message translates to:
  /// **'查看者'**
  String get viewer;

  /// No description provided for @editor.
  ///
  /// In zh, this message translates to:
  /// **'编辑者'**
  String get editor;

  /// No description provided for @owner.
  ///
  /// In zh, this message translates to:
  /// **'所有者'**
  String get owner;

  /// No description provided for @admin.
  ///
  /// In zh, this message translates to:
  /// **'管理员'**
  String get admin;

  /// No description provided for @invite.
  ///
  /// In zh, this message translates to:
  /// **'邀请'**
  String get invite;

  /// No description provided for @invited.
  ///
  /// In zh, this message translates to:
  /// **'已邀请 {email}'**
  String invited(String email);

  /// No description provided for @inviteFailed.
  ///
  /// In zh, this message translates to:
  /// **'邀请失败: {error}'**
  String inviteFailed(String error);

  /// No description provided for @changeRole.
  ///
  /// In zh, this message translates to:
  /// **'修改角色'**
  String get changeRole;

  /// No description provided for @changeRoleTitle.
  ///
  /// In zh, this message translates to:
  /// **'修改 {name} 的角色'**
  String changeRoleTitle(String name);

  /// No description provided for @changeRoleFailed.
  ///
  /// In zh, this message translates to:
  /// **'修改失败: {error}'**
  String changeRoleFailed(String error);

  /// No description provided for @removeMember.
  ///
  /// In zh, this message translates to:
  /// **'移除成员'**
  String get removeMember;

  /// No description provided for @removeMemberConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认将 {name} 从工作区中移除？'**
  String removeMemberConfirm(String name);

  /// No description provided for @remove.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get remove;

  /// No description provided for @removeFailed.
  ///
  /// In zh, this message translates to:
  /// **'移除失败: {error}'**
  String removeFailed(String error);

  /// No description provided for @ownerPermission.
  ///
  /// In zh, this message translates to:
  /// **'完全控制权限，可管理成员和设置'**
  String get ownerPermission;

  /// No description provided for @editorPermission.
  ///
  /// In zh, this message translates to:
  /// **'可编辑文档和对话，管理成员'**
  String get editorPermission;

  /// No description provided for @viewerPermission.
  ///
  /// In zh, this message translates to:
  /// **'仅可查看文档和对话'**
  String get viewerPermission;

  /// No description provided for @memberManagement.
  ///
  /// In zh, this message translates to:
  /// **'成员管理'**
  String get memberManagement;

  /// No description provided for @memberManagementWithWs.
  ///
  /// In zh, this message translates to:
  /// **'成员管理 — {name}'**
  String memberManagementWithWs(String name);

  /// No description provided for @noMembers.
  ///
  /// In zh, this message translates to:
  /// **'暂无成员'**
  String get noMembers;

  /// No description provided for @me.
  ///
  /// In zh, this message translates to:
  /// **'我'**
  String get me;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @languageZh.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get languageZh;

  /// No description provided for @languageEn.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get languageEn;

  /// No description provided for @languageJa.
  ///
  /// In zh, this message translates to:
  /// **'日本語'**
  String get languageJa;

  /// No description provided for @noReviewRecords.
  ///
  /// In zh, this message translates to:
  /// **'暂无审核记录'**
  String get noReviewRecords;

  /// No description provided for @reviewRecordsHint.
  ///
  /// In zh, this message translates to:
  /// **'在对话中审核 AI 引用后，记录将在此处显示'**
  String get reviewRecordsHint;

  /// No description provided for @exportReport.
  ///
  /// In zh, this message translates to:
  /// **'导出报告'**
  String get exportReport;

  /// No description provided for @reviewReport.
  ///
  /// In zh, this message translates to:
  /// **'审核报告'**
  String get reviewReport;

  /// No description provided for @generating.
  ///
  /// In zh, this message translates to:
  /// **'生成中...'**
  String get generating;

  /// No description provided for @reportGeneratedAt.
  ///
  /// In zh, this message translates to:
  /// **'生成时间: {time}'**
  String reportGeneratedAt(String time);

  /// No description provided for @totalCitations.
  ///
  /// In zh, this message translates to:
  /// **'总引用数'**
  String get totalCitations;

  /// No description provided for @reviewed.
  ///
  /// In zh, this message translates to:
  /// **'已审核'**
  String get reviewed;

  /// No description provided for @unreviewedCount.
  ///
  /// In zh, this message translates to:
  /// **'未审核'**
  String get unreviewedCount;

  /// No description provided for @reviewCoverage.
  ///
  /// In zh, this message translates to:
  /// **'审核覆盖率'**
  String get reviewCoverage;

  /// No description provided for @approvalRate.
  ///
  /// In zh, this message translates to:
  /// **'通过率'**
  String get approvalRate;

  /// No description provided for @rejectionRate.
  ///
  /// In zh, this message translates to:
  /// **'拒绝率'**
  String get rejectionRate;

  /// No description provided for @hallucinationRate.
  ///
  /// In zh, this message translates to:
  /// **'幻觉率'**
  String get hallucinationRate;

  /// No description provided for @keyMetrics.
  ///
  /// In zh, this message translates to:
  /// **'关键指标'**
  String get keyMetrics;

  /// No description provided for @reviewResults.
  ///
  /// In zh, this message translates to:
  /// **'审核结果分布'**
  String get reviewResults;

  /// No description provided for @reviewDetails.
  ///
  /// In zh, this message translates to:
  /// **'审核明细'**
  String get reviewDetails;

  /// No description provided for @approved.
  ///
  /// In zh, this message translates to:
  /// **'通过'**
  String get approved;

  /// No description provided for @rejected.
  ///
  /// In zh, this message translates to:
  /// **'拒绝'**
  String get rejected;

  /// No description provided for @flagged.
  ///
  /// In zh, this message translates to:
  /// **'存疑'**
  String get flagged;

  /// No description provided for @pending.
  ///
  /// In zh, this message translates to:
  /// **'待定'**
  String get pending;

  /// No description provided for @document.
  ///
  /// In zh, this message translates to:
  /// **'文档'**
  String get document;

  /// No description provided for @section.
  ///
  /// In zh, this message translates to:
  /// **'章节'**
  String get section;

  /// No description provided for @page.
  ///
  /// In zh, this message translates to:
  /// **'页码'**
  String get page;

  /// No description provided for @quote.
  ///
  /// In zh, this message translates to:
  /// **'引用'**
  String get quote;

  /// No description provided for @copyMarkdown.
  ///
  /// In zh, this message translates to:
  /// **'复制 Markdown'**
  String get copyMarkdown;

  /// No description provided for @copiedToClipboard.
  ///
  /// In zh, this message translates to:
  /// **'已复制到剪贴板'**
  String get copiedToClipboard;

  /// No description provided for @reportLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'报告生成失败'**
  String get reportLoadFailed;

  /// No description provided for @overview.
  ///
  /// In zh, this message translates to:
  /// **'概览'**
  String get overview;
}

class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();

  @override
  Future<S> load(Locale locale) {
    return SynchronousFuture<S>(lookupS(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_SDelegate old) => false;
}

S lookupS(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return SEn();
    case 'ja':
      return SJa();
    case 'zh':
      return SZh();
  }

  throw FlutterError(
    'S.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
