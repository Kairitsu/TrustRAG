// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class SJa extends S {
  SJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'TrustRAG';

  @override
  String get navChat => 'チャット';

  @override
  String get navDocuments => 'ドキュメント';

  @override
  String get navReview => 'レビュー';

  @override
  String get navWorkspaces => 'ワークスペース';

  @override
  String get navSearch => '検索';

  @override
  String get navSettings => '設定';

  @override
  String get selectWorkspaceFirst => 'ワークスペースを選択してください';

  @override
  String loadFailed(String error) {
    return '読み込み失敗: $error';
  }

  @override
  String get newConversation => '新しいチャット';

  @override
  String get startNewConversation => '新しい会話を始めましょう';

  @override
  String get aiChatDescription => 'ドキュメントに基づくAI質問応答';

  @override
  String get noConversations => '会話がありません';

  @override
  String get conversation => 'チャット';

  @override
  String get today => '今日';

  @override
  String get yesterday => '昨日';

  @override
  String get earlier => 'それ以前';

  @override
  String get inputHint => '質問を入力...';

  @override
  String get thinking => '考え中...';

  @override
  String get copy => 'コピー';

  @override
  String get retry => '再試行';

  @override
  String get edit => '編集';

  @override
  String get copied => 'コピーしました';

  @override
  String get editMessage => 'メッセージを編集';

  @override
  String get editMessageHint => 'メッセージ内容を編集...';

  @override
  String get cancel => 'キャンセル';

  @override
  String get resend => '再送信';

  @override
  String citationSources(int count) {
    return '引用元 ($count)';
  }

  @override
  String aiError(String error) {
    return 'AIエラー: $error';
  }

  @override
  String sendFailed(String error) {
    return '送信失敗: $error';
  }

  @override
  String get switchWorkspace => 'ワークスペース切り替え';

  @override
  String get documents => 'ドキュメント';

  @override
  String get uploadDocument => 'ドキュメントをアップロード';

  @override
  String get selectItems => '選択';

  @override
  String selectedCount(int count) {
    return '$count 件選択中';
  }

  @override
  String get batchDelete => '一括削除';

  @override
  String batchDeleteConfirm(int count) {
    return '$count 件のドキュメントを削除しますか？この操作は取り消せません。';
  }

  @override
  String get batchDeleteDone => '一括削除完了';

  @override
  String uploadSuccessCount(int count) {
    return '$count ファイルのアップロードに成功';
  }

  @override
  String get delete => '削除';

  @override
  String get noDocuments => 'ドキュメントがありません';

  @override
  String get desktopUploadHint =>
      '「ドキュメントをアップロード」をクリックしてPDF、TXT、MDまたはHTMLファイルを追加';

  @override
  String get serverUploadHint => '「ドキュメントをアップロード」をクリックしてPDF、DOCXまたはTXTファイルを追加';

  @override
  String get desktopFormatTooltip =>
      'デスクトップモードはTXT/MD/HTML/PDFに対応\nDOCXはサーバーモードが必要';

  @override
  String get desktopDocxWarning => 'デスクトップモードではDOCX解析に対応していません。サーバーモードをご利用ください';

  @override
  String folderEmpty(String folder) {
    return 'フォルダ「$folder」にドキュメントがありません';
  }

  @override
  String chunkCount(int count) {
    return '$count チャンク';
  }

  @override
  String get moveToFolder => 'フォルダに移動';

  @override
  String get all => 'すべて';

  @override
  String get newFolder => '新しいフォルダ';

  @override
  String get folderName => 'フォルダ名';

  @override
  String get create => '作成';

  @override
  String get moveToFolderTitle => 'フォルダに移動';

  @override
  String currentFolder(String name) {
    return '現在のフォルダ: $name';
  }

  @override
  String get selectExistingFolder => '既存のフォルダを選択:';

  @override
  String get noFolder => 'フォルダなし';

  @override
  String get orEnterNewFolder => 'または新しいフォルダを入力:';

  @override
  String get enterFolderName => 'フォルダ名を入力:';

  @override
  String get newFolderName => '新しいフォルダ名';

  @override
  String get confirm => '確認';

  @override
  String get switchWorkspaceTooltip => 'ワークスペース/ドキュメント切り替え';

  @override
  String get switchLabel => '切替';

  @override
  String get statusReady => '準備完了';

  @override
  String get statusProcessing => '解析中';

  @override
  String get statusChunking => '分割中';

  @override
  String get statusEmbedding => 'ベクトル化中';

  @override
  String get statusFailed => '失敗';

  @override
  String get statusPending => '待機中';

  @override
  String get reviewRecords => 'レビュー記録';

  @override
  String get refresh => '更新';

  @override
  String get noReviews => 'レビュー記録がありません';

  @override
  String get noReviewsDescription => 'チャットでAI引用をレビューすると、ここに記録が表示されます';

  @override
  String correction(String text) {
    return '訂正';
  }

  @override
  String citationId(String id) {
    return '引用 ID: $id...';
  }

  @override
  String get statusApproved => '承認';

  @override
  String get statusRejected => '拒否';

  @override
  String get statusFlagged => '要確認';

  @override
  String get statusPendingReview => '未処理';

  @override
  String get workspaces => 'ワークスペース';

  @override
  String get createNew => '新規作成';

  @override
  String get noWorkspaces => 'ワークスペースがありません';

  @override
  String get createFirstWorkspace => '最初のワークスペースを作成';

  @override
  String get noDescription => '説明なし';

  @override
  String get createWorkspace => 'ワークスペースを作成';

  @override
  String get nameLabel => '名前';

  @override
  String get descriptionLabel => '説明（任意）';

  @override
  String get settings => '設定';

  @override
  String get modelConfig => 'モデル設定';

  @override
  String get modelConfigSubtitle => 'LLMとEmbeddingモデルを管理';

  @override
  String get teamMembers => 'チームメンバー';

  @override
  String get teamMembersSubtitle => 'ワークスペースのメンバーと権限を管理';

  @override
  String get accountInfo => 'アカウント情報';

  @override
  String get unknown => '不明';

  @override
  String get appearance => '外観';

  @override
  String get themeLight => 'ライト';

  @override
  String get themeDark => 'ダーク';

  @override
  String get themeSystem => 'システム設定に従う';

  @override
  String get developerMode => '開発者モード';

  @override
  String get devModeOn => '有効 — デバッグツールを表示';

  @override
  String get devModeOff => '有効にするとログやAPIリクエストなどのデバッグ情報を確認できます';

  @override
  String get debugLog => 'デバッグログ';

  @override
  String get debugLogSubtitle => 'ランタイムログとAPIリクエスト記録を表示';

  @override
  String get runtimeEnv => '実行環境';

  @override
  String get envInfoCopied => '環境情報をコピーしました';

  @override
  String get checkUpdate => 'アップデートを確認';

  @override
  String currentVersion(String version) {
    return '現在のバージョン v$version';
  }

  @override
  String get about => 'TrustRAGについて';

  @override
  String get alreadyLatest => '最新バージョンです';

  @override
  String checkUpdateFailed(String error) {
    return 'アップデート確認失敗: $error';
  }

  @override
  String get debugLogTitle => 'デバッグログ';

  @override
  String get clearLog => 'クリア';

  @override
  String get noLogs => 'ログがありません';

  @override
  String get logCopied => 'ログをクリップボードにコピーしました';

  @override
  String get copyAll => 'すべてコピー';

  @override
  String get close => '閉じる';

  @override
  String get accountInfoTitle => 'アカウント情報';

  @override
  String get username => 'ユーザー名';

  @override
  String get email => 'メール';

  @override
  String get role => '役割';

  @override
  String get aboutTrustRAG => 'TrustRAGについて';

  @override
  String get trustragDescription => 'TrustRAG - 信頼できるRAGナレッジワークベンチ';

  @override
  String get version => 'バージョン';

  @override
  String get backend => 'バックエンド';

  @override
  String get frontend => 'フロントエンド';

  @override
  String get database => 'データベース';

  @override
  String get storage => 'ストレージ';

  @override
  String get aboutDescription => '検索拡張生成（RAG）技術に基づく、引用追跡可能な信頼性の高いAI質問応答。';

  @override
  String get logout => 'ログアウト';

  @override
  String get newVersionFound => '新しいバージョンが利用可能';

  @override
  String get releaseNotes => '更新内容';

  @override
  String get skipThisVersion => 'このバージョンをスキップ';

  @override
  String get remindLater => '後で通知';

  @override
  String get goToDownload => 'ダウンロード';

  @override
  String cannotOpenLink(String error) {
    return 'リンクを開けません: $error';
  }

  @override
  String get inviteMember => 'メンバーを招待';

  @override
  String get emailAddress => 'メールアドレス';

  @override
  String get roleLabel => '役割';

  @override
  String get viewer => '閲覧者';

  @override
  String get editor => '編集者';

  @override
  String get owner => 'オーナー';

  @override
  String get admin => '管理者';

  @override
  String get invite => '招待';

  @override
  String invited(String email) {
    return '$email を招待しました';
  }

  @override
  String inviteFailed(String error) {
    return '招待失敗: $error';
  }

  @override
  String get changeRole => '役割を変更';

  @override
  String changeRoleTitle(String name) {
    return '$name の役割を変更';
  }

  @override
  String changeRoleFailed(String error) {
    return '変更失敗: $error';
  }

  @override
  String get removeMember => 'メンバーを削除';

  @override
  String removeMemberConfirm(String name) {
    return '$name をワークスペースから削除しますか？';
  }

  @override
  String get remove => '削除';

  @override
  String removeFailed(String error) {
    return '削除失敗: $error';
  }

  @override
  String get ownerPermission => '完全な制御権限、メンバーと設定を管理可能';

  @override
  String get editorPermission => 'ドキュメントとチャットを編集、メンバーを管理可能';

  @override
  String get viewerPermission => 'ドキュメントとチャットの閲覧のみ';

  @override
  String get memberManagement => 'メンバー管理';

  @override
  String memberManagementWithWs(String name) {
    return 'メンバー管理 — $name';
  }

  @override
  String get noMembers => 'メンバーがいません';

  @override
  String get me => '自分';

  @override
  String get language => '言語';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageEn => 'English';

  @override
  String get languageJa => '日本語';

  @override
  String get languageKo => '한국어';

  @override
  String get navKnowledgeGraph => 'グラフ';

  @override
  String get knowledgeGraph => 'ナレッジグラフ';

  @override
  String knowledgeGraphDesc(String name) {
    return '「$name」のエンティティと関係';
  }

  @override
  String get graphView => '関係図';

  @override
  String get entityList => 'エンティティ一覧';

  @override
  String get noGraphData => 'グラフデータなし';

  @override
  String get noGraphDataHint => 'ドキュメントをアップロードして解析すると、ナレッジグラフが自動生成されます';

  @override
  String get noEntities => 'エンティティなし';

  @override
  String get searchEntities => 'エンティティ名またはタイプで検索...';

  @override
  String get entitiesCount => 'エンティティ';

  @override
  String get typesCount => 'タイプ';

  @override
  String get entityType => 'タイプ';

  @override
  String get relatedEntities => '関連エンティティ';

  @override
  String get nodes => 'ノード';

  @override
  String get edges => 'エッジ';

  @override
  String get noReviewRecords => 'レビュー記録なし';

  @override
  String get reviewRecordsHint => '会話でAI引用をレビューすると、ここに記録が表示されます';

  @override
  String get exportReport => 'レポート出力';

  @override
  String get reviewReport => 'レビューレポート';

  @override
  String get generating => '生成中...';

  @override
  String reportGeneratedAt(String time) {
    return '生成日時: $time';
  }

  @override
  String get totalCitations => '引用総数';

  @override
  String get reviewed => 'レビュー済み';

  @override
  String get unreviewedCount => '未レビュー';

  @override
  String get reviewCoverage => 'レビューカバー率';

  @override
  String get approvalRate => '承認率';

  @override
  String get rejectionRate => '却下率';

  @override
  String get hallucinationRate => 'ハルシネーション率';

  @override
  String get keyMetrics => '主要指標';

  @override
  String get reviewResults => 'レビュー結果';

  @override
  String get reviewDetails => 'レビュー詳細';

  @override
  String get approved => '承認';

  @override
  String get rejected => '却下';

  @override
  String get flagged => '要確認';

  @override
  String get pending => '保留';

  @override
  String get document => 'ドキュメント';

  @override
  String get section => 'セクション';

  @override
  String get page => 'ページ';

  @override
  String get quote => '引用';

  @override
  String get copyMarkdown => 'Markdownをコピー';

  @override
  String get copiedToClipboard => 'クリップボードにコピーしました';

  @override
  String get reportLoadFailed => 'レポート生成に失敗しました';

  @override
  String get overview => '概要';

  @override
  String get personalSpace => '個人スペース';

  @override
  String get teamSpace => 'チームスペース';

  @override
  String get createTeam => 'チーム作成';

  @override
  String get joinTeam => 'チームに参加';

  @override
  String get teamName => 'チーム名';

  @override
  String get teamDescription => 'チームの説明（任意）';

  @override
  String get inviteCode => '招待コード';

  @override
  String get enterInviteCode => '8桁の招待コードを入力';

  @override
  String get joinButton => '参加';

  @override
  String teamCreated(Object name, Object code) {
    return 'チーム「$name」を作成しました！招待コード: $code';
  }

  @override
  String joinedTeam(Object name) {
    return 'チーム「$name」に参加しました！';
  }

  @override
  String get joinFailed => '参加に失敗しました。招待コードを確認してください。';

  @override
  String get teamSettings => 'チーム設定';

  @override
  String manageTeam(Object name) {
    return '「$name」チームの管理';
  }

  @override
  String get regenerateInviteCode => '招待コードを再生成';

  @override
  String get regenerateConfirm => '再生成すると、古い招待コードは無効になります。続行しますか？';

  @override
  String newInviteCode(Object code) {
    return '新しい招待コード: $code';
  }

  @override
  String get copyInviteCode => '招待コードをコピー';

  @override
  String get inviteCodeCopied => '招待コードをコピーしました';

  @override
  String get shareInvite => '招待を共有';

  @override
  String get shareInviteSubtitle => '招待コードをチームメンバーに送信';

  @override
  String inviteMessage(Object name, Object code) {
    return 'TrustRAGチーム「$name」に参加しませんか\n招待コード: $code';
  }

  @override
  String get inviteInfoCopied => '招待情報をクリップボードにコピーしました';

  @override
  String get memberManagementSubtitle => 'チームメンバーの表示と管理';

  @override
  String get transferOwnership => '管理者の移譲';

  @override
  String get transferOwnershipDesc => 'チームの所有権を他のメンバーに移譲';

  @override
  String get goToMemberManagement => 'メンバー管理へ';

  @override
  String get disbandTeam => 'チーム解散';

  @override
  String get disbandTeamDesc => 'チームとすべてのデータを永久に削除';

  @override
  String get disbandWarning =>
      'この操作は元に戻せません！チーム内のすべてのドキュメント、会話、レビュー記録が永久に削除されます。';

  @override
  String disbandConfirmPrompt(Object name) {
    return '確認のためチーム名「$name」を入力してください：';
  }

  @override
  String get confirmDisband => '解散を確認';

  @override
  String get teamNameMismatch => 'チーム名が一致しません';

  @override
  String get teamDisbanded => 'チームが解散されました';

  @override
  String disbandFailed(Object error) {
    return '解散に失敗しました: $error';
  }

  @override
  String get roleOwner => 'オーナー';

  @override
  String get roleAdmin => '管理者';

  @override
  String get roleEditor => '編集者';

  @override
  String get roleViewer => '閲覧者';

  @override
  String get roleOwnerDesc => '完全な権限、メンバー・設定・API設定の管理';

  @override
  String get roleAdminDesc => 'メンバー、LLM設定、APIキーの管理';

  @override
  String get roleEditorDesc => 'ドキュメントと会話の編集';

  @override
  String get roleViewerDesc => 'ドキュメントと会話の閲覧、レビューの提出';

  @override
  String get team => 'チーム';

  @override
  String get collapseSidebar => 'サイドバーを折りたたむ';

  @override
  String get expandSidebar => 'サイドバーを展開';
}
