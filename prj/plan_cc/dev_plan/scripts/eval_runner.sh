#!/bin/bash
# eval_runner.sh - GPT 테스트 평가 요청 (Phase 1-2 반자동)
# Claude Code가 코드 작성 + 테스트 실행 후, GPT에 평가만 요청
#
# 사용법:
#   ./eval_runner.sh --version=1                    # v1 테스트 평가 요청
#   ./eval_runner.sh --version=2 --dry-run          # 테스트 모드

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ══════════════════════════════════════════════════════════════
# 프로젝트 설정 로드
# ══════════════════════════════════════════════════════════════
if [[ -f "${PROJECT_DIR}/config/settings.sh" ]]; then
    source "${PROJECT_DIR}/config/settings.sh"
    load_chatgpt 2>/dev/null || true
else
    echo "ERROR: settings.sh not found" >&2
    exit 1
fi

# 공통 모듈 로드
source "${PROJECT_DIR}/lib/util/errors.sh"
source "${PROJECT_DIR}/lib/util/state.sh"
source "${PROJECT_DIR}/lib/util/template.sh"

# 상태 디렉토리 초기화
init_state_dir "${STATE_DIR}"

# 날짜 및 경로 설정
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H%M%S)
RUN_DIR="${RUNS_DIR}/${DATE}"
DEV_DIR="${RUN_DIR}/dev"
DESIGN_DIR="${RUN_DIR}/design"
LOG_DIR="${LOGS_DIR}/${DATE}"
mkdir -p "$DEV_DIR" "$LOG_DIR"

LOG_FILE="${LOG_DIR}/eval_${TIME}.log"

# ══════════════════════════════════════════════════════════════
# 인자 파싱
# ══════════════════════════════════════════════════════════════
VERSION=""
DRY_RUN=false

show_help() {
    echo ""
    echo "eval_runner.sh - GPT 테스트 평가 요청 (Phase 1-2)"
    echo ""
    echo "사용법: ./eval_runner.sh --version=N [옵션]"
    echo ""
    echo "필수 옵션:"
    echo "  --version=N     평가할 코드 버전"
    echo ""
    echo "선택 옵션:"
    echo "  --dry-run       ChatGPT 호출 없이 테스트"
    echo "  --help          도움말 표시"
    echo ""
    echo "사전 조건:"
    echo "  1. Claude Code가 코드 작성 완료 → runtime/runs/{date}/dev/code_v{N}/"
    echo "  2. Claude Code가 테스트 실행 완료 → runtime/runs/{date}/dev/test_v{N}.json"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --version=*)
            VERSION="${1#*=}"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    echo "ERROR: --version은 필수입니다." >&2
    show_help
    exit 1
fi

# ══════════════════════════════════════════════════════════════
# 입력 파일 확인
# ══════════════════════════════════════════════════════════════
CODE_DIR="${DEV_DIR}/code_v${VERSION}"
TEST_FILE="${DEV_DIR}/test_v${VERSION}.json"
FEEDBACK_FILE="${DEV_DIR}/feedback_v${VERSION}.json"

# 승인된 설계 찾기 (가장 높은 버전의 설계)
find_approved_design() {
    local latest_design=""
    for f in "${DESIGN_DIR}"/design_v*.md; do
        [[ -f "$f" ]] && latest_design="$f"
    done
    echo "$latest_design"
}

DESIGN_FILE=$(find_approved_design)

if [[ ! -d "$CODE_DIR" ]]; then
    echo "ERROR: 코드 디렉토리 없음: $CODE_DIR" >&2
    echo "  Claude Code에서 먼저 코드를 작성하세요." >&2
    exit 1
fi

if [[ ! -f "$TEST_FILE" ]]; then
    echo "ERROR: 테스트 결과 없음: $TEST_FILE" >&2
    echo "  Claude Code에서 먼저 테스트를 실행하세요." >&2
    exit 1
fi

