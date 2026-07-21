import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_exception.dart';
import '../core/config.dart';
import '../data/api/api_client.dart';
import '../data/api/dio_api_client.dart';
import '../data/api/mock_api_client.dart';
import '../data/api/token_store.dart';
import '../data/db/database.dart';
import '../data/dto/explore.dart';
import '../data/dto/graph.dart';
import '../data/dto/recommendation.dart';
import '../data/repository/auth_repository.dart';
import '../data/repository/thoughtmap_repository.dart';
import '../data/xp/xp_rules.dart';

// ── 인프라 ──────────────────────────────────────────────────

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// `AppConfig.useMock` 하나로 Mock/실서버가 갈린다.
/// 실서버 전환: `--dart-define=USE_MOCK=false`
final apiClientProvider = Provider<ApiClient>((ref) {
  if (AppConfig.useMock) return MockApiClient();
  return DioApiClient(tokenStore: ref.watch(tokenStoreProvider));
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(apiClientProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  );
});

final thoughtmapRepositoryProvider = Provider<ThoughtmapRepository>((ref) {
  return ThoughtmapRepository(
    api: ref.watch(apiClientProvider),
    db: ref.watch(databaseProvider),
  );
});

// ── 인증 상태 ───────────────────────────────────────────────

class AuthState {
  const AuthState({this.signedIn = false, this.email});

  final bool signedIn;
  final String? email;
}

class AuthController extends StateNotifier<AsyncValue<AuthState>> {
  AuthController(this._repo) : super(const AsyncValue.loading()) {
    _restore();
  }

  final AuthRepository _repo;

