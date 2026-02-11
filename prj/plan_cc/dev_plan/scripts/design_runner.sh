#!/bin/bash
# design_runner.sh - 설계 루프 자동화 (Phase 1-1)
# GPT가 설계 작성 → Claude API가 평가 → 자동 반복 (최대 3회, 85점 통과)
#
# 사용법:
#   ./design_runner.sh                      # v1부터 시작
#   ./design_runner.sh --version=2          # v2부터 시작
#   ./design_runner.sh --dry-run            # 테스트 모드
#   ./design_runner.sh --version=1 --once   # 1회만 실행

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ══════════════════════════════════════════════════════════════
# 프로젝트 설정 로드
# ══════════════════════════════════════════════════════════════
if [[ -f "${PROJECT_DIR}/config/settings.sh" ]]; then
    source "${PROJECT_DIR}/config/settings.sh"
    load_chatgpt 2>/dev/null || true
    load_claude 2>/dev/null || true
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
DESIGN_DIR="${RUN_DIR}/design"
LOG_DIR="${LOGS_DIR}/${DATE}"
mkdir -p "$DESIGN_DIR" "$LOG_DIR"

LOG_FILE="${LOG_DIR}/design_${TIME}.log"

# ══════════════════════════════════════════════════════════════
# 인자 파싱
# ══════════════════════════════════════════════════════════════
VERSION=1
DRY_RUN=false
ONCE=false

show_help() {
    echo ""
    echo "design_runner.sh - 설계 루프 자동화 (Phase 1-1)"
    echo ""
    echo "사용법: ./design_runner.sh [옵션]"
    echo ""
    echo "옵션:"
    echo "  --version=N     시작 버전 (기본: 1)"
    echo "  --dry-run       ChatGPT/Claude 호출 없이 테스트"
    echo "  --once          1회만 실행 (자동 반복 안 함)"
    echo "  --help          도움말 표시"
    echo ""
    echo "설정값:"
    echo "  최대 버전:   ${MAX_DESIGN_VERSIONS}회"
    echo "  목표 점수:   ${TARGET_DESIGN_SCORE}점"
    echo "  GPT 타임아웃: ${TIMEOUT_DESIGN_WRITER}초"
    echo "  Claude 타임아웃: ${TIMEOUT_DESIGN_EVALUATOR}초"
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
        --once)
            ONCE=true
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

# ══════════════════════════════════════════════════════════════
# feature_list 확인
# ══════════════════════════════════════════════════════════════
FEATURE_LIST="${RUN_DIR}/feature_list.md"
if [[ ! -f "$FEATURE_LIST" ]]; then
    echo "ERROR: feature_list.md not found at $FEATURE_LIST" >&2
    echo "  Phase 0에서 feature_list.md를 먼저 작성하세요." >&2
    exit 1
fi

FEATURE_CONTENT=$(cat "$FEATURE_LIST")
echo "feature_list.md 로드: ${#FEATURE_CONTENT}자"

# ══════════════════════════════════════════════════════════════
# 설계 프롬프트 빌드
# ══════════════════════════════════════════════════════════════
build_design_prompt() {
    local version="$1"
    local design_template="${PROMPTS_DIR}/designer/design.md"

    if [[ ! -f "$design_template" ]]; then
        echo "ERROR: design template not found: $design_template" >&2
        return 1
    fi

    local prompt
    prompt=$(cat "$design_template")

    # feature_request 치환
    prompt=$(replace_placeholder "$prompt" "feature_request" "$FEATURE_CONTENT")
    prompt=$(replace_placeholder "$prompt" "version" "$version")

    # v2+: 이전 설계 + 평가 피드백 포함
    if [[ $version -gt 1 ]]; then
        local prev_version=$((version - 1))
        local prev_design_file="${DESIGN_DIR}/design_v${prev_version}.md"
        local prev_eval_file="${DESIGN_DIR}/design_v${prev_version}.eval.json"

        if [[ -f "$prev_design_file" ]]; then
            local prev_design
            prev_design=$(cat "$prev_design_file")
            prompt=$(replace_placeholder "$prompt" "prev_design" "$prev_design")
        fi

        if [[ -f "$prev_eval_file" ]]; then
            local prev_eval
            prev_eval=$(cat "$prev_eval_file")
            prompt=$(replace_placeholder "$prompt" "prev_eval_feedback" "$prev_eval")
        fi
    else
        prompt=$(replace_placeholder "$prompt" "prev_design" "")
        prompt=$(replace_placeholder "$prompt" "prev_eval_feedback" "")
    fi

    echo "$prompt"
}

