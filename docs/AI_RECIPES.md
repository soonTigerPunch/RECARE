# AI 레시피 추천 개발 안내

냉장고 재고를 선택해 최대 3개의 요리를 추천받고, 레시피를 기기에 저장하거나
실제 조리 사용량을 기존 먹음 기록에 연결하는 기능입니다. 기존 재고·장보기는
인터넷 없이 계속 사용할 수 있습니다.

## 사용 흐름

홈의 요리 찾기 → 재료·조건 선택 → 최초 전송 안내 확인 → 추천 결과 → 조리법.
보유한 기본 양념은 직접 선택합니다. 소비기한이 지난 재료는 제외하며,
날짜가 바뀌거나 재고가 변경되면 다시 확인합니다. 추천 조건 변경이나 상세 열기,
즐겨찾기 저장만으로 AI를 추가 호출하지 않습니다.

- 최근 추천은 5회, 즐겨찾기는 최대 100개를 기기에 저장합니다.
- 즐겨찾기는 최근 추천을 지워도 남으며, 인터넷 없이 검색·열람·해제할 수 있습니다.
- 알레르기·제외 원문은 현재 요청의 메모리에만 둡니다. 생성된 설명에는 조건을
  반영한 내용이 포함될 수 있습니다. 추천은 알레르기 안전 보증이 아닙니다.
- 만들었어요에서 실제 사용량과 현재 보관분을 확인한 후 일괄 기록합니다.
  재고는 추천을 열거나 저장하는 것만으로 바뀌지 않습니다.
- 조리 일괄 기록과 장보기 일괄 추가는 각각 하나의 트랜잭션과 작업 ID로 처리합니다.
  같은 작업을 다시 제출해도 중복 기록하지 않습니다.
- 먹음 기록 실행 취소는 8초 제공하며, 관련 재료 전체를 복원할 수 있어야 합니다.
  이후 다른 기록이 추가되었으면 일부만 복원하지 않습니다.
- g↔kg, ml↔L만 환산하고 무게·부피·개수 간 임의 환산은 하지 않습니다.

## 서버와 앱 설정

서버 구성은 [Supabase 서버 안내](AI_RECIPE_SERVER.md)를 따릅니다.
사용자 소유 Supabase 프로젝트와 익명 인증 설정이 필요합니다. 앱 빌드에는
다음 **공개 설정값 두 개만** 전달합니다.

```sh
flutter run \
  --dart-define=RECARE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=RECARE_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY
```

실기기에는 접근 가능한 HTTPS Supabase 주소가 필요합니다. 개발용 루프백 HTTP는
로컬 테스트만 허용합니다. Android release 인터넷 권한을 포함합니다.
운영 서버 URL이 설정되지 않으면 새 추천을 사용할 수 없다는 안내가 나오고,
기존 로컬 기능은 계속 동작합니다. 실제 추천 대신 예제 데이터를 반환하지 않습니다.

OpenAI 키는 Supabase Edge Function의 시크릿에만 등록합니다. 이 개발 환경의
`RECARE_KEY`가 운영 서버에 자동 복사되지는 않습니다. 키 값을 읽어 Git이나
Flutter `--dart-define`, `.env` 번들, 앱 설정에 넣지 마세요. Supabase service-role
키도 서버 전용입니다. 앱 클라이언트는 service-role/secret 키 설정을 거부합니다.

## 검증

사용자가 OpenAI 잔액 충전 전까지 유료 호출을 보류하도록 요청했으므로,
이 작업에서는 실제 OpenAI 호출을 실행하지 않습니다. 테스트는 HTTP/모델 응답을
통제한 모의 경계와 실제 로컬 SQLite를 사용합니다. AI 생성 품질·실제 응답 시간·
비용·모델 접근 권한이 검증됐다는 의미는 아닙니다.

```sh
source /workspace/recare-env.sh
flutter analyze --no-pub
flutter test --no-pub
node --experimental-strip-types --test --test-isolation=none server_tests/*.test.ts
```

Flutter 테스트는 내부적으로 로컬 루프백 소켓을 사용하므로, 소켓을 차단한
샌드박스에서는 허용된 테스트 실행 환경이 필요합니다.

공개 배포 전에는 Supabase 프로젝트/리전/요금제와 예산, 개인정보 처리 주체·
정식 안내 주소, 앱 무결성 및 익명 인증 남용 방지 정책을 확정해야 합니다.
그 이후 운영 설정을 검토하고 배포합니다. 서버 기본 상태는 비활성화이며,
환경 게시·공개 서버 배포·실제 모델 평가·실기기 QA와 구현 완료는 별도로 관리합니다.

## 구현 검토 기록

수량 표시를 정수 수량에서 계산하도록 통일하고, kg/L 재고의 사용량은 g/ml로 입력해
소수 수량의 정밀도를 유지합니다. 자정 이후에도 기존 요청의 결과는 조회할 수 있지만
새 추천은 현재 소비기한을 다시 검사합니다. 키보드가 열린 화면에서도 하단 버튼을
누를 수 있도록 여백을 반영합니다. 조리/즐겨찾기 실행 취소 안내는 해당 화면을
떠나면 닫으며, 이미 종료된 화면의 비동기 알림을 차단합니다.

서버는 알려진 식재료가 조리 순서에 등장했는데 재료 목록에서 빠졌으면 거절합니다.
이는 제한된 사전 기반 검사이며 모든 자연어 조리법의 재료 누락이나 알레르기 안전을
증명하지 않습니다. 실제 생성 결과의 품질 평가는 충전 후 별도로 필요합니다.

클라우드 APK 빌드에서 환경 스크립트의 `/usr/lib/jvm/...` 경로에 `javac`가 없다면,
이미 설치된 전체 JDK를 사용합니다.

```sh
source /workspace/recare-env.sh
export JAVA_HOME=/workspace/toolchains/jdk21
export PATH="$JAVA_HOME/bin:$PATH"
export GRADLE_OPTS='-Dorg.gradle.java.installations.paths=/workspace/toolchains/jdk21 -Dorg.gradle.java.installations.auto-detect=false'
flutter build apk --release
```
