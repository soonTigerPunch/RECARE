# AI 레시피 Supabase 서버 운영 안내

현재 상태는 **구현 및 모의 검증 완료, 운영 비활성화**입니다. Supabase 프로젝트 생성,
서버 배포, 외부 공개, 실제 OpenAI 호출은 수행하지 않았습니다. 이 문서의 배포 명령도
실행하지 않았습니다. 사용자 소유 프로젝트와 운영 정책·예산이 확정된 후 담당자가
검토할 실행 절차입니다.

## 구성과 요청 수명

앱은 Supabase 익명 인증으로 받은 access token과 공개 publishable key를 사용합니다.
Edge Function은 토큰을 `/auth/v1/user`로 검증한 뒤, 검증된 토큰의 `sub`, `session_id`,
익명 상태, 만료 시각을 확인합니다. 익명 사용자가 생성된 지 30일 이상이면 새 익명
로그인이 필요합니다. refresh token 갱신으로 이 30일 제한을 연장하지 않습니다.

서버는 사용자/세션과 IP를 서로 다른 문맥의 HMAC으로 가명 처리합니다. 클라이언트는
DB 테이블 및 예약 RPC에 직접 접근할 권한이 없습니다. 공개 함수의 JWT gateway 검증은
`supabase/config.toml`에서 `verify_jwt = false`이며, 함수 내부의 Auth 검증은 필수입니다.
이 설정은 새 publishable key를 지원하기 위한 것이며 익명 무인증 엔드포인트를 뜻하지 않습니다.

기본 경로는 `/functions/v1/recipe-recommendations`입니다. 모든 요청에 다음 헤더가 필요합니다.

```text
apikey: <앱과 같은 Supabase publishable key>
Authorization: Bearer <Supabase anonymous access token>
Content-Type: application/json
```

1. `POST ?action=issue`에 `{"request_id":"클라이언트가 만든 UUID"}`를 보내면
   서버가 해당 세션에 발급 시각과 24시간 만료 시각을 기록합니다.
   응답은 `{"request_id":"…","expires_at":"…"}`입니다. 동일 ID 재발급은 원래
   만료 시각을 유지합니다. 발급은 모델 호출이나 하루 5회 차감을 발생시키지 않습니다.
2. 일반 `POST`에는 [공유 계약](AI_RECIPE_CONTRACT.md)의 재료·조건을 보냅니다.
   발급되지 않은 ID는 `not_found`, 만료된 ID는 `expired`입니다. 원자적 예약이
   성공한 작업만 모델을 호출합니다. 같은 세션·ID·입력은 같은 결과를 재수신하며,
   입력을 바꾸면 `conflict`입니다. 진행 중이면 HTTP 409 `in_progress`입니다.
3. `GET ?request_id=UUID`는 같은 세션의 결과만 조회하며 새 작업을 발급하거나
   모델을 호출하지 않습니다. 다른 세션 및 모르는 ID는 HTTP 404입니다.
   완료 전 발급 상태도 조회 가능한 결과가 없으므로 `not_found`입니다.

사용자 취소나 네트워크 시간 초과 뒤에는 같은 ID를 조회합니다. 같은 작업이 실패·만료되어도
서버가 그 ID로 새 모델 실행을 시작하지 않습니다. 새로운 추천은 사용자 행동으로 새 ID를 만듭니다.
발급한 ID는 결과를 지운 뒤에도 작은 가명 tombstone으로 유지하여 오래된 ID 재사용을 차단합니다.

## 서버 설정값

운영 비밀은 Supabase Edge Function secrets에만 보관합니다. 앱에는 Supabase URL과
publishable key 두 개만 전달합니다. 비밀값을 Git, Flutter `--dart-define`, 앱 asset,
오류 응답, 명령행 인수, 일반 로그에 넣지 않습니다. 로컬 비밀 파일은 `.env.*` 이름으로
만들고 저장소 밖 또는 무시되는 위치에 두세요. `.env.example`에는 실제 값을 넣지 않습니다.