# ══════════════════════════════════════════════════════════════
# 평가 프롬프트 빌드
# ══════════════════════════════════════════════════════════════
build_eval_prompt() {
    local design_content="$1"
    local eval_template="${PROMPTS_DIR}/evaluator/design_eval.md"

    if [[ ! -f "$eval_template" ]]; then
        echo "ERROR: eval template not found: $eval_template" >&2
        return 1
    fi

    local prompt
    prompt=$(cat "$eval_template")

    prompt=$(replace_placeholder "$prompt" "design_content" "$design_content")
    prompt=$(replace_placeholder "$prompt" "feature_request" "$FEATURE_CONTENT")

    echo "$prompt"
}

# ══════════════════════════════════════════════════════════════
# Step 1: GPT에 설계 요청
# ══════════════════════════════════════════════════════════════
run_design_write() {
    local version="$1"
    local design_file="${DESIGN_DIR}/design_v${version}.md"
    local prompt_file="${DESIGN_DIR}/design_v${version}.prompt.md"

    echo "━━━ [v${version}] Step 1: GPT 설계 작성 ━━━"

    # 프롬프트 빌드
    local design_prompt
    design_prompt=$(build_design_prompt "$version")
    if [[ $? -ne 0 ]]; then
        echo "ERROR: 설계 프롬프트 빌드 실패" >&2
        return 1
    fi

    # 프롬프트 저장
    echo "$design_prompt" > "$prompt_file"
    echo "프롬프트 저장: $prompt_file (${#design_prompt}자)"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] ChatGPT 호출 스킵"
        echo "[DRY-RUN] 설계 v${version} 샘플" > "$design_file"
        return 0
    fi

    # ChatGPT 새 채팅 + 전송
    echo "ChatGPT 새 채팅 시작..."
    chatgpt_call --mode=new_chat --tab="$CHATGPT_TAB" --project="$CHATGPT_PROJECT_URL" >/dev/null 2>&1
    sleep 2

    local start_time=$(date +%s)
    echo "ChatGPT 호출 중 (Tab $CHATGPT_TAB, timeout: ${TIMEOUT_DESIGN_WRITER}초)..."

    local response
    response=$(chatgpt_call --tab="$CHATGPT_TAB" --timeout="$TIMEOUT_DESIGN_WRITER" --retry "$design_prompt")

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # 오류 체크
    if is_chatgpt_error "$response"; then
        echo "ChatGPT 오류: $(get_error_message "$response")"
        return 1
    fi

    # 저장
    echo "$response" > "$design_file"
    echo "설계 저장: $design_file (${#response}자, ${duration}초)"

    # 상태 업데이트
    save_step_state "design" "$version" "write" "completed" "$design_file" "${#response}" "$duration"

    return 0
}

