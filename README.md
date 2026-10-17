# RE:CARE

서버 없이 기기 내 SQLite로 식재료 재고와 폐기 금액을 기록하는 Flutter MVP입니다.

새 식재료 등록에서 이름을 입력하면 대표 이미지와 함께 기본 목록·이전 등록 이력을 제안합니다. 선택하면 이름과 수량·단위를 채우며 소비기한과 실제 구매금액은 새로 입력합니다. 검색은 기기 안에서 처리합니다. 자세한 범위는 [자동완성 안내](docs/AUTOCOMPLETE.md)를 참고하세요.

홈에서 이번 주 폐기금액과 임박 재료를 확인하고, 목록에서 식재료 상세·수정·삭제로 이동합니다. 먹음·폐기 처리는 전부·절반·1/3·1/4 또는 직접 입력으로 수량을 지정합니다. 구매금액 미입력과 0원을 구분하며 부분 처리 금액을 정확히 계산합니다.

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --debug
```

처리 기록이 없는 식재료만 삭제할 수 있습니다. 처리 기록이 있는 재료는 이력을 보존하며 남은 수량을 먹음·폐기로 처리합니다. 설정에서 시스템·라이트·다크 모드와 처리 완료 항목 표시 여부를 변경할 수 있으며 재실행 후에도 유지됩니다. 비율은 현재 남은 재고 기준이며 계산 결과를 저장 전에 확인합니다. 공통 디자인 규칙은 `lib/ui/design_system.dart`에서 관리합니다.

Android 최소 버전은 Android 10(API 29)입니다. APK는 `build/app/outputs/flutter-apk/app-debug.apk`에 생성됩니다.

이전 내용·저장 규칙·백업 정보는 [마이그레이션 문서](docs/MIGRATION.md)를 참고하세요.

## 팀원 다운로드

현재 소스와 공개 테스트 APK는 **1.0.3+4**입니다. 식재료 자동완성과 최신 안내 문구가 포함되어 있습니다.

- [테스트 APK 다운로드](https://github.com/soonTigerPunch/RECARE/releases/tag/v1.0.3-mvp)
- [소스 ZIP 다운로드](https://github.com/soonTigerPunch/RECARE/archive/refs/heads/main.zip)

APK는 Android 10 이상에서 설치할 수 있는 테스트 빌드입니다. 기존 RE:CARE가 설치되어 있다면 업데이트로 설치하세요. 앱을 삭제하면 기기 내 기록도 삭제됩니다.

개발 환경은 Flutter 3.47.6 / Dart 3.13.5입니다. 저장소를 받은 뒤 `flutter pub get`, `flutter test`, `flutter run` 순서로 실행합니다. Android SDK와 사용할 기기 설정은 각 개발자의 환경에 맞게 지정합니다.

## 검증

- 2026-10-17: 자동완성·계산·저장·수정·삭제·수량 선택·설정·화면 흐름 테스트 67건 통과
- `flutter analyze --no-pub` 문제 없음
- 별도 화면 렌더링 테스트 통과, 자동완성 3개를 포함한 13개 캡처 확인
- 1.0.3+4 Android debug APK 빌드 성공
- 이번 버전의 실기기 설치·조작 검사는 미실시. 이전 1.0.2 버전의 연결 기기 업데이트 설치·시작 확인과 구분

[자동완성 제안](docs/screenshots/autocomplete-suggestions.png) · [선택 후 등록](docs/screenshots/autocomplete-selected.png) · [이전 등록 이력](docs/screenshots/autocomplete-history.png)

[홈 화면](docs/screenshots/home.png) · [식재료 목록](docs/screenshots/fridge.png) · [수량 선택](docs/screenshots/processing-dialog.png)

## 개발 변경 기록

Flutter 전환, 기능·디자인·문구 변경, 검증·배포 및 후속 합의는 [개발 변경 기록](docs/DEVELOPMENT_HISTORY.md)에 정리했습니다.
