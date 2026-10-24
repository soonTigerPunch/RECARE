# 1.1.1 기존 서명키 재배포

2026-10-24 · 사용자 요청에 따른 APK 교체.

## 원인과 조치

GitHub CI가 별도의 Android Debug 인증서를 생성해 기존 PC의 1.0.3과 서명이 달랐다. 전달받은 RECARE-main.zip은 GitHub v1.1.1-mvp의 소스 커밋 `68c65892c64c9cb9e74287e5008fa0e243f8c0f5`와 텍스트 줄바꿈을 제외하고 일치했다. 해당 소스를 별도 빌드 폴더에서 기존 PC 키로 release 빌드했다. 앱 기능·버전·스키마 코드는 변경하지 않았다.

| 항목 | 결과 |
| --- | --- |
| 앱 ID | com.detabev.recare |
| 버전 | 1.1.1+6 |
| 기존 공개 1.0.3의 versionCode | 4 |
| 기존 1.0.3 및 새 APK 인증서 SHA-256 | `716d350e47cffbd8d0e9d6e790c147f6d05fbd305c81cc0dc2ffeccb4c552991` |
| 이전 CI 1.1.1 인증서 SHA-256 | `28393138386f6b57c1a12764dea90d4cdb48b2b3b270a44db65fddb9ce56104b` |
| 새 APK SHA-256 | `1cc07d8b37bbf063c94f4153508c4f84d35205bba086238fe91fb3f023937b3c` |
| 파일 크기 | 55,067,532 bytes |

기존 1.0.3 설치본에서 업데이트할 수 있는 서명·앱 ID·버전 코드 조건을 확인했다. 실제 기기의 설치와 기록 유지 검증은 하지 않았다. 이전 CI 서명의 1.1.1 설치본은 이번 APK와 서명이 다르므로 해당 설치본까지 업데이트 호환되는 것은 아니다.

## 검증

- `flutter pub get --enforce-lockfile` 및 정적 분석 통과.
- Flutter 테스트 122개, Kotlin 알림 정책 14개, 실제 알림 SQL fixture 6개 통과.
- 최초 Windows 검사에서는 실행 취소 후 DB 복원은 완료됐지만 UI 갱신 전 검사해 실패했다. `test/usability_widget_test.dart`에서 기존 페이지의 존재만 확인하지 않고 실행 취소 완료 메시지를 기다리도록 보완했다. 단독 재현 실패 → 대기 보완 후 단독·전체 테스트 통과를 확인했다.
- release APK의 서명 검증, 기존 1.0.3과 인증서 비교, 앱 ID·버전 코드·최소 SDK 확인.

## 배포

[v1.1.1-mvp](https://github.com/soonTigerPunch/RECARE/releases/tag/v1.1.1-mvp)의 `RECARE-1.1.1-android.apk`와 `SHA256SUMS.txt`를 교체했다. 업로드한 파일의 SHA-256·크기 일치와 인증 없는 공개 다운로드를 확인했다. 기존 CI APK는 교체 전 로컬에 보관했다. 키 파일이나 비밀번호는 저장소·릴리스에 포함하지 않는다. 일반 CI는 기존 PC 키가 없으므로 같은 서명을 자동으로 재현하지 못한다.