  /// 앱 시작 시 저장된 토큰으로 세션을 복원한다.
  Future<void> _restore() async {
    try {
      state = AsyncValue.data(AuthState(signedIn: await _repo.hasSession()));
    } catch (_) {
      state = const AsyncValue.data(AuthState());
    }
  }

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      await _repo.login(email, password);
      state = AsyncValue.data(AuthState(signedIn: true, email: email));
    } on AppException catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> signup(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      await _repo.signup(email, password);
      await _repo.login(email, password);
      state = AsyncValue.data(AuthState(signedIn: true, email: email));
    } on AppException catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AsyncValue.data(AuthState());
  }

  /// 401을 만났을 때 세션만 끊는다(에러 표시는 호출부 담당).
  Future<void> invalidateSession() async {
    await _repo.logout();
    state = const AsyncValue.data(AuthState());
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<AuthState>>((ref) {
  return AuthController(ref.watch(authRepositoryProvider));
});

// ── 그래프 / 동기화 ─────────────────────────────────────────

/// 로컬 SQLite의 그래프 원본. 동기화가 DB를 갱신하면 자동으로 흘러나온다.
final graphProvider = StreamProvider<Graph>((ref) {
  return ref.watch(thoughtmapRepositoryProvider).watchLocalGraph();
});

class SyncState {
  const SyncState({
    this.inProgress = false,
    this.lastSyncedAt,
    this.recommendations = Recommendations.empty,
    this.error,
    this.addedNodeCount,
    this.xpGained = 0,
  });

  final bool inProgress;
  final DateTime? lastSyncedAt;
  final Recommendations recommendations;
  final AppException? error;

  /// 직전 동기화로 늘어난 노드 수(스낵바 안내용).
  final int? addedNodeCount;

  /// 직전 동기화로 받은 XP(스낵바 안내용).
  final int xpGained;

  SyncState copyWith({
    bool? inProgress,
    DateTime? lastSyncedAt,
    Recommendations? recommendations,
    AppException? error,
    int? addedNodeCount,
    int? xpGained,
    bool clearError = false,
  }) {
    return SyncState(
      inProgress: inProgress ?? this.inProgress,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      recommendations: recommendations ?? this.recommendations,
      error: clearError ? null : (error ?? this.error),
      addedNodeCount: addedNodeCount ?? this.addedNodeCount,
      xpGained: xpGained ?? this.xpGained,
    );
  }
}

/// 동기화 컨트롤러.
///
/// 트리거는 명세 §5.2에 따라 **딱 두 가지**다: 앱 실행 시 최초 1회 자동,
/// 그리고 "내 이력 가져오기" 수동 클릭. 실시간 폴링은 하지 않는다.
class SyncController extends StateNotifier<SyncState> {
  SyncController(this._repo, this._ref) : super(const SyncState());

  final ThoughtmapRepository _repo;
  final Ref _ref;

  /// 앱 실행 후 자동 동기화를 이미 수행했는지. 세션당 1회로 제한한다.
  bool _autoSyncDone = false;

  Future<void> syncOnLaunch() async {
    if (_autoSyncDone) return;
    _autoSyncDone = true;
    await sync();
  }

  Future<void> sync() async {
    if (state.inProgress) return;
    state = state.copyWith(inProgress: true, clearError: true);
    try {
      final result = await _repo.sync();
      state = state.copyWith(
        inProgress: false,
        lastSyncedAt: result.syncedAt,
        recommendations: result.recommendations,
        addedNodeCount: result.addedNodeCount,
        xpGained: result.xpGained,
        clearError: true,
      );
      // 동기화가 XP를 적립했으므로 배지를 다시 읽는다(raw SQL 테이블이라
      // drift 스트림이 자동으로 흘려주지 않는다).
      await _ref.read(xpProvider.notifier).refresh();
    } on AppException catch (e) {
      state = state.copyWith(inProgress: false, error: e);
      if (e.isUnauthorized) {
        // 토큰 만료 → 로그인 화면으로 되돌린다(명세 §3.5).
        await _ref.read(authControllerProvider.notifier).invalidateSession();
      }
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final syncControllerProvider =
    StateNotifierProvider<SyncController, SyncState>((ref) {
  return SyncController(ref.watch(thoughtmapRepositoryProvider), ref);
});

/// 그래프에서 사용자가 선택한 노드. null이면 상세를 닫는다.
///
/// 지도 위 노드를 **탭**했을 때만 바뀐다. 탐색 키워드 담기([exploreKeywordProvider])
/// 와는 완전히 독립이다 — 지도를 둘러보다 키워드가 저절로 쌓이면 안 된다.
final selectedNodeIdProvider = StateProvider<String?>((ref) => null);

// ── 우측 패널 ──────────────────────────────────────────────────────────────

/// 우측 도킹 패널이 지금 보여주는 화면.
///
/// [closed]는 접힌 상태이고 앱 진입 시 기본값이다 — 처음엔 지도를 넓게 보여주고,
/// 사용자가 아이콘을 눌러야 패널이 열린다.
enum RightPanelMode { closed, recommendations, explore, archive }

final rightPanelModeProvider =
    StateProvider<RightPanelMode>((ref) => RightPanelMode.closed);

/// 추천 탭에서 지금 인라인으로 펼친 개념 상세. null이면 목록만 보인다.
///
/// [selectedNodeIdProvider]와 별개로 둔다. 추천 목록에서 개념을 눌렀다고 해서
/// 지도 선택이나 패널 모드가 따라 움직이면 안 되기 때문이다.
final inlineConceptDetailProvider = StateProvider<String?>((ref) => null);

// ── 경험치 ────────────────────────────────────────────────────────────────

/// XP 현황. 적립은 동기화·앱 실행에서만 일어나므로 그때마다 [refresh]로 당긴다.
class XpController extends StateNotifier<XpSnapshot> {
  XpController(this._repo) : super(XpSnapshot.empty) {
    refresh();
  }

  final ThoughtmapRepository _repo;

  Future<void> refresh() async {
    final snapshot = await _repo.loadXp();
    if (mounted) state = snapshot;
  }

  /// 앱 실행 시 1회. 오늘 첫 접속이면 스트릭 XP가 붙는다.
  Future<void> registerVisit() async {
    await _repo.registerVisit();
    await refresh();
  }
}

final xpProvider = StateNotifierProvider<XpController, XpSnapshot>((ref) {
  return XpController(ref.watch(thoughtmapRepositoryProvider));
});

/// 추천 탭 O/X 정답 처리 — 개념을 이해완료로 올리고 XP를 반영한다.
///
/// 그래프는 drift 스트림을 타고 [graphProvider]로 저절로 흘러나오지만, XP는
/// raw SQL 테이블이라 배지를 직접 당겨야 한다(동기화 경로와 같은 사정).
/// 지급된 이벤트를 돌려주므로 호출부가 "+N XP"를 안내할 수 있다.
Future<List<XpEvent>> solveOxQuiz(WidgetRef ref, String nodeId) async {
  final granted =
      await ref.read(thoughtmapRepositoryProvider).markUnderstoodByOxQuiz(nodeId);
  if (granted.isNotEmpty) await ref.read(xpProvider.notifier).refresh();
  return granted;
}

// ── 탐색 탭 ────────────────────────────────────────────────────────────────

/// 탐색용으로 고른 키워드(노드 id). 2~3개를 묶어 "더 탐색하기"에 넘긴다.
///
/// 지도에서 노드를 **길게 눌러 끌어다** 탐색 패널에 놓으면 채워진다. 순서가 곧
/// 사용자가 담은 순서라 Set 이 아니라 List 다.
final exploreKeywordProvider = StateProvider<List<String>>((ref) => const []);

/// "더 탐색하기"를 눌러 결과를 펼쳤는지 여부.
///
/// 키워드 구성이 바뀌면 다시 접는다. 고른 키워드와 화면에 떠 있는 설명이
/// 어긋난 채로 남지 않게 하려는 것 — 결과는 항상 버튼을 눌러 갱신한다.
final exploreRevealedProvider = StateProvider<bool>((ref) => false);

/// "더 탐색하기" 결과. 요청 전에는 null, 요청 중에는 loading.
class ExploreController extends StateNotifier<AsyncValue<ExploreResult?>> {
  ExploreController(this._api) : super(const AsyncValue.data(null));

  final ApiClient _api;

  Future<void> run(List<GraphNode> nodes) async {
    if (nodes.isEmpty) return;
    state = const AsyncValue.loading();
    try {
      final result = await _api.explore(ExploreRequest(
        conceptIds: nodes.map((n) => n.id).toList(),
        conceptTags: nodes.map((n) => n.concept).toList(),
      ));
      state = AsyncValue.data(result);
    } on AppException catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void clear() => state = const AsyncValue.data(null);
}

final exploreControllerProvider =
    StateNotifierProvider<ExploreController, AsyncValue<ExploreResult?>>((ref) {
  return ExploreController(ref.watch(apiClientProvider));
});

// ── 보관함 ────────────────────────────────────────────────────────────────

/// 열람한 기사 1건 — 그래프에서 역산한다(서버 왕복 없음).
class LibraryEntry {
  const LibraryEntry({
    required this.article,
    required this.concepts,
  });

  final SourceArticle article;

  /// 이 기사에서 학습한 개념들.
  final List<GraphNode> concepts;

  int get understoodCount => concepts.where((n) => n.isUnderstood).length;
}

/// 보관함 목록. **서버 엔드포인트가 아니라 로컬 그래프에서 뽑는다**(명세 §4.5 —
/// 학습 데이터는 로컬이 원본이고, 서버는 스크랩을 동기화 시 소비·삭제한다).
final libraryProvider = Provider<List<LibraryEntry>>((ref) {
  final graph = ref.watch(graphProvider).valueOrNull ?? Graph.empty;

  final byKey = <String, List<GraphNode>>{};
  final articleOf = <String, SourceArticle>{};
  for (final node in graph.nodes) {
    for (final article in node.sourceArticles) {
      final key = article.url.isNotEmpty ? article.url : article.title;
      if (key.isEmpty) continue;
      byKey.putIfAbsent(key, () => []).add(node);
      // URL 이 있는 쪽을 대표로 둔다(구형 데이터가 섞여도 링크를 살린다).
      final known = articleOf[key];
      if (known == null || (known.url.isEmpty && article.url.isNotEmpty)) {
        articleOf[key] = article;
      }
    }
  }

  final entries = [
    for (final entry in byKey.entries)
      LibraryEntry(article: articleOf[entry.key]!, concepts: entry.value),
  ];
  // 많이 배운 기사가 위로.
  entries.sort((a, b) => b.concepts.length.compareTo(a.concepts.length));
  return entries;
});
