#!/bin/bash
# suite_runner.sh - Suite 실행 (Baseline/Challenger 비교용)
# 사용법: ./suite_runner.sh --writer=champion --evaluator=frozen --suite=suite-5

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$LIB_DIR")"

# ══════════════════════════════════════════════════════════════
# 프로젝트 설정 로드
# ══════════════════════════════════════════════════════════════
if [[ -f "${PROJECT_DIR}/config/config.sh" ]]; then
    source "${PROJECT_DIR}/config/config.sh"
    load_chatgpt 2>/dev/null || true
else
    COMMON_DIR="$(dirname "$(dirname "$PROJECT_DIR")")/common"
    source "${COMMON_DIR}/chatgpt.sh" 2>/dev/null
fi

# ══════════════════════════════════════════════════════════════
# 공통 모듈 로드
# ══════════════════════════════════════════════════════════════
source "${PROJECT_DIR}/lib/util/parser.sh"
source "${PROJECT_DIR}/lib/util/research.sh"
source "${PROJECT_DIR}/lib/util/errors.sh"
source "${PROJECT_DIR}/lib/util/state.sh"
source "${PROJECT_DIR}/lib/util/template.sh"
source "${PROJECT_DIR}/lib/util/logger.sh"

# 모든 작업은 CHATGPT_TAB에서 실행

# ══════════════════════════════════════════════════════════════
# 인자 파싱
# ══════════════════════════════════════════════════════════════

WRITER="champion"
EVALUATOR="frozen"
SUITE="suite-5"
DATE=$(date +%Y-%m-%d)
DRY_RUN=false
START_FROM=1
START_VERSION=1
RUNS=5
ENABLE_RESEARCH=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --writer=*)
            WRITER="${1#*=}"
            shift
            ;;
        --evaluator=*)
            EVALUATOR="${1#*=}"
            shift
            ;;
        --suite=*)
            SUITE="${1#*=}"
            shift
            ;;
        --date=*)
            DATE="${1#*=}"
            shift
            ;;
        --start=*)
            START_FROM="${1#*=}"
            shift
            ;;
        --start-version=*)
            START_VERSION="${1#*=}"
            shift
            ;;
        --runs=*)
            RUNS="${1#*=}"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# 경로 설정
SUITES_DIR="${PROJECT_DIR}/suites"
PROMPTS_DIR="${PROJECT_DIR}/prompts"
RUNS_DIR="${PROJECT_DIR}/runs/${DATE}"

VARIANT="${WRITER}"
OUTPUT_DIR="${RUNS_DIR}/${VARIANT}"

# ══════════════════════════════════════════════════════════════
# Writer/Evaluator 프롬프트 로드
# ══════════════════════════════════════════════════════════════

load_writer_prompt_suite() {
    local writer_file="${PROMPTS_DIR}/writer/${WRITER}.md"
    local section_name="$1"
    local section_detail="$2"
    local topic="$3"
    local pages="$4"
    local previous_feedback="${5:-}"
    local research_block="${6:-}"

    # 안전한 템플릿 렌더링 사용
    local result
    result=$(render_writer_prompt "$writer_file" "$section_name" "$section_detail" "$topic" "$pages" "$research_block" "$previous_feedback")
    echo "$result"
}

load_evaluator_prompt_suite() {
    local evaluator_file="${PROMPTS_DIR}/evaluator/${EVALUATOR}.md"
    local section_name="$1"
    local content="$2"

    # 안전한 템플릿 렌더링 사용
    render_evaluator_prompt "$evaluator_file" "$section_name" "$content"
}

# ══════════════════════════════════════════════════════════════
# Challenger 프롬프트 개선 (Tab5 사용)
# ══════════════════════════════════════════════════════════════