# ══════════════════════════════════════════════════════════════
# Step 2: Claude API에 평가 요청
# ══════════════════════════════════════════════════════════════
run_design_eval() {
    local version="$1"
    local design_file="${DESIGN_DIR}/design_v${version}.md"
    local eval_file="${DESIGN_DIR}/design_v${version}.eval.json"

    echo "━━━ [v${version}] Step 2: Claude 설계 평가 ━━━"

    if [[ ! -f "$design_file" ]]; then
        echo "ERROR: 설계 파일 없음: $design_file" >&2
        return 1
    fi

    local design_content
    design_content=$(cat "$design_file")

    # 평가 프롬프트 빌드
    local eval_prompt
    eval_prompt=$(build_eval_prompt "$design_content")

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Claude API 호출 스킵"
        echo '{"score": 80, "pass": false, "questions": [], "improvements": ["DRY-RUN"]}' > "$eval_file"
        return 0
    fi

    # Claude API 호출
    local start_time=$(date +%s)
    echo "Claude API 호출 중 (timeout: ${TIMEOUT_DESIGN_EVALUATOR}초)..."

    local response
    response=$(claude_call \
        --prompt="$eval_prompt" \
        --model="sonnet" \
        --format="text" \
        --timeout="$TIMEOUT_DESIGN_EVALUATOR")

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [[ $? -ne 0 ]]; then
        echo "Claude API 오류"
        return 1
    fi

    # JSON 추출 (응답에서 JSON 부분만)
    local json_only
    json_only=$(echo "$response" | python3 -c "
import sys, json, re
text = sys.stdin.read()
# JSON 블록 추출
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
    echo "$json_only" > "$eval_file"
    echo "평가 저장: $eval_file (${#json_only}자, ${duration}초)"

    # 상태 업데이트
    save_step_state "design" "$version" "eval" "completed" "$eval_file" "${#json_only}" "$duration"

    return 0
}

# ══════════════════════════════════════════════════════════════
# 점수 추출
# ══════════════════════════════════════════════════════════════
get_design_score() {
    local eval_file="$1"
    if [[ -f "$eval_file" ]]; then
        python3 -c "
import json
try:
    with open('$eval_file', 'r') as f:
        data = json.load(f)
    print(data.get('score', 0))
except:
    print(0)
" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# ══════════════════════════════════════════════════════════════
# 메인 루프
# ══════════════════════════════════════════════════════════════

# 로그 시작
exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Design Runner - 설계 자동 반복                               ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  시작 시간:   $(date '+%Y-%m-%d %H:%M:%S')"
echo "║  시작 버전:   v${VERSION}"
echo "║  최대 버전:   ${MAX_DESIGN_VERSIONS}회"
echo "║  목표 점수:   ${TARGET_DESIGN_SCORE}점"
echo "║  Dry-run:    ${DRY_RUN}"
echo "║  feature_list: ${FEATURE_LIST}"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

current_version="$VERSION"
max_version=$((VERSION + MAX_DESIGN_VERSIONS - 1))
current_score=0
loop_start_time=$(date +%s)

while [[ $current_version -le $max_version ]]; do
    echo ""
    echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
    echo "┃  설계 v${current_version} 시작                                              ┃"
    echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"

    # Step 1: GPT 설계 작성
    if ! run_design_write "$current_version"; then
        echo "설계 작성 실패 (v${current_version})"
        ((current_version++))
        continue
    fi

    # Step 2: Claude 설계 평가
    if ! run_design_eval "$current_version"; then
        echo "설계 평가 실패 (v${current_version})"
        ((current_version++))
        continue
    fi

    # 점수 확인
    local_eval_file="${DESIGN_DIR}/design_v${current_version}.eval.json"
    current_score=$(get_design_score "$local_eval_file")

    echo ""
    echo "설계 v${current_version} 결과: ${current_score}점"

    # 목표 점수 달성 확인
    if [[ $current_score -ge $TARGET_DESIGN_SCORE ]]; then
        echo ""
        echo "목표 점수 달성! (${current_score}점 >= ${TARGET_DESIGN_SCORE}점)"
        break
    fi

    # --once 모드면 1회만 실행
    if [[ "$ONCE" == "true" ]]; then
        echo ""
        echo "1회 실행 완료 (--once)"
        break
    fi

    # 다음 버전
    ((current_version++))

    if [[ $current_version -le $max_version ]]; then
        echo "점수 미달 (${current_score}점 < ${TARGET_DESIGN_SCORE}점) -> v${current_version} 진행"
    fi
done

# 최종 결과
loop_end_time=$(date +%s)
loop_duration=$((loop_end_time - loop_start_time))
loop_minutes=$((loop_duration / 60))
loop_seconds=$((loop_duration % 60))

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  설계 완료                                                    ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  최종 버전: v${current_version}"
echo "║  최종 점수: ${current_score}점"
if [[ $current_score -ge $TARGET_DESIGN_SCORE ]]; then
    echo "║  결과:      PASS"
else
    echo "║  결과:      최대 버전 도달"
fi
echo "║  소요 시간: ${loop_minutes}분 ${loop_seconds}초"
echo "╚══════════════════════════════════════════════════════════════╝"

echo ""
echo "로그: $LOG_FILE"

if [[ $current_score -ge $TARGET_DESIGN_SCORE ]]; then
    exit 0
else
    exit 1
fi