| 변수 | 설정 및 의미 |
| --- | --- |
| `RECIPE_ENABLED` | 기본 `false`. `true`일 때만 HTTP 처리와 외부 의존성 접근 허용 |
| `RECIPE_PUBLIC_POLICY_APPROVED` | 기본 `false`. 개인정보·남용 방지·공개 이용 정책 검토 뒤 명시적으로 `true` |
| `SUPABASE_URL` | Supabase가 주입하는 프로젝트 URL. 운영 HTTPS 필수 |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase가 주입하는 서버 전용 키. PostgREST RPC 호출에만 사용 |
| `RECIPE_PUBLISHABLE_KEY` | 앱과 동일한 공개 publishable key. 서버 설정에도 명시 필요 |
| `OPENAI_API_KEY` | 서버 전용 OpenAI 프로젝트 키. `RECARE_KEY`를 대체 이름으로 지원하지만 하나를 선택 |
| `RECIPE_ENCRYPTION_KEY` | AES-256-GCM용 무작위 32바이트를 64자리 hex로 표현 |
| `RECIPE_PSEUDONYM_KEY` | 별도로 생성한 HMAC-SHA256용 32바이트, 64자리 hex |
| `RECIPE_TRUSTED_IP_HEADER` | `x-forwarded-for`, `x-real-ip`, `cf-connecting-ip` 중 검증한 신뢰 경계의 헤더 |
| `RECIPE_MODEL` | 잠정 기본값 `gpt-4.1-mini`. 클라이언트는 모델을 지정할 수 없음 |
| `RECIPE_INPUT_PRICE_MICRO_PER_MILLION` | 운영자가 확인한 입력 100만 토큰 가격, micro USD 정수. 기본 0은 활성화 차단 |
| `RECIPE_OUTPUT_PRICE_MICRO_PER_MILLION` | 운영자가 확인한 출력 100만 토큰 가격, micro USD 정수. 기본 0은 활성화 차단 |

테스트의 가격 숫자는 고정 계산용 fixture이며 현재 실제 모델 가격을 확인했다는 뜻이 아닙니다.
모델 지원 여부·프로젝트 접근 권한·실제 생성 품질·비용은 유료 호출 없이 검증하지 않았습니다.
키의 유효성을 알아보기 위한 실제 API 호출도 수행하지 않았습니다.

키는 서버 밖에 출력하지 않고 암호학적 난수 생성기로 각각 만듭니다. 암호화 키를 바꾸면
기존 24시간 결과를 복호화할 수 없습니다. 키 교체는 기능 중지와 기존 결과 정리 뒤 진행하거나
향후 key version 지원을 추가해야 합니다. 가명 키 교체는 세션별 한도와 tombstone의 연결도
바꾸므로 운영 중 즉시 교체하지 않습니다.

## IP 신뢰 경계와 익명 인증

Authentication 설정에서 anonymous sign-in을 허용해야 앱의 로그인 없는 흐름이 동작합니다.
익명 사용자를 일반 이메일 계정으로 자동 연결하지 않습니다. 앱에 공유 비밀문자열을 넣어
앱 진위를 판정하지 않습니다. 재설치나 익명 사용자 재생성으로 일일 한도를 우회할 수 있으므로,
공개 전 익명 가입 자체의 rate limit, CAPTCHA/앱 무결성 대책 및 운영 비용을 결정해야 합니다.
현재 앱에는 CAPTCHA 또는 기기 무결성 토큰 연동이 구현되어 있지 않으므로 해당 정책을
필수화할 경우 서버만 켜지 말고 앱과 함께 구현·검증해야 합니다.

