> 최신 상태: [실제 추천 테스트 운영](AI_RECIPE_PILOT.md). 제한 테스트에서 실제 Flutter 클라이언트 추천/조회/회수 검증 성공. 아래는 이전 작업 이력이다.

> 2026-11-07 새 프로젝트 `tpugkdsqrsiucnjyakqx`: 마이그레이션 `20261105000000`, 익명 인증, Edge Function v1, 매분 정리 작업 설정 완료. DB 예산 0 및 기능 비활성, 함수 503 disabled 확인. Supabase의 `OPENAI_API_KEY`로 비공개 임시 함수에서 실제 생성 성공(아래 최신 검증 참고). 아래 내용은 이전 프로젝트 이력입니다.

# AI recipe deployment verification — 2026-11-06 (KST)

## Observed project state

Project: `ahphnqxqkzdfnpraodmy` (`recipe`, ap-south-1), ACTIVE_HEALTHY.
Initial checkout: a8fbc35, clean working tree. No previous uncommitted app configuration was present.
The running managed environment reports current, ready bindings for SUPABASE_ACCESS_TOKEN
(api.supabase.com) and RECARE_KEY (api.openai.com). No environment configuration was published.

Management API and project endpoint checks found existing deployment, so migration and
function deployment were not repeated:

- Migration 20261105000000 is recorded.
- recipe-recommendations v2 is ACTIVE, verify_jwt=false (internal Auth verification is required).
- Anonymous sign-in is enabled; signup with the supplied public key returned HTTP 200 and is_anonymous=true.
  One test anonymous account was created; its tokens were not printed or persisted.
- Function POST returns HTTP 503 with error.code=disabled.
- recipe_private config: enabled=false; daily/monthly/request budgets all zero; max_concurrent=1.
- All five recipe_private tables have RLS enabled.
- pg_cron is installed. recare-recipe-retention runs every minute and was active;
  31 succeeded runs were observed. This verifies scheduling, not every physical deletion scenario.
- RECARE_KEY, encryption/pseudonym keys, model, prices and feature/policy flag secret names exist.
  Management API lists names only; secret values were not retrieved or compared.
- RECIPE_TRUSTED_IP_HEADER was absent from the secret-name list.
- Anonymous signup limit reported 30; CAPTCHA disabled. App integrity integration remains unimplemented.

## App configuration

config/recipe.public.json contains only the project URL and user-provided public key.
Android and iOS workflow build commands now use --dart-define-from-file=config/recipe.public.json.
No workflows or releases were triggered. APKs remain ignored by Git.
See AI_RECIPES.md for local build commands.

## OpenAI authentication investigation and cost

Exactly one GET /v1/models and one POST /v1/responses were issued in this session
using the environment-provided RECARE_KEY through the inherited HTTPS proxy.
The list returned 200 and included gpt-4.1-mini.
The generation request used gpt-4.1-mini, store=false, input "Reply with OK.",
and max_output_tokens=16. It returned HTTP 401, type invalid_request_error,
code invalid_api_key. No retry or correction request was sent.

Successful generations: zero. No token usage or billable amount was returned.
Expected generation charge is $0 for the authentication rejection; account billing
was not available and a posted invoice amount cannot be independently confirmed.
The authorized test budget is $0.50; no further paid tests were attempted.

The problem reproduces before application JSON/schema validation; model listing
success does not prove Responses authentication. Evidence does not distinguish a
bad/revoked secret from a credential delivery issue in the environment proxy.
The hosted Edge Function's RECARE_KEY value cannot be compared through the secret
listing API; its actual generation path remains untested. Do not copy an injected
runtime credential placeholder into Supabase secrets. Verify/re-save the intended
OpenAI project secret through the secure configuration UI, check Responses access,
and test again only within the remaining authorized budget. Do not paste keys in chat.

## Public activation remains blocked

The user explicitly chose “미정 — 비활성 유지” during this session.
Keep DB enabled=false and do not approve public-policy flags until these are resolved:

- Approve service daily/monthly budget and per-request reservation; verify current model pricing
  and OpenAI project spending controls. The $0.50 test permission is not a service budget.
- Publish accurate privacy notice: OpenAI transfer, indirect sensitive recipe content,
  24-hour encrypted results and scheduler delay/backups, permanent pseudonymous request tombstones.
