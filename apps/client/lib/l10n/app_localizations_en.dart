// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class SEn extends S {
  SEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'TrustRAG';

  @override
  String get navChat => 'Chat';

  @override
  String get navDocuments => 'Documents';

  @override
  String get navReview => 'Review';

  @override
  String get navWorkspaces => 'Workspaces';

  @override
  String get navSearch => 'Search';

  @override
  String get navSettings => 'Settings';

  @override
  String get selectWorkspaceFirst => 'Please select a workspace first';

  @override
  String loadFailed(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get newConversation => 'New Chat';

  @override
  String get startNewConversation => 'Start a new conversation';

  @override
  String get aiChatDescription => 'AI-powered Q&A based on your documents';

  @override
  String get noConversations => 'No conversations yet';

  @override
  String get conversation => 'Chat';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get earlier => 'Earlier';

  @override
  String get inputHint => 'Type your question...';

  @override
  String get thinking => 'Thinking...';

  @override
  String get copy => 'Copy';

  @override
  String get retry => 'Retry';

  @override
  String get edit => 'Edit';

  @override
  String get copied => 'Copied';

  @override
  String get editMessage => 'Edit Message';

  @override
  String get editMessageHint => 'Edit message content...';

  @override
  String get cancel => 'Cancel';

  @override
  String get resend => 'Resend';

  @override
  String citationSources(int count) {
    return 'Citation Sources ($count)';
  }

  @override
  String aiError(String error) {
    return 'AI Error: $error';
  }

  @override
  String sendFailed(String error) {
    return 'Send failed: $error';
  }

  @override
  String get switchWorkspace => 'Switch Workspace';

  @override
  String get documents => 'Documents';

  @override
  String get uploadDocument => 'Upload Document';

  @override
  String get selectItems => 'Select';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get batchDelete => 'Batch Delete';

  @override
  String batchDeleteConfirm(int count) {
    return 'Delete $count documents? This cannot be undone.';
  }

  @override
  String get batchDeleteDone => 'Batch delete complete';

  @override
  String uploadSuccessCount(int count) {
    return 'Successfully uploaded $count files';
  }

  @override
  String get delete => 'Delete';

  @override
  String get noDocuments => 'No documents yet';

  @override
  String get desktopUploadHint =>
      'Click \"Upload Document\" to add PDF, TXT, MD or HTML files';

  @override
  String get serverUploadHint =>
      'Click \"Upload Document\" to add PDF, DOCX or TXT files';

  @override
  String get desktopFormatTooltip =>
      'Desktop mode supports TXT/MD/HTML/PDF\nDOCX requires server deployment';

  @override
  String get desktopDocxWarning =>
      'Desktop mode does not support DOCX parsing. Please deploy server mode for these formats';

  @override
  String folderEmpty(String folder) {
    return 'No documents in folder \"$folder\"';
  }

  @override
  String chunkCount(int count) {
    return '$count chunks';
  }

  @override
  String get moveToFolder => 'Move to Folder';

  @override
  String get all => 'All';

  @override
  String get newFolder => 'New Folder';

  @override
  String get folderName => 'Folder name';

  @override
  String get create => 'Create';

  @override
  String get moveToFolderTitle => 'Move to Folder';

  @override
  String currentFolder(String name) {
    return 'Current folder: $name';
  }

  @override
  String get selectExistingFolder => 'Select existing folder:';

  @override
  String get noFolder => 'No folder';

  @override
  String get orEnterNewFolder => 'Or enter a new folder:';

  @override
  String get enterFolderName => 'Enter folder name:';

  @override
  String get newFolderName => 'New folder name';

  @override
  String get confirm => 'OK';

  @override
  String get switchWorkspaceTooltip => 'Switch workspace/documents';

  @override
  String get switchLabel => 'Switch';

  @override
  String get statusReady => 'Ready';

  @override
  String get statusProcessing => 'Processing';

  @override
  String get statusChunking => 'Chunking';

  @override
  String get statusEmbedding => 'Embedding';

  @override
  String get statusFailed => 'Failed';

  @override
  String get statusPending => 'Pending';

  @override
  String get reviewRecords => 'Review Records';

  @override
  String get refresh => 'Refresh';

  @override
  String get noReviews => 'No review records';

  @override
  String get noReviewsDescription =>
      'After reviewing AI citations in chat, records will appear here';

  @override
  String correction(String text) {
    return 'Correction: $text';
  }

  @override
  String citationId(String id) {
    return 'Citation ID: $id...';
  }

  @override
  String get statusApproved => 'Approved';

  @override
  String get statusRejected => 'Rejected';

  @override
  String get statusFlagged => 'Flagged';

  @override
  String get statusPendingReview => 'Pending';

  @override
  String get workspaces => 'Workspaces';

  @override
  String get createNew => 'New';

  @override
  String get noWorkspaces => 'No workspaces yet';

  @override
  String get createFirstWorkspace => 'Create your first workspace';

  @override
  String get noDescription => 'No description';

  @override
  String get createWorkspace => 'Create Workspace';

  @override
  String get nameLabel => 'Name';

  @override
  String get descriptionLabel => 'Description (optional)';

  @override
  String get settings => 'Settings';

  @override
  String get modelConfig => 'Model Configuration';

  @override
  String get modelConfigSubtitle => 'Manage LLM and Embedding models';

  @override
  String get teamMembers => 'Team Members';

  @override
  String get teamMembersSubtitle => 'Manage workspace members and permissions';

  @override
  String get accountInfo => 'Account Info';

  @override
  String get unknown => 'Unknown';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeSystem => 'System';

  @override
  String get developerMode => 'Developer Mode';

  @override
  String get devModeOn => 'Enabled — showing debug tools';

  @override
  String get devModeOff => 'Enable to view logs, API requests and debug info';

  @override
  String get debugLog => 'Debug Log';

  @override
  String get debugLogSubtitle => 'View runtime logs and API request records';

  @override
  String get runtimeEnv => 'Runtime Environment';

  @override
  String get envInfoCopied => 'Environment info copied';

  @override
  String get checkUpdate => 'Check for Updates';

  @override
  String currentVersion(String version) {
    return 'Current version v$version';
  }

  @override
  String get about => 'About';

  @override
  String get alreadyLatest => 'You are on the latest version';

  @override
  String checkUpdateFailed(String error) {
    return 'Update check failed: $error';
  }

  @override
  String get debugLogTitle => 'Debug Log';

  @override
  String get clearLog => 'Clear';

  @override
  String get noLogs => 'No logs yet';

  @override
  String get logCopied => 'Logs copied to clipboard';

  @override
  String get copyAll => 'Copy All';

  @override
  String get close => 'Close';

  @override
  String get accountInfoTitle => 'Account Info';

  @override
  String get username => 'Username';

  @override
  String get email => 'Email';

  @override
  String get role => 'Role';

  @override
  String get aboutTrustRAG => 'About TrustRAG';

  @override
  String get trustragDescription =>
      'TrustRAG - Trustworthy RAG Knowledge Workbench';

  @override
  String get version => 'Version';

  @override
  String get backend => 'Backend';

  @override
  String get frontend => 'Frontend';

  @override
  String get database => 'Database';

  @override
  String get storage => 'Storage';

  @override
  String get aboutDescription =>
      'AI-powered Q&A with citation traceability, built on Retrieval-Augmented Generation (RAG) technology.';

  @override
  String get logout => 'Log Out';

  @override
  String get newVersionFound => 'New Version Available';

  @override
  String get releaseNotes => 'Release Notes';

  @override
  String get skipThisVersion => 'Skip This Version';

  @override
  String get remindLater => 'Remind Me Later';

  @override
  String get goToDownload => 'Download';

  @override
  String cannotOpenLink(String error) {
    return 'Cannot open link: $error';
  }

  @override
  String get inviteMember => 'Invite Member';

  @override
  String get emailAddress => 'Email address';

  @override
  String get roleLabel => 'Role';

  @override
  String get viewer => 'Viewer';

  @override
  String get editor => 'Editor';

  @override
  String get owner => 'Owner';

  @override
  String get admin => 'Admin';

  @override
  String get invite => 'Invite';

  @override
  String invited(String email) {
    return 'Invited $email';
  }

  @override
  String inviteFailed(String error) {
    return 'Invite failed: $error';
  }

  @override
  String get changeRole => 'Change Role';

  @override
  String changeRoleTitle(String name) {
    return 'Change role for $name';
  }

  @override
  String changeRoleFailed(String error) {
    return 'Change failed: $error';
  }

  @override
  String get removeMember => 'Remove Member';

  @override
  String removeMemberConfirm(String name) {
    return 'Remove $name from workspace?';
  }

  @override
  String get remove => 'Remove';

  @override
  String removeFailed(String error) {
    return 'Remove failed: $error';
  }

  @override
  String get ownerPermission => 'Full control, can manage members and settings';

  @override
  String get editorPermission => 'Can edit documents and chats, manage members';

  @override
  String get viewerPermission => 'Can only view documents and chats';

  @override
  String get memberManagement => 'Member Management';

  @override
  String memberManagementWithWs(String name) {
    return 'Member Management — $name';
  }

  @override
  String get noMembers => 'No members yet';

  @override
  String get me => 'Me';

  @override
  String get language => 'Language';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageEn => 'English';

  @override
  String get languageJa => '日本語';
}