# ══════════════════════════════════════════════════════════════
# 평가 프롬프트 빌드
# ══════════════════════════════════════════════════════════════
build_test_eval_prompt() {
    local eval_template="${PROMPTS_DIR}/evaluator/test_eval.md"

    if [[ ! -f "$eval_template" ]]; then
        echo "ERROR: test_eval template not found: $eval_template" >&2
        return 1
    fi

    local prompt
    prompt=$(cat "$eval_template")

    # 테스트 결과 로드
    local test_result
    test_result=$(cat "$TEST_FILE")
    prompt=$(replace_placeholder "$prompt" "test_result" "$test_result")

    # 코드 내용 로드 (주요 파일만)
    local code_content=""
    for f in "${CODE_DIR}"/*; do
        if [[ -f "$f" ]]; then
            code_content+="
--- $(basename "$f") ---
$(cat "$f")
"
        fi
    done
    prompt=$(replace_placeholder "$prompt" "code_content" "$code_content")

    # 설계 문서 로드
    if [[ -n "$DESIGN_FILE" && -f "$DESIGN_FILE" ]]; then
        local design_doc
        design_doc=$(cat "$DESIGN_FILE")
        prompt=$(replace_placeholder "$prompt" "design_doc" "$design_doc")
    else
        prompt=$(replace_placeholder "$prompt" "design_doc" "(설계 문서 없음)")
    fi

    echo "$prompt"
}

# ══════════════════════════════════════════════════════════════
# 메인 실행
# ══════════════════════════════════════════════════════════════

# 로그 시작
exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Eval Runner - GPT 테스트 평가 요청                           ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  시작 시간:   $(date '+%Y-%m-%d %H:%M:%S')"
echo "║  코드 버전:   v${VERSION}"
echo "║  코드 경로:   ${CODE_DIR}"
echo "║  테스트 파일: ${TEST_FILE}"
echo "║  설계 문서:   ${DESIGN_FILE:-없음}"
echo "║  Dry-run:    ${DRY_RUN}"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 평가 프롬프트 빌드
echo "━━━ 평가 프롬프트 빌드 ━━━"
eval_prompt=$(build_test_eval_prompt)
if [[ $? -ne 0 ]]; then
    echo "ERROR: 평가 프롬프트 빌드 실패" >&2
    exit 1
fi

# 프롬프트 저장
PROMPT_FILE="${DEV_DIR}/feedback_v${VERSION}.prompt.md"
echo "$eval_prompt" > "$PROMPT_FILE"
echo "프롬프트 저장: $PROMPT_FILE (${#eval_prompt}자)"

if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] ChatGPT 호출 스킵"
    echo '{"test_pass": false, "code_quality": 70, "improvements": ["DRY-RUN"], "summary": "dry-run test"}' > "$FEEDBACK_FILE"
    echo "피드백 저장: $FEEDBACK_FILE (DRY-RUN)"

    save_step_state "dev" "$VERSION" "eval" "dry_run" "$FEEDBACK_FILE" 0 0
    echo ""
    echo "━━━ 완료: $(date '+%Y-%m-%d %H:%M:%S') ━━━"
    exit 0
fi

# ChatGPT 새 채팅 + 전송
echo "━━━ GPT 테스트 평가 요청 ━━━"
echo "ChatGPT 새 채팅 시작..."
chatgpt_call --mode=new_chat --tab="$CHATGPT_TAB" --project="$CHATGPT_PROJECT_URL" >/dev/null 2>&1
sleep 2

start_time=$(date +%s)
echo "ChatGPT 호출 중 (Tab $CHATGPT_TAB, timeout: ${TIMEOUT_DEV_EVALUATOR}초)..."

response=$(chatgpt_call --tab="$CHATGPT_TAB" --timeout="$TIMEOUT_DEV_EVALUATOR" --retry "$eval_prompt")

end_time=$(date +%s)
duration=$((end_time - start_time))

# 오류 체크
if is_chatgpt_error "$response"; then
    echo "ChatGPT 오류: $(get_error_message "$response")"
    save_step_state "dev" "$VERSION" "eval" "failed" "$FEEDBACK_FILE" 0 "$duration"
    exit 1
fi

# JSON 추출
json_only=$(echo "$response" | python3 -c "
import sys, json, re
text = sys.stdin.read()
match = re.search(r'\{[\s\S]*\}', text)
if match:
    try:
        obj = json.loads(match.group())
        print(json.dumps(obj, ensure_ascii=False, indent=2))
    except:
        print(match.group())
else:
    print(text)
" 2>/dev/null)

# 저장
echo "$json_only" > "$FEEDBACK_FILE"

echo ""
echo "━━━ 평가 결과 ━━━"
echo "피드백 파일: $FEEDBACK_FILE"
echo "피드백 길이: ${#json_only}자"
echo "소요 시간: ${duration}초"

# 상태 업데이트
save_step_state "dev" "$VERSION" "eval" "completed" "$FEEDBACK_FILE" "${#json_only}" "$duration"

echo ""
echo "━━━ 완료: $(date '+%Y-%m-%d %H:%M:%S') ━━━"
echo "로그: $LOG_FILE"

exit 0
