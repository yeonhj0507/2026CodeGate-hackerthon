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
  });

  final bool inProgress;
  final DateTime? lastSyncedAt;
  final Recommendations recommendations;
  final AppException? error;

  /// 직전 동기화로 늘어난 노드 수(스낵바 안내용).
  final int? addedNodeCount;

  SyncState copyWith({
    bool? inProgress,
    DateTime? lastSyncedAt,
    Recommendations? recommendations,
    AppException? error,
    int? addedNodeCount,
    bool clearError = false,
  }) {
    return SyncState(
      inProgress: inProgress ?? this.inProgress,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      recommendations: recommendations ?? this.recommendations,
      error: clearError ? null : (error ?? this.error),
      addedNodeCount: addedNodeCount ?? this.addedNodeCount,
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
        clearError: true,
      );
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

/// 그래프에서 사용자가 선택한 노드. null이면 상세 패널을 닫는다.
final selectedNodeIdProvider = StateProvider<String?>((ref) => null);

// ── 탐색 탭 ────────────────────────────────────────────────────────────────

/// 탐색용으로 고른 키워드(노드 id). 2~3개를 묶어 "더 탐색하기"에 넘긴다.
final exploreSelectionProvider =
    StateProvider<Set<String>>((ref) => <String>{});

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
