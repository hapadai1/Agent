#!/bin/bash
# state.sh - 상태 관리 공통 모듈
# 사용법: source lib/util/state.sh

# ══════════════════════════════════════════════════════════════
# 상태 파일 관리
# ══════════════════════════════════════════════════════════════

# 기본 상태 파일 경로 설정
_STATE_DIR="${PROJECT_DIR:-$(pwd)}/state"
_STATE_FILE="${_STATE_DIR}/current.json"

# 상태 디렉토리 초기화
# 사용법: init_state_dir ["/custom/path"]
init_state_dir() {
    local custom_dir="${1:-$_STATE_DIR}"
    _STATE_DIR="$custom_dir"
    _STATE_FILE="${_STATE_DIR}/current.json"
    mkdir -p "$_STATE_DIR"
}

# 상태 파일 경로 반환
# 사용법: path=$(get_state_file)
get_state_file() {
    echo "$_STATE_FILE"
}

# ══════════════════════════════════════════════════════════════
# 상태 저장
# ══════════════════════════════════════════════════════════════

# 단일 스텝 상태 저장
# 사용법: save_step_state "s1_2" 1 "writer" "completed" "$output_file" 1500 45
save_step_state() {
    local section="$1"
    local version="$2"
    local step="$3"
    local status="$4"
    local output_file="$5"
    local chars="${6:-0}"
    local duration="${7:-0}"

    mkdir -p "$_STATE_DIR"

    cat > "$_STATE_FILE" <<EOF
{
  "section": "$section",
  "version": $version,
  "step": "$step",
  "status": "$status",
  "timestamp": "$(date -Iseconds)",
  "files": {
    "output": "$output_file"
  },
  "metrics": {
    "output_chars": $chars,
    "duration_sec": $duration
  }
}
EOF
}

# 간단한 상태 저장 (호환성 유지)
# 사용법: save_state "completed" "$output_file" 1500 45
save_state() {
    local status="$1"
    local output_file="$2"
    local chars="${3:-0}"
    local duration="${4:-0}"

    # 전역 변수에서 SECTION, VERSION, STEP 사용
    save_step_state \
        "${SECTION:-unknown}" \
        "${VERSION:-1}" \
        "${STEP:-unknown}" \
        "$status" \
        "$output_file" \
        "$chars" \
        "$duration"
}

# ══════════════════════════════════════════════════════════════
# 상태 읽기
# ══════════════════════════════════════════════════════════════

# 상태 파일 존재 확인
# 사용법: if has_state; then ... fi
has_state() {
    [[ -f "$_STATE_FILE" ]]
}

# 상태 파일에서 값 읽기
# 사용법: section=$(read_state "section")
read_state() {
    local key="$1"

    if [[ ! -f "$_STATE_FILE" ]]; then
        echo ""
        return 1
    fi

    python3 -c "
import json
try:
    with open('$_STATE_FILE', 'r') as f:
        data = json.load(f)
    keys = '$key'.split('.')
    result = data
    for k in keys:
        if isinstance(result, dict):
            result = result.get(k, '')
        else:
            result = ''
            break
    print(result)
except:
    print('')
" 2>/dev/null
}

# 전체 상태 JSON 읽기
# 사용법: json=$(read_state_json)
read_state_json() {
    if [[ -f "$_STATE_FILE" ]]; then
        cat "$_STATE_FILE"
    else
        echo "{}"
    fi
}

# ══════════════════════════════════════════════════════════════
# 상태 기반 복구
# ══════════════════════════════════════════════════════════════

# 마지막 상태에서 다음 스텝 결정
# 사용법: next_step=$(get_next_step)
get_next_step() {
    local last_step
    local last_status

    last_step=$(read_state "step")
    last_status=$(read_state "status")

    # 에러/실패 상태면 같은 스텝 재시도
    if [[ "$last_status" == "error" || "$last_status" == "failed" ]]; then
        echo "$last_step"
        return
    fi

    # 완료된 상태면 다음 스텝
    case "$last_step" in
        prompt)
            echo "writer"
            ;;
        writer)
            echo "evaluator"
            ;;
        evaluator)
            echo "prompt"  # 다음 버전의 prompt
            ;;
        *)
            echo "prompt"  # 기본값
            ;;
    esac
}

# 복구 가능 여부 확인
# 사용법: if can_resume; then resume; fi
can_resume() {
    if [[ ! -f "$_STATE_FILE" ]]; then
        return 1
    fi

    local status
    status=$(read_state "status")

    # completed 또는 error 상태면 복구 가능
    [[ "$status" == "completed" || "$status" == "error" || "$status" == "failed" ]]
}

# 복구 정보 출력
# 사용법: print_resume_info
print_resume_info() {
    if [[ ! -f "$_STATE_FILE" ]]; then
        echo "복구할 상태가 없습니다." >&2
        return 1
    fi

    local section version step status timestamp
    section=$(read_state "section")
    version=$(read_state "version")
    step=$(read_state "step")
    status=$(read_state "status")
    timestamp=$(read_state "timestamp")

    echo "────────────────────────────────────" >&2
    echo "  마지막 상태" >&2
    echo "────────────────────────────────────" >&2
    echo "  Section:   $section" >&2
    echo "  Version:   v$version" >&2
    echo "  Step:      $step" >&2
    echo "  Status:    $status" >&2
    echo "  Timestamp: $timestamp" >&2
    echo "────────────────────────────────────" >&2
}

