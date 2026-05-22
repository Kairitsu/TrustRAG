// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class SKo extends S {
  SKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'TrustRAG';

  @override
  String get navChat => '채팅';

  @override
  String get navDocuments => '문서';

  @override
  String get navReview => '검토';

  @override
  String get navWorkspaces => '워크스페이스';

  @override
  String get navSearch => '검색';

  @override
  String get navSettings => '설정';

  @override
  String get selectWorkspaceFirst => '먼저 워크스페이스를 선택하세요';

  @override
  String loadFailed(String error) {
    return '로드 실패: $error';
  }

  @override
  String get newConversation => '새 대화';

  @override
  String get startNewConversation => '새 대화를 시작하세요';

  @override
  String get aiChatDescription => '문서 기반 AI 질의응답';

  @override
  String get noConversations => '대화가 없습니다';

  @override
  String get conversation => '대화';

  @override
  String get today => '오늘';

  @override
  String get yesterday => '어제';

  @override
  String get earlier => '이전';

  @override
  String get inputHint => '질문을 입력하세요...';

  @override
  String get thinking => '생각 중...';

  @override
  String get copy => '복사';

  @override
  String get retry => '재시도';

  @override
  String get edit => '편집';

  @override
  String get copied => '복사됨';

  @override
  String get editMessage => '메시지 편집';

  @override
  String get editMessageHint => '메시지 내용 편집...';

  @override
  String get cancel => '취소';

  @override
  String get resend => '재전송';

  @override
  String citationSources(int count) {
    return '인용 출처 ($count)';
  }

  @override
  String aiError(String error) {
    return 'AI 오류: $error';
  }

  @override
  String sendFailed(String error) {
    return '전송 실패: $error';
  }

  @override
  String get switchWorkspace => '워크스페이스 전환';

  @override
  String get documents => '문서';

  @override
  String get uploadDocument => '문서 업로드';

  @override
  String get selectItems => '선택';

  @override
  String selectedCount(int count) {
    return '$count개 선택됨';
  }

  @override
  String get batchDelete => '일괄 삭제';

  @override
  String batchDeleteConfirm(int count) {
    return '$count개 문서를 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.';
  }

  @override
  String get batchDeleteDone => '일괄 삭제 완료';

  @override
  String uploadSuccessCount(int count) {
    return '$count개 파일 업로드 성공';
  }

  @override
  String get delete => '삭제';

  @override
  String get noDocuments => '문서가 없습니다';

  @override
  String get desktopUploadHint =>
      '\"문서 업로드\"를 클릭하여 PDF, TXT, MD 또는 HTML 파일을 추가하세요';

  @override
  String get serverUploadHint => '\"문서 업로드\"를 클릭하여 PDF, DOCX 또는 TXT 파일을 추가하세요';

  @override
  String get desktopFormatTooltip =>
      '데스크톱 모드는 TXT/MD/HTML/PDF를 지원합니다\nDOCX는 서버 모드가 필요합니다';

  @override
  String get desktopDocxWarning =>
      '데스크톱 모드에서는 DOCX 파싱을 지원하지 않습니다. 서버 모드를 이용하세요';

  @override
  String folderEmpty(String folder) {
    return '\"$folder\" 폴더에 문서가 없습니다';
  }

  @override
  String chunkCount(int count) {
    return '$count개 청크';
  }

  @override
  String get moveToFolder => '폴더로 이동';

  @override
  String get all => '전체';

  @override
  String get newFolder => '새 폴더';

  @override
  String get folderName => '폴더 이름';

  @override
  String get create => '생성';

  @override
  String get moveToFolderTitle => '폴더로 이동';

  @override
  String currentFolder(String name) {
    return '현재 폴더: $name';
  }

  @override
  String get selectExistingFolder => '기존 폴더 선택:';

  @override
  String get noFolder => '폴더 없음';

  @override
  String get orEnterNewFolder => '또는 새 폴더 입력:';

  @override
  String get enterFolderName => '폴더 이름 입력:';

  @override
  String get newFolderName => '새 폴더 이름';

  @override
  String get confirm => '확인';

  @override
  String get switchWorkspaceTooltip => '워크스페이스/문서 전환';

  @override
  String get switchLabel => '전환';

  @override
  String get statusReady => '준비 완료';

  @override
  String get statusProcessing => '처리 중';

  @override
  String get statusChunking => '분할 중';

  @override
  String get statusEmbedding => '벡터화 중';

  @override
  String get statusFailed => '실패';

  @override
  String get statusPending => '대기 중';

  @override
  String get reviewRecords => '검토 기록';

  @override
  String get refresh => '새로고침';

  @override
  String get noReviews => '검토 기록이 없습니다';

  @override
  String get noReviewsDescription => '대화에서 AI 인용을 검토하면 여기에 기록이 표시됩니다';

  @override
  String correction(String text) {
    return '수정';
  }

  @override
  String citationId(String id) {
    return '인용 ID: $id...';
  }

  @override
  String get statusApproved => '승인';

  @override
  String get statusRejected => '거부';

  @override
  String get statusFlagged => '의심';

  @override
  String get statusPendingReview => '대기';

  @override
  String get workspaces => '워크스페이스';

  @override
  String get createNew => '새로 만들기';

  @override
  String get noWorkspaces => '워크스페이스가 없습니다';

  @override
  String get createFirstWorkspace => '첫 번째 워크스페이스를 만드세요';

  @override
  String get noDescription => '설명 없음';

  @override
  String get createWorkspace => '워크스페이스 생성';

  @override
  String get nameLabel => '이름';

  @override
  String get descriptionLabel => '설명 (선택사항)';

  @override
  String get settings => '설정';

  @override
  String get modelConfig => '모델 설정';

  @override
  String get modelConfigSubtitle => 'LLM 및 임베딩 모델 관리';

  @override
  String get teamMembers => '팀 멤버';

  @override
  String get teamMembersSubtitle => '워크스페이스 멤버 및 권한 관리';

  @override
  String get accountInfo => '계정 정보';

  @override
  String get unknown => '알 수 없음';

  @override
  String get appearance => '외관';

  @override
  String get themeLight => '라이트';

  @override
  String get themeDark => '다크';

  @override
  String get themeSystem => '시스템 설정';

  @override
  String get developerMode => '개발자 모드';

  @override
  String get devModeOn => '활성화됨 — 디버그 도구 표시';

  @override
  String get devModeOff => '활성화하면 로그, API 요청 등 디버그 정보를 확인할 수 있습니다';

  @override
  String get debugLog => '디버그 로그';

  @override
  String get debugLogSubtitle => '런타임 로그 및 API 요청 기록 보기';

  @override
  String get runtimeEnv => '실행 환경';

  @override
  String get envInfoCopied => '환경 정보가 복사되었습니다';

  @override
  String get checkUpdate => '업데이트 확인';

  @override
  String currentVersion(String version) {
    return '현재 버전 v$version';
  }

  @override
  String get about => '정보';

  @override
  String get alreadyLatest => '최신 버전입니다';

  @override
  String checkUpdateFailed(String error) {
    return '업데이트 확인 실패: $error';
  }

  @override
  String get debugLogTitle => '디버그 로그';

  @override
  String get clearLog => '지우기';

  @override
  String get noLogs => '로그가 없습니다';

  @override
  String get logCopied => '로그가 클립보드에 복사되었습니다';

  @override
  String get copyAll => '전체 복사';

  @override
  String get close => '닫기';

  @override
  String get accountInfoTitle => '계정 정보';

  @override
  String get username => '사용자 이름';

  @override
  String get email => '이메일';

  @override
  String get role => '역할';

  @override
  String get aboutTrustRAG => 'TrustRAG 정보';

  @override
  String get trustragDescription => 'TrustRAG - 신뢰할 수 있는 RAG 지식 워크벤치';

  @override
  String get version => '버전';

  @override
  String get backend => '백엔드';

  @override
  String get frontend => '프론트엔드';

  @override
  String get database => '데이터베이스';

  @override
  String get storage => '스토리지';

  @override
  String get aboutDescription =>
      '검색 증강 생성(RAG) 기술 기반의 인용 추적이 가능한 신뢰할 수 있는 AI 질의응답.';

  @override
  String get logout => '로그아웃';

  @override
  String get newVersionFound => '새 버전 발견';

  @override
  String get releaseNotes => '릴리스 노트';

  @override
  String get skipThisVersion => '이 버전 건너뛰기';

  @override
  String get remindLater => '나중에 알림';

  @override
  String get goToDownload => '다운로드';

  @override
  String cannotOpenLink(String error) {
    return '링크를 열 수 없습니다: $error';
  }

  @override
  String get inviteMember => '멤버 초대';

  @override
  String get emailAddress => '이메일 주소';

  @override
  String get roleLabel => '역할';

  @override
  String get viewer => '뷰어';

  @override
  String get editor => '편집자';

  @override
  String get owner => '소유자';

  @override
  String get admin => '관리자';

  @override
  String get invite => '초대';

  @override
  String invited(String email) {
    return '$email을(를) 초대했습니다';
  }

  @override
  String inviteFailed(String error) {
    return '초대 실패: $error';
  }

  @override
  String get changeRole => '역할 변경';

  @override
  String changeRoleTitle(String name) {
    return '$name의 역할 변경';
  }

  @override
  String changeRoleFailed(String error) {
    return '변경 실패: $error';
  }

  @override
  String get removeMember => '멤버 삭제';

  @override
  String removeMemberConfirm(String name) {
    return '$name을(를) 워크스페이스에서 삭제하시겠습니까?';
  }

  @override
  String get remove => '삭제';

  @override
  String removeFailed(String error) {
    return '삭제 실패: $error';
  }

  @override
  String get ownerPermission => '전체 제어 권한, 멤버 및 설정 관리 가능';

  @override
  String get editorPermission => '문서 및 채팅 편집, 멤버 관리 가능';

  @override
  String get viewerPermission => '문서 및 채팅 열람만 가능';

  @override
  String get memberManagement => '멤버 관리';

  @override
  String memberManagementWithWs(String name) {
    return '멤버 관리 — $name';
  }

  @override
  String get noMembers => '멤버가 없습니다';

  @override
  String get me => '나';

  @override
  String get language => '언어';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageEn => 'English';

  @override
  String get languageJa => '日本語';

  @override
  String get languageKo => '한국어';

  @override
  String get navKnowledgeGraph => '그래프';

  @override
  String get knowledgeGraph => '지식 그래프';

  @override
  String knowledgeGraphDesc(String name) {
    return '\"$name\"의 엔티티 및 관계';
  }

  @override
  String get graphView => '관계도';

  @override
  String get entityList => '엔티티 목록';

  @override
  String get noGraphData => '그래프 데이터 없음';

  @override
  String get noGraphDataHint => '문서를 업로드하고 처리하면 지식 그래프가 자동 생성됩니다';

  @override
  String get noEntities => '엔티티 없음';

  @override
  String get searchEntities => '엔티티 이름 또는 유형 검색...';

  @override
  String get entitiesCount => '엔티티';

  @override
  String get typesCount => '유형';

  @override
  String get entityType => '유형';

  @override
  String get relatedEntities => '관련 엔티티';

  @override
  String get nodes => '노드';

  @override
  String get edges => '엣지';

  @override
  String get noReviewRecords => '검토 기록 없음';

  @override
  String get reviewRecordsHint => '대화에서 AI 인용을 검토하면 여기에 기록이 표시됩니다';

  @override
  String get exportReport => '보고서 내보내기';

  @override
  String get reviewReport => '검토 보고서';

  @override
  String get generating => '생성 중...';

  @override
  String reportGeneratedAt(String time) {
    return '생성 시간: $time';
  }

  @override
  String get totalCitations => '총 인용 수';

  @override
  String get reviewed => '검토 완료';

  @override
  String get unreviewedCount => '미검토';

  @override
  String get reviewCoverage => '검토 커버리지';

  @override
  String get approvalRate => '승인율';

  @override
  String get rejectionRate => '거부율';

  @override
  String get hallucinationRate => '환각률';

  @override
  String get keyMetrics => '주요 지표';

  @override
  String get reviewResults => '검토 결과';

  @override
  String get reviewDetails => '검토 상세';

  @override
  String get approved => '승인';

  @override
  String get rejected => '거부';

  @override
  String get flagged => '의심';

  @override
  String get pending => '대기';

  @override
  String get document => '문서';

  @override
  String get section => '섹션';

  @override
  String get page => '페이지';

  @override
  String get quote => '인용';

  @override
  String get copyMarkdown => 'Markdown 복사';

  @override
  String get copiedToClipboard => '클립보드에 복사되었습니다';

  @override
  String get reportLoadFailed => '보고서 생성 실패';

  @override
  String get overview => '개요';

  @override
  String get personalSpace => '개인 공간';

  @override
  String get teamSpace => '팀 공간';

  @override
  String get createTeam => '팀 만들기';

  @override
  String get joinTeam => '팀 참가';

  @override
  String get teamName => '팀 이름';

  @override
  String get teamDescription => '팀 설명 (선택)';

  @override
  String get inviteCode => '초대 코드';

  @override
  String get enterInviteCode => '8자리 초대 코드 입력';

  @override
  String get joinButton => '참가';

  @override
  String teamCreated(Object name, Object code) {
    return '팀 \"$name\" 생성 완료! 초대 코드: $code';
  }

  @override
  String joinedTeam(Object name) {
    return '팀 \"$name\"에 참가했습니다!';
  }

  @override
  String get joinFailed => '참가 실패. 초대 코드를 확인해주세요.';

  @override
  String get teamSettings => '팀 설정';

  @override
  String manageTeam(Object name) {
    return '\"$name\" 팀 관리';
  }

  @override
  String get regenerateInviteCode => '초대 코드 재생성';

  @override
  String get regenerateConfirm => '재생성 시 기존 초대 코드가 무효화됩니다. 계속하시겠습니까?';

  @override
  String newInviteCode(Object code) {
    return '새 초대 코드: $code';
  }

  @override
  String get copyInviteCode => '초대 코드 복사';

  @override
  String get inviteCodeCopied => '초대 코드가 복사되었습니다';

  @override
  String get shareInvite => '초대 공유';

  @override
  String get shareInviteSubtitle => '팀 멤버에게 초대 코드 보내기';

  @override
  String inviteMessage(Object name, Object code) {
    return 'TrustRAG 팀 \"$name\"에 참가하세요\n초대 코드: $code';
  }

  @override
  String get inviteInfoCopied => '초대 정보가 클립보드에 복사되었습니다';

  @override
  String get memberManagementSubtitle => '팀 멤버 보기 및 관리';

  @override
  String get transferOwnership => '소유권 이전';

  @override
  String get transferOwnershipDesc => '팀 소유권을 다른 멤버에게 이전';

  @override
  String get goToMemberManagement => '멤버 관리로 이동';

  @override
  String get disbandTeam => '팀 해체';

  @override
  String get disbandTeamDesc => '팀과 모든 데이터를 영구 삭제';

  @override
  String get disbandWarning =>
      '이 작업은 되돌릴 수 없습니다! 팀의 모든 문서, 대화, 검토 기록이 영구 삭제됩니다.';

  @override
  String disbandConfirmPrompt(Object name) {
    return '확인을 위해 팀 이름 \"$name\"을(를) 입력하세요:';
  }

  @override
  String get confirmDisband => '해체 확인';

  @override
  String get teamNameMismatch => '팀 이름이 일치하지 않습니다';

  @override
  String get teamDisbanded => '팀이 해체되었습니다';

  @override
  String disbandFailed(Object error) {
    return '해체 실패: $error';
  }

  @override
  String get roleOwner => '소유자';

  @override
  String get roleAdmin => '관리자';

  @override
  String get roleEditor => '편집자';

  @override
  String get roleViewer => '뷰어';

  @override
  String get roleOwnerDesc => '모든 권한, 멤버·설정·API 설정 관리';

  @override
  String get roleAdminDesc => '멤버, LLM 설정, API 키 관리';

  @override
  String get roleEditorDesc => '문서 및 대화 편집';

  @override
  String get roleViewerDesc => '문서 및 대화 열람, 검토 제출';

  @override
  String get team => '팀';

  @override
  String get collapseSidebar => '사이드바 접기';

  @override
  String get expandSidebar => '사이드바 펼치기';
}
