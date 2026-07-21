// 웹(Chrome) 미리보기 전용 drift 워커 진입점.
//
// `web/drift_worker.js`로 컴파일되어 브라우저 탭 간 SQLite 상태를 공유한다.
// Windows 데스크톱 빌드에는 영향 없음(네이티브 경로는 이 파일을 쓰지 않는다).
import 'package:drift/wasm.dart';

void main() {
  WasmDatabase.workerMainForOpen();
}
