import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_exception.dart';
import '../core/config.dart';
import '../data/api/api_client.dart';
import '../data/api/dio_api_client.dart';
import '../data/api/mock_api_client.dart';
import '../data/api/token_store.dart';
import '../data/db/database.dart';
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

/// 그래프에서 사용자가 선택한 노드. null이면 뇌지도 위 상세 카드를 닫는다.
///
/// 오직 "그래프 위 노드 상세 카드" 표시에만 쓰인다 — 도킹 패널 모드 전환이나
/// 탐색 탭 키워드 선택과는 완전히 독립적이다([exploreKeywordProvider] 참고).
final selectedNodeIdProvider = StateProvider<String?>((ref) => null);

/// 우측 도킹 패널이 지금 보여주는 화면(명세 밖, Figma 시안 §S1~S3).
/// [closed]는 패널이 접혀 있는 상태 — 앱 진입 시 기본값이라 세 아이콘 중
/// 아무것도 활성 표시되지 않는다.
enum RightPanelMode { closed, recommendations, explore, archive }

/// 우측 도킹 패널 모드. 기본값은 [RightPanelMode.closed].
final rightPanelModeProvider =
    StateProvider<RightPanelMode>((ref) => RightPanelMode.closed);

/// 추천 탭에서 지금 인라인으로 펼쳐 보여주는 개념 상세. null이면 목록만 보인다.
///
/// 그래프 선택([selectedNodeIdProvider])과는 별개다 — 추천 탭에서 개념을 눌러도
/// 패널이 "탐색" 탭으로 넘어가면 안 되기 때문에 독립된 상태로 둔다.
final inlineConceptDetailProvider = StateProvider<String?>((ref) => null);

/// "탐색" 탭에서 고른 키워드(그래프 노드 id) 목록. 최대 5개까지만 담긴다.
///
/// 그래프 노드 클릭([selectedNodeIdProvider])과는 완전히 독립된 액션이다 —
/// 그래프 클릭(탭)은 노드 상세 카드만 열고, 탐색 키워드는 뇌지도에서 노드를
/// 길게 눌러 끌어다(드래그) 탐색 탭의 드롭 영역에 놓아야 채워진다.
final exploreKeywordProvider = StateProvider<List<String>>((ref) => const []);

/// "더 탐색하기"를 눌러 결과(설명·추천 기사)를 펼쳤는지 여부.
/// 키워드 선택이 바뀌면 다시 접어서, 매번 버튼을 눌러야 결과가 보이게 한다.
final exploreRevealedProvider = StateProvider<bool>((ref) => false);