IP는 **신뢰하는 프록시가 클라이언트 제공 값을 제거하고 다시 기록하는 헤더**에서만
받아야 합니다. `x-forwarded-for`는 첫 번째 주소를 사용합니다. 임의의 클라이언트가 이 값을
바꿀 수 있거나 실제 사용자 대신 같은 gateway IP만 전달된다면 올바른 제한이 아닙니다.
선택한 Supabase gateway 또는 별도 프록시에서 헤더 제거/덮어쓰기와 우회 경로 차단을 확인한
뒤 `RECIPE_TRUSTED_IP_HEADER`를 지정하세요. 코드만으로 프록시의 헤더 신뢰성을 증명하지 않습니다.
헤더 설정 또는 주소가 없으면 `configuration`으로 차단합니다.

현재 IP당 UTC 분 버킷 60회로 발급·추천·조회 및 잘못된 인증을 제한합니다. DB에는 원 IP를
저장하지 않습니다. IP 제한은 짧은 남용 방지 용도이고 개인별 일일 한도는 검증된 세션으로 계산합니다.

## SQL 예산과 작업 예약

마이그레이션은 `recipe_private` 스키마와 service-role 전용 `SECURITY DEFINER` RPC를 만듭니다.
테이블은 RLS가 켜져 있고 클라이언트 정책 및 직접 테이블 권한이 없습니다. RPC는 고정
`search_path`를 사용합니다. 설정은 프로젝트 DB 소유자의 SQL 편집기/관리 연결에서 변경합니다.

초기 `recipe_private.config`는 `enabled=false`, 모든 비용 한도 0, 전체 동시 작업 1입니다.
일일/월간 한도 및 작업당 예약 비용은 micro USD 정수입니다. 1 USD = 1,000,000 micro USD입니다.
승인한 숫자로 다음 비활성 설정을 먼저 구성한 뒤 검토하세요. 예산 0은 실제 추천을 허용하지 않습니다.

```sql
update recipe_private.config set
  enabled = false,
  daily_budget_micro = 0,       -- 승인한 서비스 일일 예산으로 교체
  monthly_budget_micro = 0,     -- 승인한 서비스 월간 예산으로 교체
  request_reserve_micro = 0,    -- 아래 최소 예약액 이상으로 교체
  max_concurrent = 1
where singleton;
```

한 요청은 교정까지 최대 두 번의 모델 호출을 예약합니다. 현재 출력 상한은 호출당 4,000토큰이며
입력은 직렬화한 요청 본문 최대 65,536바이트와 토큰 오버헤드 여유 1,000을 기준으로 잡습니다.
서버가 요구하는 최소 예약액은 다음과 같습니다.

```text
2 × (ceil(66,536 × 입력가격 / 1,000,000)
     + ceil(4,000 × 출력가격 / 1,000,000)) micro USD
```

실제 모델 가격, 프롬프트/스키마 변경, 토큰 계산 정책을 확인하고 예약액을 넉넉히 잡으세요.
비용 상한은 설정한 모델 가격이 정확하다는 전제이며 Supabase 요금·세금·기타 인프라 비용은
포함하지 않습니다. 운영자의 OpenAI 프로젝트 지출 한도도 함께 설정해야 합니다.

예약 RPC는 트랜잭션 잠금 아래 세션별 한국 날짜 기준 5회, 세션 동시 작업 1건,
전체 동시 작업 수, 서비스 일일·월간 비용을 함께 선점합니다. 정상 결과와 정상 `no_match`는
사용 횟수로 계산합니다. 서비스 오류는 사용자 횟수 예약을 해제하지만 모델 비용은 반영합니다.
두 호출의 읽을 수 있는 사용량은 모두 정산하고, 비용을 알 수 없으면 예약액 전체를 보수적으로
차감합니다. 35초 lease가 끊긴 작업도 같은 방식으로 복구하며 다시 모델을 실행하지 않습니다.

## 보관과 정기 정리

결과는 세션/요청 문맥을 추가 인증 데이터로 묶은 AES-GCM ciphertext로 저장합니다.
재료 원문·제외 원문은 작업 테이블에 저장하지 않으며 입력은 SHA-256 해시만 남깁니다.
생성된 결과에 제외 조건이 간접 반영될 수 있으므로 암호화 결과 역시 민감한 데이터로 취급합니다.
논리적 만료 시점은 서버 발급 후 24시간이며 만료된 결과는 응답하지 않습니다.

