# iPhone 빌드와 배포

iOS 프로젝트는 Flutter 3.47.6 템플릿으로 생성했습니다. 앱 표시 이름은
**RE:CARE**, 번들 ID는 `com.detabev.recare`, 최소 지원 버전은 **iOS 15.0**입니다.
앱 버전과 빌드 번호는 `pubspec.yaml`을 따릅니다.

현재 저장소에는 Apple 인증서, 프로비저닝 프로파일, 개발 팀 ID가 없습니다.
Linux 작업 공간에서는 Xcode로 iOS 앱을 컴파일하거나 서명할 수 없습니다.
따라서 이 변경 자체가 설치 가능한 IPA나 TestFlight 배포를 제공하지는 않습니다.
iOS 앱 아이콘은 현재 Flutter 템플릿 아이콘이며, 정식 배포 전 교체해야 합니다.

재고/폐기 기록과 SQLite 저장소는 Flutter 코드와 iOS 플러그인을 사용합니다.
예약 알림은 현재 Android에서만 구현되어 있으며 iOS 설정 화면에서는 지원하지
않는다고 표시합니다. iPhone에서 실제 저장/재실행/화면 동작 검증은 별도로 필요합니다.

## macOS에서 빌드 확인

Flutter **3.47.6**, Xcode와 해당 iOS SDK를 설치하고 Xcode 초기 설정 및 라이선스
동의를 완료합니다. 프로젝트 루트에서 실행합니다.

```sh
flutter doctor -v
flutter pub get --enforce-lockfile
flutter build ios --release --no-codesign
```

`build/ios/iphoneos/Runner.app`은 **서명되지 않아 iPhone에 설치할 수 없습니다**.
ZIP 파일 이름을 `.ipa`로 바꾸어도 설치 가능한 앱이 되지 않습니다.

GitHub Actions가 사용 가능한 저장소에서는 **Actions → iOS unsigned compile check
→ Run workflow**로 같은 검증을 실행할 수 있습니다. macOS 실행 시간은 계정의
Actions 사용량에 포함될 수 있습니다. 업로드되는
`RECARE-iOS-UNSIGNED-NOT-INSTALLABLE` 아티팩트는 컴파일 확인용이며 배포 파일이 아닙니다.
2026-10-22 [macOS CI 실행](https://github.com/soonTigerPunch/RECARE/actions/runs/39733875158)에서 release 앱의 서명 없는 컴파일과 산출물 업로드를 확인했습니다. 설치 가능한 IPA나 기기 동작 검증을 의미하지 않습니다.

## 연결된 iPhone에서 개발용 실행

1. Mac에 iPhone을 연결하고 기기 신뢰 및 필요한 개발자 모드를 활성화합니다.
2. `open ios/Runner.xcworkspace`로 Xcode를 엽니다.
3. Runner 타깃의 **Signing & Capabilities**에서 실제 Apple 계정의 Team을 선택하고
   **Automatically manage signing**을 설정합니다. 번들 ID를 해당 팀에 등록할 수
   있어야 합니다. 이미 다른 팀이 소유한 ID라면 고유한 ID로 변경해야 합니다.
4. `flutter devices`로 기기 ID를 확인한 뒤 실행합니다.

```sh
flutter run -d <IPHONE_DEVICE_ID>
```

개인 Apple ID의 무료 개발 서명은 기간과 기능에 제한이 있으며 일반 사용자에게
배포할 수 있는 방식이 아닙니다.

## TestFlight 배포 (권장)

필요 항목: 유료 Apple Developer Program 팀, 해당 팀의 앱 등록 권한,
App Store Connect의 동일 번들 ID 앱 레코드, 유효한 배포 서명 설정입니다.
Apple 로그인 정보나 개인 키는 저장소에 커밋하지 마세요.

1. 위 Xcode Team/번들 ID 설정을 완료하고 배포용 앱 아이콘을 준비합니다.
2. App Store Connect에서 앱 레코드를 만들고 빌드마다 이전에 업로드한 번호보다
   높은 빌드 번호를 사용합니다. 예를 들어 현재 `1.1.1+6` 다음 빌드는:

   ```sh
   flutter build ipa --release --build-name 1.1.1 --build-number 7
   ```

3. 결과 `build/ios/archive/Runner.xcarchive`를 Xcode Organizer에서 열어
   **Validate App**, **Distribute App → App Store Connect → Upload**를 진행합니다.
   또는 서명된 `build/ios/ipa/*.ipa`를 Apple Transporter로 업로드합니다.
4. App Store Connect 처리 및 필요한 수출 규정 질문을 완료하고 TestFlight
   테스터를 추가합니다. 외부 테스트에는 Apple의 베타 심사가 필요할 수 있습니다.
5. 테스터는 TestFlight 앱에서 초대를 수락하고 설치합니다.

## 등록된 기기에 IPA 배포

Ad Hoc 배포에는 유료 개발자 팀, **대상 iPhone UDID가 등록된** 프로비저닝
프로파일과 유효한 배포 인증서가 필요합니다. Xcode에서 해당 서명을 준비한 뒤:

```sh
flutter build ipa --release --export-method ad-hoc
```

생성된 서명 IPA는 프로파일에 포함된 기기에만 설치할 수 있습니다. Mac의
Apple Configurator 등으로 설치합니다. 임의의 iPhone에서 다운로드만으로
실행할 수 있는 공개 배포 파일은 아닙니다.

자동 서명 내보내기가 맞지 않는 팀은 Xcode Organizer에서 한 번 내보낸 실제
`ExportOptions.plist`와 로컬 서명 설정을 사용합니다.

```sh
flutter build ipa --release --export-options-plist=/path/to/ExportOptions.plist
```

서명 CI는 실제 팀/인증서/프로파일과 비밀 저장 방식이 정해진 뒤 구성해야 합니다.
현재 제공하는 CI는 Apple 자격 증명을 사용하지 않는 컴파일 확인만 수행합니다.