# ══════════════════════════════════════════════════════════════
# 런타임 상태 (전역 변수 관리)
# ══════════════════════════════════════════════════════════════

# bash 3.2 호환 (associative array 대신 개별 변수 사용)
_RUNTIME_consecutive_failures=0
_RUNTIME_last_prompt_hash=""
_RUNTIME_test_start_time=""
_RUNTIME_version_start_time=""
_RUNTIME_last_writer_section=""

# 런타임 상태 설정
# 사용법: runtime_set "consecutive_failures" "3"
runtime_set() {
    local key="$1"
    local value="$2"

    case "$key" in
        consecutive_failures)
            _RUNTIME_consecutive_failures="$value"
            ;;
        last_prompt_hash)
            _RUNTIME_last_prompt_hash="$value"
            ;;
        test_start_time)
            _RUNTIME_test_start_time="$value"
            ;;
        version_start_time)
            _RUNTIME_version_start_time="$value"
            ;;
        last_writer_section)
            _RUNTIME_last_writer_section="$value"
            ;;
    esac
}

# 런타임 상태 읽기
# 사용법: value=$(runtime_get "consecutive_failures")
runtime_get() {
    local key="$1"

    case "$key" in
        consecutive_failures)
            echo "$_RUNTIME_consecutive_failures"
            ;;
        last_prompt_hash)
            echo "$_RUNTIME_last_prompt_hash"
            ;;
        test_start_time)
            echo "$_RUNTIME_test_start_time"
            ;;
        version_start_time)
            echo "$_RUNTIME_version_start_time"
            ;;
        last_writer_section)
            echo "$_RUNTIME_last_writer_section"
            ;;
        *)
            echo ""
            ;;
    esac
}

# 런타임 상태 증가
# 사용법: runtime_increment "consecutive_failures"
runtime_increment() {
    local key="$1"

    case "$key" in
        consecutive_failures)
            ((_RUNTIME_consecutive_failures++))
            ;;
    esac
}

# 런타임 상태 리셋
# 사용법: runtime_reset
runtime_reset() {
    _RUNTIME_consecutive_failures=0
    _RUNTIME_last_prompt_hash=""
    _RUNTIME_test_start_time=""
    _RUNTIME_version_start_time=""
    _RUNTIME_last_writer_section=""
}

# ══════════════════════════════════════════════════════════════
# 이전 평가 피드백 로드
# ══════════════════════════════════════════════════════════════

# 이전 버전의 평가 피드백 로드
# 사용법: feedback=$(load_previous_feedback "$runs_dir" "$section" 2)
load_previous_feedback() {
    local runs_dir="$1"
    local section="$2"
    local version="$3"

    local prev_version=$((version - 1))
    local prev_eval_file="${runs_dir}/${section}_v${prev_version}.eval.json"

    if [[ ! -f "$prev_eval_file" ]]; then
        echo ""
        return 1
    fi

    python3 -c "
import json
try:
    with open('$prev_eval_file', 'r') as f:
        data = json.load(f)

    score = data.get('total_score', 0)
    tags = data.get('defect_tags', [])
    weaknesses = data.get('weaknesses', [])
    priority_fix = data.get('priority_fix', '')

    feedback = f'이전 점수: {score}점\n'
    if tags:
        feedback += f'결함 태그: {\", \".join(tags)}\n'
    if weaknesses:
        feedback += '주요 약점:\n'
        for w in weaknesses[:3]:
            issue = w.get('issue', '')[:150]
            fix = w.get('fix', '')[:150]
            feedback += f'- 문제: {issue}\n  해결: {fix}\n'
    if priority_fix:
        feedback += f'최우선 개선: {priority_fix[:200]}'

    print(feedback)
except Exception as e:
    pass
" 2>/dev/null
}

# 평가 JSON에서 피드백 추출
# 사용법: feedback=$(extract_feedback_from_json "$json")
extract_feedback_from_json() {
    local json="$1"

    echo "$json" | python3 -c "
import json
import sys

try:
    data = json.load(sys.stdin)

    score = data.get('total_score', 0)
    tags = data.get('defect_tags', [])
    weaknesses = data.get('weaknesses', [])
    priority_fix = data.get('priority_fix', '')

    feedback = f'이전 점수: {score}점\n'
    if tags:
        feedback += f'결함 태그: {\", \".join(tags)}\n'
    if weaknesses:
        feedback += '주요 약점:\n'
        for w in weaknesses[:3]:
            issue = w.get('issue', '')[:150]
            fix = w.get('fix', '')[:150]
            feedback += f'- 문제: {issue}\n  해결: {fix}\n'
    if priority_fix:
        feedback += f'최우선 개선: {priority_fix[:200]}'

    print(feedback)
except:
    pass
" 2>/dev/null
}
