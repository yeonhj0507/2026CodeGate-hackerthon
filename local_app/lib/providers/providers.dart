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

/// 그래프에서 사용자가 선택한 노드. null이면 상세 패널을 닫는다.
final selectedNodeIdProvider = StateProvider<String?>((ref) => null);