- Decide and implement CAPTCHA/app integrity and anonymous signup abuse protections.
- Verify gateway strips/overwrites the chosen trusted client IP header, then configure it.
- Resolve OpenAI generation authentication and run bounded end-to-end quality/latency tests.
- Verify remote function source matches the intended local revision before activation;
  ACTIVE status alone does not establish source equivalence.
- Complete real-device QA, retention deletion checks and failure monitoring/alerts.

Deployment exists, but successful AI recipe generation and public launch are not complete.

## Local verification

- Server mock suite: 36 passed.
- Flutter analyze --no-pub: no issues.
- Flutter test --no-pub: 170 passed. The sandbox initially blocked local test sockets;
  rerun with the needed execution permissions passed.
- Initial APK build failed because recare-env.sh selects a Java runtime without javac.
  Use JAVA_HOME=/workspace/toolchains/jdk21 and prepend its bin to PATH;
  set GRADLE_OPTS=-Dorg.gradle.java.home=/workspace/toolchains/jdk21 for this build.
  No cloud configuration was changed or published.
- Gradle also waited on a direct dependency connection. For the retry, explicit
  http/https proxyHost=proxy, proxyPort=8080 and the system Java CA trust store were
  passed through GRADLE_OPTS, preserving the managed proxy route and TLS validation.

Cloud APK build command (session-only overrides):

```sh
source /workspace/recare-env.sh
export JAVA_HOME=/workspace/toolchains/jdk21
export PATH="$JAVA_HOME/bin:$PATH"
export GRADLE_OPTS="-Dorg.gradle.java.home=/workspace/toolchains/jdk21 -Dhttp.proxyHost=proxy -Dhttp.proxyPort=8080 -Dhttps.proxyHost=proxy -Dhttps.proxyPort=8080 -Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts"
flutter build apk --release --dart-define-from-file=config/recipe.public.json
```

The restored GeneratedPluginRegistrant.java contained the dev-only integration_test
plugin. --no-pub retained this stale registration. flutter pub get alone generated
debug registrations; running the normal release build without --no-pub refreshed
release-specific tooling and removed the integration_test registration. No generated
file was edited or committed manually; the lockfile remained unchanged.

Final APK build: succeeded, build/app/outputs/flutter-apk/app-release.apk (57.1 MB).
This is a test APK using the repository's existing debug signing configuration,
not a production-signed store release. iOS CI configuration was updated but no iOS
build was executed on this Linux host. No APK, release or cloud settings were published.

## 2026-11-07 최신 릴리스 검증

- Supabase에 있는 OPENAI_API_KEY로 기존 model.ts/validation.ts를 사용해 실제 두부 레시피 생성 성공.
- 추측 불가능한 임시 Bearer 토큰, 10분 만료, 인스턴스별 단일 실행으로 보호한 일회용 함수 사용. 요청 내용은 고정된 합성 재료이며 임의 사용자 입력을 받지 않음.
- OpenAI POST 1회, HTTP 200, 입력 578 / 출력 284토큰. 교정 호출 없음. 임시 함수 삭제 HTTP 200 확인.
- 입력 $0.40/백만, 출력 $1.60/백만 토큰 가정 시 $0.0006864(서버 올림 정산 $0.000687). 실제 청구액 및 최신 요금표는 확인하지 못했음.
- 공개 추천과 DB 예산 0은 유지. 실제 공개 Auth→예약→생성→정산 전체 흐름은 아직 미검증.
- 기존 공개 1.1.1 APK 인증서 716d350e47cffbd8d0e9d6e790c147f6d05fbd305c81cc0dc2ffeccb4c552991, 앱 ID com.detabev.recare, versionCode 6 확인.
- 클라우드 키와 기존 로컬 APK는 44f52b423b5ff4321ad2f56c7efc9c392fc6c377b455b754d6f25e6d358e83b2이므로 업데이트 배포 금지.
- 다음 빌드는 1.2.0+7. 원본 키로 서명 검증 후에만 APK 릴리스 진행. 키·암호는 저장소에 포함하지 않음.

원본 키 전달 후 인증서 일치 확인. 최종 1.2.0+7 APK 빌드와 apksigner 검증 통과. 이전 클라우드 키로 만든 APK는 배포하지 않음. 키 파일과 로컬 암호 설정은 Git에서 제외.