마이그레이션 시 `pg_cron`이 이미 설치되어 있으면 `recare-recipe-retention`을 매분 등록합니다.
없으면 자동 등록하지 않으므로 **실제 활성화 전에** Supabase에서 `pg_cron`을 설치하고 다음
작업을 등록하거나 동등한 신뢰 가능한 관리 스케줄러를 구성해야 합니다.

```sql
select cron.schedule(
  'recare-recipe-retention',
  '* * * * *',
  'select public.recipe_maintenance()'
);
select jobid, jobname, schedule, active
from cron.job where jobname = 'recare-recipe-retention';
```

중복 등록하지 않도록 기존 jobname을 확인하고, 실패 알림과 `cron.job_run_details` 감시를
설정하세요. maintenance는 만료 ciphertext 삭제, 끊긴 작업의 비용/한도 복구,
IP 분 버킷 정리, 오래된 한도 행 정리, 30일 이후 작업 메타데이터 축소를 수행합니다.
IP 버킷은 약 2분, 세션 한도는 약 31일, 월 경계 예산 계산용 집계는 최대 약 62일 유지합니다.
작업 ID·세션 가명·발급/만료·상태 tombstone은 재실행 방지를 위해 영구 유지합니다.
이 보관 예외를 개인정보 안내 및 삭제 정책에 명시해야 합니다.

물리적 ciphertext 삭제는 정리 실행 시점에 일어나므로 매분 스케줄 기준 만료 후 최대 약 1분과
스케줄러 지연이 추가될 수 있습니다. 정확한 물리적 24시간 상한 또는 백업까지 포함한 삭제가
정책상 필요하다면 더 이른 정리 시각/TTL과 백업 보관 정책을 별도로 설계·검증한 뒤 개방하세요.
현재 코드는 관리형 백업 보관을 제어하지 않습니다. 기능 중지 중에도 정리 스케줄은 계속 실행합니다.

## 프로젝트 구성 및 배포 절차

아래는 아직 실행하지 않은 운영 절차입니다. 사용자 소유 Supabase 계정·프로젝트,
리전/요금제, 서비스 예산, 정식 개인정보 안내 주소 및 공개 이용 정책 확정이 선행되어야 합니다.

1. 소유자가 Supabase 프로젝트를 만들고 익명 인증을 허용합니다. 공개 key와 서버 key를
   구분하고, recipe_private 스키마를 API exposed schemas에 추가하지 않습니다.
2. 적절한 권한의 로컬 Supabase CLI에서 프로젝트를 연결하고 마이그레이션을 검토·적용합니다.

   ```sh
   supabase link --project-ref YOUR_PROJECT_REF
   supabase db push --linked
   ```

3. secrets를 비공개 파일로 준비합니다. 이 단계에는 `RECIPE_ENABLED=false`와
   `RECIPE_PUBLIC_POLICY_APPROVED=false`를 유지합니다. 플랫폼 주입 `SUPABASE_*`를
   CLI secret 파일로 다시 등록하지 않습니다. 비밀값이 포함된 파일은 Git에 추가하지 않습니다.

   ```sh
   supabase secrets set --project-ref YOUR_PROJECT_REF --env-file /PRIVATE/PATH/.env.recipe
   supabase functions deploy recipe-recommendations --project-ref YOUR_PROJECT_REF
   ```

4. 운영 DB 예산, maintenance 스케줄과 실제 정리, Auth 정책, 신뢰 IP 헤더,
   민감 정보 로그 비활성화, 모델·가격·프로젝트 지출 한도를 검토합니다. 비활성 엔드포인트는
   HTTP 503 `disabled`만 반환하며 OpenAI를 호출하지 않아야 합니다.
5. 사용자가 실제 호출과 비용 상한을 별도로 승인한 뒤 제한된 품질/지연/비용 평가를 진행합니다.
   현재 요청은 mock-only이므로 이 단계는 수행하지 않았습니다. 공개 출시 전에 실기기 QA와
   무결성/남용 방지 검증도 필요합니다.
