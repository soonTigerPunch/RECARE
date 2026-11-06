# Android 업데이트 서명

기존 앱 ID: `com.detabev.recare`. 기존 공개 1.1.1은 versionCode 6이며 다음 테스트 빌드는 1.2.0+7이다.
기존 설치 기기 자체는 연결되지 않았으므로 공개 APK와 비교한다.

필수 인증서 SHA-256:
`716d350e47cffbd8d0e9d6e790c147f6d05fbd305c81cc0dc2ffeccb4c552991`

업데이트용 원본 서명키는 소유자가 비공개로 관리한다.
파일명은 같아도 다른 PC의 debug.keystore는 다른 키다. 키를 생성하거나 덮어쓰지 않는다.
빌드 환경에 기본으로 있는 키는 인증서가 다를 수 있으므로 지문을 확인한다.

원본을 안전한 비공개 경로로 전달받은 뒤, Git에서 제외된 android/key.properties에 다음 항목을 설정한다.
storeFile은 원본 파일의 절대 경로(Windows는 C:/Users/... 형태)를 사용한다.
실제 암호는 채팅·명령 출력·GitHub에 넣지 않는다.

```properties
storeFile=/private/path/original.keystore
storePassword=LOCAL_ONLY
keyAlias=LOCAL_ONLY
keyPassword=LOCAL_ONLY
```

release Gradle 빌드는 설정 누락, 파일 누락, 인증서 불일치 시 중단한다.
debug 키로 자동 대체하지 않는다. 원본 키가 없는 GitHub CI의 release 빌드도 중단되는 것이 정상이다.
키가 준비되면 다음 명령으로 생성한 APK의 인증서를 다시 검증한다.

```sh
flutter build apk --release --dart-define-from-file=config/recipe.public.json
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
aapt dump badging build/app/outputs/flutter-apk/app-release.apk
```

인증서와 앱 ID 일치 및 versionCode 증가를 확인한 APK만 테스트 릴리스에 올린다.
설치 실패 시 INSTALL_FAILED_UPDATE_INCOMPATIBLE은 서명 문제,
INSTALL_FAILED_VERSION_DOWNGRADE는 버전 코드 문제로 구분한다. 앱 삭제·데이터 초기화를 요구하지 않는다.