improve_challenger_prompt() {
    local run_num="$1"
    local previous_output="$2"
    local previous_eval_json="$3"
    local section_id="$4"

    local challenger_prompt_file="${PROMPTS_DIR}/writer/challenger.md"
    local version_dir="${PROMPTS_DIR}/challenger"
    local version_file="${version_dir}/v${run_num}.md"
    local log_file="${version_dir}/v${run_num}.log"

    mkdir -p "$version_dir"

    # 현재 프롬프트 로드
    local current_prompt=""
    if [[ -f "$challenger_prompt_file" ]]; then
        current_prompt=$(cat "$challenger_prompt_file")
    fi

    # 평가 정보 추출 (공통 모듈 사용)
    local eval_score eval_tags eval_weaknesses eval_priority_fix
    eval_score=$(json_get "$previous_eval_json" "total_score")
    eval_tags=$(json_get_array "$previous_eval_json" "defect_tags")
    eval_priority_fix=$(json_get "$previous_eval_json" "priority_fix")

    eval_weaknesses=$(echo "$previous_eval_json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
ws = d.get('weaknesses', [])
for w in ws[:3]:
    print(f\"- 문제: {w.get('issue', '')}\\n  해결: {w.get('fix', '')}\")
" 2>/dev/null)

    # Tab5에 보낼 프롬프트 개선 요청 생성
    local critic_prompt
    critic_prompt=$(cat <<CRITIC_EOF
당신은 사업계획서 프롬프트 개선 전문가입니다.
아래 정보를 분석하여 개선된 새 프롬프트를 생성해주세요.

═══════════════════════════════════════════════════════════════
[1. 이전 프롬프트 (v$((run_num - 1)))]
═══════════════════════════════════════════════════════════════
$current_prompt

═══════════════════════════════════════════════════════════════
[2. 이전 프롬프트로 생성된 결과물 (일부)]
═══════════════════════════════════════════════════════════════
$previous_output

═══════════════════════════════════════════════════════════════
[3. 평가 결과]
═══════════════════════════════════════════════════════════════
- 점수: ${eval_score}점
- 결함 태그: ${eval_tags}
- 주요 약점:
${eval_weaknesses}
- 최우선 개선사항: ${eval_priority_fix}

═══════════════════════════════════════════════════════════════
[요청사항] ★ 중요 ★
═══════════════════════════════════════════════════════════════
1. 위 평가 결과의 문제점을 해결할 수 있도록 프롬프트를 개선하세요
2. 결함 태그(${eval_tags})가 발생하지 않도록 명시적 규칙을 추가하세요
3. 개선된 프롬프트 전문만 출력하세요 (설명 없이)
4. 프롬프트 시작은 "당신은" 또는 역할 설명으로 시작하세요
5. 기존 프롬프트의 구조({topic}, {section_name}, {section_detail}, {pages} 변수)는 유지하세요

개선된 프롬프트:
CRITIC_EOF
)

    # ChatGPT 호출 + 품질 기반 재시도
    local improved_prompt=""
    local tab5_retry_count=0
    local tab5_total_duration=0

    while [[ $tab5_retry_count -lt $MAX_STEP_RETRIES ]]; do
        ((tab5_retry_count++))
        log_info "Critic 호출 (시도 $tab5_retry_count/${MAX_STEP_RETRIES}, Section $section_id)..."

        local tab5_start_time=$(date +%s)
        improved_prompt=$(chatgpt_call --tab="$CHATGPT_TAB" --timeout="$TIMEOUT_CRITIC" --retry --section="$section_id" "$critic_prompt")
        local tab5_end_time=$(date +%s)
        local tab5_duration=$((tab5_end_time - tab5_start_time))
        tab5_total_duration=$((tab5_total_duration + tab5_duration))

        echo "    ⏱️  Tab5 시도${tab5_retry_count}: ${#improved_prompt}자, ${tab5_duration}초" >&2

        # 에러 체크 (공통 모듈 사용)
        if is_chatgpt_error "$improved_prompt"; then
            log_warn "Tab5 에러 응답: $(get_error_message "$improved_prompt")"
            if [[ $tab5_retry_count -lt $MAX_STEP_RETRIES ]]; then
                echo "    🔄 에러로 인해 새 채팅 시작 후 재시도..." >&2
                chatgpt_call --mode=new_chat --tab="$tab" >/dev/null 2>&1
                sleep 2
            fi
            continue
        fi

        # 응답 품질 검사 (공통 모듈 사용)
        if check_response_length "$improved_prompt" 100; then
            log_info "Tab5 응답 품질 OK (${#improved_prompt}자)"
            break
        fi

        log_warn "Tab5 응답 짧음 (${#improved_prompt}자 < 100자)"

        if [[ $tab5_retry_count -lt $MAX_STEP_RETRIES ]]; then
            echo "    🔄 새 채팅 시작 후 재시도..." >&2
            chatgpt_call --mode=new_chat --tab="$tab" >/dev/null 2>&1
            sleep 2
        fi
    done

    echo "    ⏱️  Tab5 총: ${#improved_prompt}자, ${tab5_total_duration}초 (${tab5_retry_count}회 시도)" >&2

    # 최종 품질 검사
    if ! check_response_length "$improved_prompt" 100; then
        echo "    ❌ Tab5 재시도 실패 (${tab5_retry_count}회), 기존 프롬프트 유지" >&2
        return 1
    fi

    # 버전 파일 저장
    cat > "$version_file" <<VERSION_EOF
# Challenger Prompt - v${run_num}
# Generated: $(date +"%Y-%m-%d %H:%M:%S")
# Based on: v$((run_num - 1)) evaluation (score: ${eval_score})
# Defects addressed: ${eval_tags}

$improved_prompt
VERSION_EOF

    echo "    Saved: $version_file" >&2

    # 로그 저장
    cat > "$log_file" <<LOG_EOF
# Challenger v${run_num} Generation Log
# Generated: $(date +"%Y-%m-%d %H:%M:%S")

## Input
- Previous version: v$((run_num - 1))
- Previous score: ${eval_score}
- Defect tags: ${eval_tags}

## Evaluation Summary
${eval_weaknesses}

Priority fix: ${eval_priority_fix}

## Prompt Request (sent to Tab5)
$critic_prompt
LOG_EOF

    echo "    Saved: $log_file" >&2

    # challenger.md 업데이트
    echo "$improved_prompt" > "$challenger_prompt_file"
    echo "    Updated: $challenger_prompt_file" >&2

    return 0
}

# ══════════════════════════════════════════════════════════════
# 검증 함수 (Watchdog) - 상태 관리 모듈 사용
# ══════════════════════════════════════════════════════════════

# 런타임 상태 초기화
runtime_reset

# 테스트 시작/종료 배너
print_test_start() {
    runtime_set "test_start_time" "$(date +%s)"
    local start_datetime=$(date '+%Y-%m-%d %H:%M:%S')

    echo "" >&2
    echo "╔══════════════════════════════════════════════════════════════╗" >&2
    echo "║  🚀 테스트 시작                                              ║" >&2
    echo "╠══════════════════════════════════════════════════════════════╣" >&2
    echo "║  시작 시간: $start_datetime                            ║" >&2
    echo "║  Suite:     $SUITE                                           ║" >&2
    echo "║  Writer:    $WRITER                                          ║" >&2
    echo "║  Evaluator: $EVALUATOR                                       ║" >&2
    echo "║  Runs:      $RUNS 버전                                       ║" >&2
    echo "║  출력 경로: $OUTPUT_DIR                                      ║" >&2
    echo "╚══════════════════════════════════════════════════════════════╝" >&2
    echo "" >&2
}

print_test_end() {
    local success="$1"
    local total="$2"
    local test_start=$(runtime_get "test_start_time")
    local end_time=$(date +%s)
    local duration=$((end_time - test_start))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    local end_datetime=$(date '+%Y-%m-%d %H:%M:%S')

    echo "" >&2
    echo "╔══════════════════════════════════════════════════════════════╗" >&2
    echo "║  🏁 테스트 종료                                              ║" >&2
    echo "╠══════════════════════════════════════════════════════════════╣" >&2
    echo "║  종료 시간: $end_datetime                            ║" >&2
    echo "║  소요 시간: ${minutes}분 ${seconds}초                        ║" >&2
    echo "║  성공률:    $success / $total                                ║" >&2
    echo "╚══════════════════════════════════════════════════════════════╝" >&2
}

print_version_start() {
    local run_num="$1"
    local sample_id="$2"
    runtime_set "version_start_time" "$(date +%s)"
    local start_time=$(date '+%H:%M:%S')

    echo "" >&2
    echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓" >&2
    echo "┃  📝 버전 v$run_num 시작 [$start_time]                        ┃" >&2
    echo "┃  Sample: $sample_id                                          ┃" >&2
    echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛" >&2
}

print_version_end() {
    local run_num="$1"
    local score="$2"
    local version_start=$(runtime_get "version_start_time")
    local end_time=$(date +%s)
    local duration=$((end_time - version_start))
    local end_clock=$(date '+%H:%M:%S')

    echo "" >&2
    echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓" >&2
    echo "┃  ✅ 버전 v$run_num 완료 [$end_clock] (${duration}초)         ┃" >&2
    echo "┃  점수: ${score}점                                            ┃" >&2
    echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛" >&2
}

validate_version() {
    local run_num="$1"
    local sample_id="$2"
    local output_file="$3"
    local eval_file="$4"
    local prompt_file="${PROMPTS_DIR}/writer/challenger.md"
    local version_dir="${PROMPTS_DIR}/challenger"
    local version_file="${version_dir}/v${run_num}.md"

    local errors=()
    local warnings=()
    local checks_passed=0
    local checks_total=0

    local check_time=$(date '+%H:%M:%S')
    echo "" >&2
    echo "  ┌─ 🔍 Watchdog 검증 [v$run_num] @ $check_time ────────────" >&2

    # 1. Tab5 프롬프트 생성 확인 (v2부터)
    if [[ "$WRITER" == "challenger" && $run_num -gt 1 ]]; then
        ((checks_total++))
        echo "  │ [1/5] Tab5 프롬프트 파일 확인 중..." >&2
        if [[ ! -f "$version_file" ]]; then
            errors+=("Tab5 실패: 프롬프트 v${run_num} 파일 미생성")
            echo "  │       ❌ 파일 없음: $version_file" >&2
        else
            ((checks_passed++))
            local prompt_size=$(wc -c < "$version_file" | tr -d ' ')
            echo "  │       ✅ 생성됨 (${prompt_size}자)" >&2
        fi
    fi

    # 2. 프롬프트 변경 확인 (v2부터)
    local last_hash=$(runtime_get "last_prompt_hash")
    if [[ "$WRITER" == "challenger" && $run_num -gt 1 && -f "$prompt_file" ]]; then
        ((checks_total++))
        echo "  │ [2/5] 프롬프트 변경 여부 확인 중..." >&2
        local current_hash
        current_hash=$(md5 -q "$prompt_file" 2>/dev/null || md5sum "$prompt_file" | cut -d' ' -f1)

        if [[ -n "$last_hash" && "$current_hash" == "$last_hash" ]]; then
            warnings+=("프롬프트 미변경: v$((run_num-1))과 동일 hash")
            echo "  │       ⚠️  미변경 (hash: ${current_hash:0:8}...)" >&2
        else
            ((checks_passed++))
            echo "  │       ✅ 변경됨 (hash: ${current_hash:0:8}...)" >&2
        fi
        runtime_set "last_prompt_hash" "$current_hash"
    elif [[ "$WRITER" == "challenger" && $run_num -eq 1 && -f "$prompt_file" ]]; then
        local initial_hash
        initial_hash=$(md5 -q "$prompt_file" 2>/dev/null || md5sum "$prompt_file" | cut -d' ' -f1)
        runtime_set "last_prompt_hash" "$initial_hash"
        echo "  │ [2/5] 초기 프롬프트 hash 저장: ${initial_hash:0:8}..." >&2
    fi

    # 3. 출력 품질 확인
    ((checks_total++))
    echo "  │ [3/5] Writer 출력 품질 확인 중..." >&2
    if [[ -f "$output_file" ]]; then
        local output_size
        output_size=$(wc -c < "$output_file" | tr -d ' ')

        if [[ $output_size -lt 500 ]]; then
            errors+=("출력 품질 불량: ${output_size}자 (최소 500자)")
            echo "  │       ❌ 불량 (${output_size}자 < 500자 최소)" >&2
            runtime_increment "consecutive_failures"
        else
            ((checks_passed++))
            echo "  │       ✅ 정상 (${output_size}자)" >&2
            runtime_set "consecutive_failures" "0"
        fi
    else
        errors+=("출력 파일 없음")
        echo "  │       ❌ 파일 없음: $output_file" >&2
        runtime_increment "consecutive_failures"
    fi

    # 4. 평가 점수 확인
    ((checks_total++))
    echo "  │ [4/5] Evaluator 평가 점수 확인 중..." >&2
    if [[ -f "$eval_file" ]]; then
        local score
        score=$(python3 -c "import json; print(json.load(open('$eval_file')).get('total_score', 0))" 2>/dev/null)

        if [[ -n "$score" && "$score" -gt 0 ]]; then
            ((checks_passed++))
            echo "  │       ✅ 점수: ${score}점" >&2
            print_version_end "$run_num" "$score"
        else
            warnings+=("평가 점수 0점")
            echo "  │       ⚠️  점수: 0점 또는 파싱 실패" >&2
        fi
    else
        warnings+=("평가 파일 없음")
        echo "  │       ⚠️  파일 없음: $eval_file" >&2
    fi

    # 5. 연속 실패 확인
    ((checks_total++))
    echo "  │ [5/5] 연속 실패 카운터 확인 중..." >&2
    local consecutive_failures=$(runtime_get "consecutive_failures")
    local max_failures="${MAX_CONSECUTIVE_FAILURES:-3}"

    if [[ $consecutive_failures -ge $max_failures ]]; then
        errors+=("연속 실패 ${consecutive_failures}회 → 자동 중단")
        echo "  │       ❌ ${consecutive_failures}회 연속 실패 (한계: $max_failures)" >&2
    else
        ((checks_passed++))
        echo "  │       ✅ 연속 실패: ${consecutive_failures}회 (한계: $max_failures)" >&2
    fi

    # 요약
    echo "  ├────────────────────────────────────────────────" >&2
    echo "  │ 📊 검증 결과: ${checks_passed}/${checks_total} 통과" >&2

    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo "  │ ⚠️  경고 ${#warnings[@]}건:" >&2
        for warn in "${warnings[@]}"; do
            echo "  │     - $warn" >&2
        done
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "  │ ❌ 오류 ${#errors[@]}건:" >&2
        for err in "${errors[@]}"; do
            echo "  │     - $err" >&2
        done
    fi

    echo "  └────────────────────────────────────────────────" >&2

    # 치명적 오류 시 중단
    if [[ ${#errors[@]} -gt 0 ]]; then
        if [[ $consecutive_failures -ge $max_failures ]]; then
            echo "" >&2
            echo "🛑 Watchdog: 연속 ${consecutive_failures}회 실패로 테스트 자동 중단" >&2
            echo "   마지막 오류: ${errors[-1]}" >&2
            return 2
        fi
        return 1
    fi

    return 0
}

# ══════════════════════════════════════════════════════════════
# 자동 재시도 로직
# ══════════════════════════════════════════════════════════════

retry_writer() {
    local sample_id="$1"
    local sample_file="$2"
    local previous_feedback="$3"
    local retry_count="${4:-1}"

    log_warn "Writer 재시도 ($retry_count/${MAX_STEP_RETRIES})..."

    local full_path="${SUITES_DIR}/${sample_file}"
    local section_name topic body pages section_id
    section_name=$(parse_front_matter "$full_path" "section_name")
    section_id=$(parse_front_matter "$full_path" "section")
    body=$(get_body "$full_path")
    topic=$(extract_topic "$full_path")
    pages=$(extract_pages "$full_path")

    # 리서치 블록 로드 (공통 모듈 사용)
    local research_block
    research_block=$(load_research_block "$section_id")

    # Writer 프롬프트 생성
    local writer_prompt
    writer_prompt=$(load_writer_prompt_suite "$section_name" "$body" "$topic" "$pages" "$previous_feedback" "$research_block")

    local out_file="${OUTPUT_DIR}/${sample_id}.out.md"
    local writer_timeout
    writer_timeout=$(get_timeout_for "writer")

    log_info "Writer 재시도..."
    chatgpt_call --mode=new_chat --tab="$CHATGPT_TAB" --project="$CHATGPT_PROJECT_URL" >/dev/null 2>&1
    sleep 1
    local writer_response
    writer_response=$(chatgpt_call --tab="$CHATGPT_TAB" --timeout="$writer_timeout" --retry --section="$section_id" "$writer_prompt")

    # 에러 체크 (공통 모듈 사용)
    if is_chatgpt_error "$writer_response"; then
        log_error "Writer 재시도 에러: $(get_error_message "$writer_response")"
        return 1
    fi

    echo "$writer_response" > "$out_file"
    local output_size=${#writer_response}

    if [[ $output_size -ge 500 ]]; then
        log_ok "Writer 재시도 성공 (${output_size}자)"
        return 0
    else
        log_error "Writer 재시도 실패 (${output_size}자 < 500자)"
        return 1
    fi
}

retry_evaluator() {
    local sample_id="$1"
    local retry_count="${2:-1}"

    log_warn "Evaluator 재시도 ($retry_count/${MAX_STEP_RETRIES})..."

    local out_file="${OUTPUT_DIR}/${sample_id}.out.md"
    local eval_file="${OUTPUT_DIR}/${sample_id}.eval.json"
    local eval_prompt_file="${OUTPUT_DIR}/${sample_id}.eval_prompt.md"

    if [[ ! -f "$out_file" ]]; then
        log_error "출력 파일 없음: $out_file"
        return 1
    fi

    local writer_response
    writer_response=$(cat "$out_file")

    local section_name="섹션"
    if [[ -f "$eval_prompt_file" ]]; then
        section_name=$(head -20 "$eval_prompt_file" | grep -oP '(?<=섹션: ).*' || echo "섹션")
    fi

    local evaluator_prompt
    evaluator_prompt=$(load_evaluator_prompt_suite "$section_name" "$writer_response")

    local eval_timeout
    eval_timeout=$(get_timeout_for "evaluator")

    log_info "Evaluator 새 채팅 시작 후 재시도..."
    chatgpt_call --mode=new_chat --tab="$CHATGPT_TAB" --project="$CHATGPT_PROJECT_URL" >/dev/null 2>&1
    sleep 1

    local eval_response
    eval_response=$(chatgpt_call --tab="$CHATGPT_TAB" --timeout="$eval_timeout" --retry "$evaluator_prompt")

    # 에러 체크 (공통 모듈 사용)
    if is_chatgpt_error "$eval_response"; then
        log_error "Evaluator 재시도 에러: $(get_error_message "$eval_response")"
        return 1
    fi

    # JSON 추출 (공통 모듈 사용)
    local json_only
    json_only=$(extract_json "$eval_response")

    echo "$json_only" > "$eval_file"

    local score
    score=$(json_get "$json_only" "total_score")
    local eval_size=${#json_only}

    if [[ -n "$score" && "$score" -gt 0 && $eval_size -gt 50 ]]; then
        log_ok "Evaluator 재시도 성공 (점수: ${score}, ${eval_size}자)"
        echo "  Score: $score" >&2
        return 0
    else
        log_error "Evaluator 재시도 실패 (점수: ${score:-0}, ${eval_size}자)"
        return 1
    fi
}

check_and_retry() {
    local sample_id="$1"
    local sample_file="$2"
    local previous_feedback="$3"

    local out_file="${OUTPUT_DIR}/${sample_id}.out.md"
    local eval_file="${OUTPUT_DIR}/${sample_id}.eval.json"

    local writer_ok=false
    local eval_ok=false

    # Writer 출력 확인
    if [[ -f "$out_file" ]]; then
        local output_size
        output_size=$(wc -c < "$out_file" | tr -d ' ')
        if [[ $output_size -ge 500 ]]; then
            writer_ok=true
        fi
    fi

    # Eval 출력 확인
    if [[ -f "$eval_file" ]]; then
        local eval_size
        eval_size=$(wc -c < "$eval_file" | tr -d ' ')
        local score
        score=$(python3 -c "import json; print(json.load(open('$eval_file')).get('total_score', 0))" 2>/dev/null || echo "0")
        if [[ $eval_size -gt 50 && -n "$score" && "$score" -gt 0 ]]; then
            eval_ok=true
        fi
    fi

    local retry_count=0

    # Writer 실패 시 재시도
    while [[ "$writer_ok" != "true" && $retry_count -lt $MAX_STEP_RETRIES ]]; do
        ((retry_count++))
        if retry_writer "$sample_id" "$sample_file" "$previous_feedback" "$retry_count"; then
            writer_ok=true
            eval_ok=false
        fi
    done

    # Writer 성공 후 Eval 실패 시 재시도
    retry_count=0
    while [[ "$writer_ok" == "true" && "$eval_ok" != "true" && $retry_count -lt $MAX_STEP_RETRIES ]]; do
        ((retry_count++))
        if retry_evaluator "$sample_id" "$retry_count"; then
            eval_ok=true
        fi
    done

    if [[ "$writer_ok" == "true" && "$eval_ok" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════
# 메인 실행 로직
# ══════════════════════════════════════════════════════════════

run_sample() {
    local sample_id="$1"
    local sample_file="$2"
    local previous_feedback="$3"

    local full_path="${SUITES_DIR}/${sample_file}"

    if [[ ! -f "$full_path" ]]; then
        echo "ERROR: Sample file not found: $full_path" >&2
        return 1
    fi

    echo "  Processing: $sample_id" >&2

    # 메타데이터 추출 (공통 모듈 사용)
    local section_name section_id topic body pages
    section_name=$(parse_front_matter "$full_path" "section_name")
    section_id=$(parse_front_matter "$full_path" "section")
    body=$(get_body "$full_path")
    topic=$(extract_topic "$full_path")
    pages=$(extract_pages "$full_path")

    # 리서치 블록 로드 (공통 모듈 사용)
    local research_block=""
    if has_section_research "$section_id"; then
        research_block=$(load_research_block "$section_id")
        log_info "기존 리서치 로드됨 (${#research_block} chars, pattern: ${section_id}_*.md)"
    fi

    # Writer 프롬프트 생성
    local writer_prompt
    writer_prompt=$(load_writer_prompt_suite "$section_name" "$body" "$topic" "$pages" "$previous_feedback" "$research_block")

    # 출력 파일 경로
    local out_file="${OUTPUT_DIR}/${sample_id}.out.md"
    local eval_file="${OUTPUT_DIR}/${sample_id}.eval.json"
    local prompt_file="${OUTPUT_DIR}/${sample_id}.prompt.md"
    local eval_prompt_file="${OUTPUT_DIR}/${sample_id}.eval_prompt.md"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] Would generate: $out_file" >&2
        echo "  [DRY-RUN] Writer prompt length: ${#writer_prompt}" >&2
        return 0
    fi

    # Writer 프롬프트 저장
    echo "$writer_prompt" > "$prompt_file"
    log_info "Writer 프롬프트 저장 (${#writer_prompt}자): $(basename "$prompt_file")"

    # ChatGPT로 Writer 실행
    local writer_response
    local writer_timeout
    writer_timeout=$(get_timeout_for "writer")

    # 항상 새 채팅 시작
    log_info "Writer: 새 채팅 시작..."
    chatgpt_call --mode=new_chat --tab="$CHATGPT_TAB" --project="$CHATGPT_PROJECT_URL" >/dev/null 2>&1
    sleep 1

    log_info "Calling Writer (Section $section_id)..."
    local writer_start_time=$(date +%s)
    writer_response=$(chatgpt_call --tab="$CHATGPT_TAB" --timeout="$writer_timeout" --retry --section="$section_id" "$writer_prompt")
    local writer_end_time=$(date +%s)
    local writer_duration=$((writer_end_time - writer_start_time))
    echo "  ⏱️  Writer: ${#writer_response}자, ${writer_duration}초" >&2

    # 에러 체크 (공통 모듈 사용)
    if is_chatgpt_error "$writer_response"; then
        log_error "Writer 에러 응답: $(get_error_message "$writer_response")"
        return 1
    fi

    # Writer 응답 저장
    echo "$writer_response" > "$out_file"
    echo "  Saved: $out_file" >&2

    # Writer 품질 확인 (공통 모듈 사용)
    if ! is_valid_writer_response "$writer_response"; then
        log_warn "Writer 응답 품질 불량 (${#writer_response}자 < 500자) - Evaluator 건너뜀"
        return 1
    fi

    # Evaluator 프롬프트 생성
    local evaluator_prompt
    evaluator_prompt=$(load_evaluator_prompt_suite "$section_name" "$writer_response")

    # Evaluator 프롬프트 저장
    echo "$evaluator_prompt" > "$eval_prompt_file"
    log_info "Evaluator 프롬프트 저장 (${#evaluator_prompt}자): $(basename "$eval_prompt_file")"

    # ChatGPT로 Evaluator 실행
    local eval_response
    local eval_timeout
    eval_timeout=$(get_timeout_for "evaluator")

    # 항상 새 채팅 시작
    log_info "Evaluator: 새 채팅 시작..."
    chatgpt_call --mode=new_chat --tab="$CHATGPT_TAB" --project="$CHATGPT_PROJECT_URL" >/dev/null 2>&1
    sleep 1

    log_info "Calling Evaluator..."
    local eval_start_time=$(date +%s)
    eval_response=$(chatgpt_call --tab="$CHATGPT_TAB" --timeout="$eval_timeout" --retry "$evaluator_prompt")
    local eval_end_time=$(date +%s)
    local eval_duration=$((eval_end_time - eval_start_time))

    # 에러 체크 (공통 모듈 사용)
    if is_chatgpt_error "$eval_response"; then
        log_error "Evaluator 에러 응답: $(get_error_message "$eval_response")"
        return 1
    fi

    # JSON 추출 (공통 모듈 사용)
    local json_only
    json_only=$(extract_json "$eval_response")

    echo "$json_only" > "$eval_file"
    echo "  Saved: $eval_file" >&2

    # 점수 출력 (공통 모듈 사용)
    local score
    score=$(json_get "$json_only" "total_score")
    echo "  ⏱️  Evaluator: ${#json_only}자, 점수: ${score}, ${eval_duration}초" >&2
}

run_suite() {
    local suite_file="${SUITES_DIR}/${SUITE}.yaml"

    if [[ ! -f "$suite_file" ]]; then
        echo "ERROR: Suite file not found: $suite_file" >&2
        exit 1
    fi

    print_test_start

    mkdir -p "$OUTPUT_DIR"

    # 샘플 목록 가져오기 (공통 모듈 사용)
    local samples
    samples=$(get_suite_samples "$suite_file")

    local total=0
    local success=0

    echo "Processing samples (${RUNS}회 반복)..."
    echo ""

    local current=0
    while IFS='|' read -r sample_id sample_file; do
        if [[ -n "$sample_id" ]]; then
            ((current++))
            if [[ $current -lt $START_FROM ]]; then
                echo "  Skipping: $sample_id (sample $current < start $START_FROM)"
                echo ""
                continue
            fi

            local previous_feedback=""
            local previous_output=""
            local previous_eval_json=""

            local full_path="${SUITES_DIR}/${sample_file}"
            local section_id
            section_id=$(parse_front_matter "$full_path" "section")

            # START_VERSION > 1이면 이전 버전의 피드백 로드
            if [[ $START_VERSION -gt 1 ]]; then
                local prev_version=$((START_VERSION - 1))
                local prev_out_file="${OUTPUT_DIR}/${sample_id}_v${prev_version}.out.md"
                local prev_eval_file="${OUTPUT_DIR}/${sample_id}_v${prev_version}.eval.json"

                if [[ -f "$prev_out_file" ]]; then
                    previous_output=$(head -80 "$prev_out_file")
                    log_info "이전 버전(v${prev_version}) 출력 로드: $(basename "$prev_out_file")"
                fi

                if [[ -f "$prev_eval_file" ]]; then
                    previous_eval_json=$(cat "$prev_eval_file")
                    previous_feedback=$(extract_feedback_from_json "$previous_eval_json")
                    log_info "이전 버전(v${prev_version}) 피드백 로드: $(basename "$prev_eval_file")"
                else
                    log_warn "이전 버전(v${prev_version}) 평가 파일 없음 - 피드백 없이 진행"
                fi
            fi

            for run_num in $(seq $START_VERSION $RUNS); do
                ((total++))
                local run_sample_id="${sample_id}_v${run_num}"

                if type log_set_context &>/dev/null; then
                    log_set_context "$sample_id" "v${run_num}"
                fi

                print_version_start "$run_num" "$sample_id"

                # Challenger 모드: v2부터 Tab5로 프롬프트 개선
                if [[ "$WRITER" == "challenger" && $run_num -gt 1 && -n "$previous_output" ]]; then
                    echo "    → Tab5: 프롬프트 v${run_num} 생성 중..." >&2
                    improve_challenger_prompt "$run_num" "$previous_output" "$previous_eval_json" "$section_id"
                fi

                if run_sample "$run_sample_id" "$sample_file" "$previous_feedback"; then
                    ((success++))
                fi

                if ! check_and_retry "$run_sample_id" "$sample_file" "$previous_feedback"; then
                    log_warn "품질 검사 실패 - 재시도 한계 도달 (v${run_num})"
                fi

                local out_file="${OUTPUT_DIR}/${run_sample_id}.out.md"
                local eval_file="${OUTPUT_DIR}/${run_sample_id}.eval.json"

                if [[ -f "$out_file" ]]; then
                    previous_output=$(head -80 "$out_file")
                fi

                if [[ -f "$eval_file" ]]; then
                    previous_eval_json=$(cat "$eval_file")
                    previous_feedback=$(extract_feedback_from_json "$previous_eval_json")
                fi

                validate_version "$run_num" "$sample_id" "$out_file" "$eval_file"
                local validate_result=$?

                if [[ $validate_result -eq 2 ]]; then
                    echo "🛑 테스트 중단됨 (Watchdog)" >&2
                    break 2
                fi
            done
            echo ""
        fi
    done <<< "$samples"

    print_test_end "$success" "$total"
    generate_summary
}

generate_summary() {
    local summary_file="${OUTPUT_DIR}/summary.json"
    local test_start=$(runtime_get "test_start_time")

    python3 -c "
import json
import os
import re
from glob import glob
from collections import defaultdict

output_dir = '$OUTPUT_DIR'
runs = $RUNS
eval_files = glob(os.path.join(output_dir, '*.eval.json'))

sample_versions = defaultdict(list)
all_tags = []

for ef in eval_files:
    filename = os.path.basename(ef).replace('.eval.json', '')
    match = re.match(r'(.+)_v(\d+)', filename)
    if match:
        sample_id = match.group(1)
        version_num = int(match.group(2))
    else:
        sample_id = filename
        version_num = 1

    try:
        with open(ef, 'r') as f:
            data = json.load(f)
        score = data.get('total_score', 0)
        tags = data.get('defect_tags', [])
        all_tags.extend(tags)
        sample_versions[sample_id].append({
            'version': version_num,
            'score': score,
            'tags': tags
        })
    except:
        sample_versions[sample_id].append({
            'version': version_num,
            'score': 0,
            'tags': [],
            'error': 'parse_failed'
        })

results = []
total_avg_score = 0

for sample_id, version_list in sorted(sample_versions.items()):
    scores = [v['score'] for v in version_list]
    avg_score = sum(scores) / len(scores) if scores else 0
    min_score = min(scores) if scores else 0
    max_score = max(scores) if scores else 0
    variance = sum((s - avg_score) ** 2 for s in scores) / len(scores) if scores else 0

    total_avg_score += avg_score
    results.append({
        'sample_id': sample_id,
        'versions': len(version_list),
        'avg_score': round(avg_score, 2),
        'min_score': min_score,
        'max_score': max_score,
        'variance': round(variance, 2),
        'all_versions': version_list
    })

overall_avg = total_avg_score / len(results) if results else 0

from collections import Counter
tag_freq = dict(Counter(all_tags))

import datetime
end_time = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
start_timestamp = ${test_start:-0}
end_timestamp = int(datetime.datetime.now().timestamp())
duration_sec = end_timestamp - start_timestamp if start_timestamp > 0 else 0

summary = {
    'suite': '$SUITE',
    'writer': '$WRITER',
    'evaluator': '$EVALUATOR',
    'date': '$DATE',
    'end_time': end_time,
    'duration_sec': duration_sec,
    'duration_min': round(duration_sec / 60, 1),
    'runs_per_sample': runs,
    'sample_count': len(results),
    'avg_score': round(overall_avg, 2),
    'total_tags': len(all_tags),
    'tag_frequency': tag_freq,
    'results': results
}

with open('$summary_file', 'w') as f:
    json.dump(summary, f, indent=2, ensure_ascii=False)

print(f'Summary saved: $summary_file')
print(f'Average score: {overall_avg:.2f}')
print(f'Total defect tags: {len(all_tags)}')
"
}

# ══════════════════════════════════════════════════════════════
# 실행
# ══════════════════════════════════════════════════════════════

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_suite
fi