6. 검토가 끝난 운영 변경에서만 `RECIPE_PUBLIC_POLICY_APPROVED=true`,
   `RECIPE_ENABLED=true`, DB의 `enabled=true`를 적용합니다. 둘 중 하나를 끄면 새 추천이
   차단됩니다. Edge flag가 꺼지면 조회도 중지되지만 로컬 즐겨찾기는 계속 열 수 있습니다.

즉시 새 생성을 중지하는 관리 SQL은 다음과 같습니다. Edge secret `RECIPE_ENABLED=false`도
함께 적용할 수 있습니다. 이미 전송된 모델 호출의 비용을 취소한다는 의미는 아닙니다.

```sql
update recipe_private.config set enabled = false where singleton;
```

## 검증 명령과 확인 범위

Node 24 이상이면 서버 테스트는 외부 패키지 설치나 비밀값 없이 실행합니다.
실제 네트워크 전송 대신 `fetch` 모의 경계를 주입합니다. Deno Edge 런타임과 공통인
표준 Fetch/WebCrypto API만 사용하며 런타임 의존성은 없습니다.

```sh
node --experimental-strip-types --test --test-isolation=none server_tests/*.test.ts
# 또는
npm --prefix server_tests test
```

실제 SQL 테스트는 **폐기 가능한 로컬 PostgreSQL 컨테이너**에서만 실행하세요.
운영/공유 DB에 테스트 SQL을 적용하지 않습니다. 다음 예제는 공개 포트를 열지 않고
네트워크가 없는 PostgreSQL을 사용합니다. `anon`, `authenticated`, `service_role` 역할은
Supabase에 원래 존재하며 일반 PostgreSQL fixture에서만 직접 만듭니다.

```sh
docker run --detach --name recare-recipe-pg --network none \
  --env POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine
docker exec -i recare-recipe-pg psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
create role anon;
create role authenticated;
create role service_role;
SQL
python3 server_tests/postgres_integration.py --container recare-recipe-pg
docker rm --force recare-recipe-pg
```

서버 테스트와 PostgreSQL 검사에서 요청·응답 검증, 잘못된 인증, 원자적 예약/비용 정산,
동일 작업 재수신, 다른 세션 차단, 만료/복구, 권한, 실제 16~32개 동시 호출 경쟁을 검증했습니다.
운영 Supabase Auth/PostgREST/gateway 연계, pg_cron 실제 실행, Edge 배포·부하·실기기 동작,
실제 OpenAI 결과/지원 모델/계정 권한은 이 로컬 검증의 범위 밖입니다.

## 모델 검증의 한계

서버는 구조·참조 ID·단위·정수 수량·합산 재고·인분·시간·명시된 양념/구매·중복 요리와
일부 알려진 제외 재료/복합 양념을 검사합니다. 숫자가 있는 표시 수량은 검증된 base amount로
서버가 다시 만듭니다. 일부 후보가 유효하면 그 후보만 반환하고, 전부 검증 실패일 때만
남은 시간 안에서 교정 호출을 한 번 허용합니다. 전송 결과가 불명확한 실패는 재시도하지 않습니다.
키/모델 접근/과금 오류는 반복 재시도를 유도하지 않는 `configuration`으로 매핑합니다.

자연어 조리 단계에 적힌 모든 재료와 동의어를 완전히 추출하는 의미 검증은 구현하지 않았습니다.
구조화된 재료 목록이 올바르더라도 단계에 미기재 재료가 들어갈 가능성은 남습니다.
현재 명시적 기본 양념 및 알려진 제외 성분 검사는 제한된 어휘에 기반하며 알레르기 안전 판정이
아닙니다. 운영 품질 평가에서 미기재 재료, 복합 조미료, 비요리 입력, 조건 만족 불가 사례를
반드시 검토하고 완전한 조건 보증을 광고하지 마세요. 제품 표시·재료 상태·익힘은 사람이 확인해야 합니다.
