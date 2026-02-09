0) 설계 목표(P0만 남김)

Claude/GPT 모두 “단일 호출 경로”: 모델 실행은 *_call만 담당 (block 직접 CLI/API 호출 금지)

재시도는 한 군데만: “전송/네트워크” 재시도는 *_call 내부에서만, block=0회

출력 계약은 명확히 2개: Legacy(기본) / Envelope(옵션) — 혼선 방지 규칙 포함

1) 구성(레이어) 재정의
A. Call 레이어(유일한 모델 호출 지점)

chatgpt_call / claude_call

책임: 실제 전송, timeout, 전송 재시도(짧은 retry), 원시 결과 반환(legacy 유지)

B. Block 레이어(Thin Adapter + 통합 정책)

gpt_block / claude_block

책임: 인자 파싱, 입력 파일 조합, call 호출, (옵션일 때만) 엔벨로프 래핑

핵심 수정점: claude_block은 gpt_block과 동일하게 “call만 호출”. 프롬프트 중복/regex 파싱/stderr 묵살 제거.

2) 출력 계약(혼선 방지 포함) — 평가 피드백 반영 핵심
모드 1) Legacy 모드(기본값, 기존 호환)

stdout: 기존 그대로 (raw JSON 또는 __ERROR__:*/__FAILED__ 등 센티넬)

상위(flow/runner)는 기존 로직 그대로 사용 가능

모드 2) Envelope 모드(옵션: --envelope 또는 ENV)

stdout: 항상 표준 JSON 한 덩어리만 출력

혼선 방지 규칙(필수)

Envelope 출력은 반드시 최상위에 ok(boolean) 필드를 포함

Legacy에서는 ok 최상위 필드가 나오지 않도록 보장(충돌 제거)

Envelope 최소 필드(필수 고정)

ok, provider, action, model

result(성공 시), error(실패 시)

meta.duration_ms, meta.retries

실패 시 error.code + error.legacy_code

3) 에러 코드 정책(UNKNOWN 과다 방지)
표준 코드(자동화 분기용 최소 세트)

TIMEOUT

EMPTY_OUTPUT

TRANSIENT (일시 오류/재시도 가치 있음)

FATAL (즉시 중단이 맞음: 입력/환경/권한/인증 등)

UNKNOWN (최후)

기존 센티넬 → 표준 매핑(최소 강제)

__TIMEOUT__ → TIMEOUT

__COMPLETED_BUT_EMPTY__, __EMPTY__ → EMPTY_OUTPUT

__STUCK__ → TRANSIENT

__STOPPED__ → 기본 TRANSIENT (reason에 “사용자 개입/차단” 등이 있으면 FATAL)

__ERROR__:* → reason 파싱 가능하면 FATAL(AUTH/CLI_NOT_FOUND/BAD_INPUT류), 아니면 UNKNOWN

__FAILED__ → 기본 UNKNOWN (단, “입력파일 없음/권한” 감지 시 FATAL)

포인트: STOPPED/ERROR는 무조건 UNKNOWN으로 던지지 말고 최소 2분류(TRANSIENT/FATAL)로 가르는 게 자동화 품질을 크게 올립니다.

4) 재시도 정책(이중 재시도 회귀 방지)
원칙(강제)

전송 재시도 = call 레이어만 (예: 0~2회, 짧은 backoff)

block 레이어 재시도 = 0 (GPT_BLOCK_RETRY 같은 설정은 “정책상 무효”로 고정)

flow 레벨 재시도는 별개: 프롬프트 변경/단계 전환 등 “의미적 재시도”만 담당

분리 규칙(운영 기준)

TIMEOUT/TRANSIENT → call이 소진하면 flow가 재시도 여부 판단

FATAL → 즉시 STOP(사람 개입)

5) 프롬프트 경로 전략(프로젝트 우선 + 공통 기본)

탐색 순서(고정)

--prompt/--template 명시

프로젝트 프롬프트(예: claude/ai_court/prompts/...)

공통 기본(예: common/prompts/claude/review.md)

내장 fallback(짧은 기본 문구)

필수 로그(관측성 최소)

prompt_source=inline|project|common|builtin

prompt_path=...(가능할 때)

6) 적용 순서(“지금 고칠 것 / 나중 표준화” 정리)

즉시(P0): claude_block thin adapter화 (call만 호출) + stderr 묵살 금지 + block retry=0

단기: Envelope 옵션 도입(기본 legacy 유지, 옵션 시에만 표준 JSON)

단기: 표준 코드 매핑 적용(TIMEOUT/EMPTY/TRANSIENT/FATAL/UNKNOWN 최소 세트)

중기: flow/runner가 envelope 기준(ok/code) 분기 채택(문자열 길이 기반 분기 제거)

최종 결론

지금 문제(claude_block만 실패)는 **A(최소 변경)**로 “즉시” 해결하고,

평가에서 지적된 리스크(2계약 혼선/UNKNOWN 과다/이중 재시도)는
(1) Envelope 충돌 방지 규칙(ok 필드) + (2) TRANSIENT/FATAL 최소 분류 + (3) retry 단일화 정책 고정으로 정리하는 게 가장 안전하고 강력합니다.