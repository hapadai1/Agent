#!/bin/bash
# claude_block.sh - Claude 블록 실행기 (Thin Adapter)
# Flow에서 Claude 판정 작업을 실행하는 통일된 인터페이스
#
# 설계 원칙 (de_claude블록.md):
#   - 모델 호출은 claude_call만 담당 (CLI 직접 호출 금지)
#   - block은 인자 파싱/입력 조합/call 호출만 담당
#   - 재시도는 call 레이어에서만 (block retry=0)
#
# 사용법:
#   ./claude_block.sh --action=review --input=content.md --output=decision.json
#   ./claude_block.sh --action=judge --input=content.md --input=eval.json
#
# 블록 인터페이스 (GPT/Claude 공통):
#   --action    : 액션 이름 (review, judge, custom)
#   --input     : 입력 파일 (여러 개 가능)
#   --output    : 출력 파일
#   --config    : 설정 파일 (선택)
#   --template  : 프롬프트 템플릿 파일 (선택)
#   --model     : 모델 (sonnet, opus, haiku)
#   --timeout   : 타임아웃 (초)
#   --envelope  : Envelope 모드 (표준 JSON 출력, 환경변수 BLOCK_ENVELOPE=true로도 가능)
#
# 환경변수:
#   PROJECT_DIR   : 프로젝트 디렉토리 (프롬프트 탐색: $PROJECT_DIR/prompts/claude/{action}.md)
#   BLOCK_ENVELOPE: Envelope 모드 활성화 (true/false)
#
# 프롬프트 탐색 순서:
#   1. --template 명시
#   2. $PROJECT_DIR/prompts/claude/{action}.md
#   3. common/prompts/claude/{action}.md
#   4. claude_call 내장 기본값

_CLAUDE_BLOCK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CLAUDE_BLOCK_COMMON_DIR="$(dirname "$_CLAUDE_BLOCK_DIR")"

# claude.sh 로드 (이미 로드되지 않은 경우)
if ! declare -f claude_call &>/dev/null; then
    source "$_CLAUDE_BLOCK_COMMON_DIR/claude.sh"
fi

# envelope.sh 로드 (Envelope 모드용)
if [[ -f "$_CLAUDE_BLOCK_DIR/envelope.sh" ]]; then
    source "$_CLAUDE_BLOCK_DIR/envelope.sh"
fi

# ══════════════════════════════════════════════════════════════
# 설정
# ══════════════════════════════════════════════════════════════
: "${CLAUDE_BLOCK_MODEL:=opus}"
: "${CLAUDE_BLOCK_TIMEOUT:=300}"

# [정책] CLAUDE_BLOCK_RETRY는 무효 - 재시도는 call 레이어에서만
: "${CLAUDE_BLOCK_RETRY:=0}"
_CLAUDE_BLOCK_RETRY_WARNED=false

# Envelope 모드 (환경변수로 활성화 가능)
: "${BLOCK_ENVELOPE:=false}"

# 프로젝트 디렉토리 (프롬프트 탐색용)
: "${PROJECT_DIR:=}"

# ══════════════════════════════════════════════════════════════
# 메인 함수 (Thin Adapter)
# ══════════════════════════════════════════════════════════════

claude_block() {
    local action=""
    local inputs=()
    local output=""
    local config=""
    local template=""
    local model="$CLAUDE_BLOCK_MODEL"
    local timeout="$CLAUDE_BLOCK_TIMEOUT"
    local use_envelope="$BLOCK_ENVELOPE"

    # 옵션 파싱
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --action=*)
                action="${1#--action=}"
                shift
                ;;
            --input=*)
                inputs+=("${1#--input=}")
                shift
                ;;
            --output=*)
                output="${1#--output=}"
                shift
                ;;
            --config=*)
                config="${1#--config=}"
                shift
                ;;
            --template=*)
                template="${1#--template=}"
                shift
                ;;
            --model=*)
                model="${1#--model=}"
                shift
                ;;
            --timeout=*)
                timeout="${1#--timeout=}"
                shift
                ;;
            --envelope)
                use_envelope=true
                shift
                ;;
            *)
                echo "ERROR: 알 수 없는 옵션: $1" >&2
                return 1
                ;;
        esac
    done

    # 설정 파일 로드
    if [[ -n "$config" && -f "$config" ]]; then
        source "$config"
    fi

    # [정책] CLAUDE_BLOCK_RETRY 경고 (1회만)
    if [[ "${CLAUDE_BLOCK_RETRY:-0}" -gt 0 && "$_CLAUDE_BLOCK_RETRY_WARNED" == false ]]; then
        echo "⚠️ CLAUDE_BLOCK_RETRY는 정책상 무효화됨 (재시도는 call 레이어 CLAUDE_RETRY_COUNT로 제어)" >&2
        _CLAUDE_BLOCK_RETRY_WARNED=true
    fi

    # 입력 검증
    if [[ ${#inputs[@]} -eq 0 ]]; then
        echo "ERROR: 입력 파일이 필요합니다 (--input=FILE)" >&2
        return 1
    fi

    # 입력 파일 존재 확인
    for input_file in "${inputs[@]}"; do
        if [[ ! -f "$input_file" ]]; then
            echo "ERROR: 입력 파일 없음: $input_file" >&2
            return 1
        fi
    done

    echo "━━━ [Claude 블록] 액션: ${action:-custom}, 모델: $model ━━━" >&2

    # claude_call 옵션 구성
    local call_opts=()
    call_opts+=(--model="$model")
    call_opts+=(--timeout="$timeout")

    # 프롬프트 탐색 순서:
    # 1. --template 명시
    # 2. PROJECT_DIR/prompts/claude/{action}.md
    # 3. common/prompts/claude/{action}.md
    # 4. claude_call 내장 기본값
    local resolved_template=""
    local prompt_source="builtin"

    if [[ -n "$template" && -f "$template" ]]; then
        # 1. 명시적 템플릿
        resolved_template="$template"
        prompt_source="explicit"
    elif [[ -n "$action" ]]; then
        # 2. 프로젝트 프롬프트 탐색
        if [[ -n "$PROJECT_DIR" && -f "${PROJECT_DIR}/prompts/claude/${action}.md" ]]; then
            resolved_template="${PROJECT_DIR}/prompts/claude/${action}.md"
            prompt_source="project"
        # 3. 공통 프롬프트 탐색
        elif [[ -f "${_CLAUDE_BLOCK_COMMON_DIR}/prompts/claude/${action}.md" ]]; then
            resolved_template="${_CLAUDE_BLOCK_COMMON_DIR}/prompts/claude/${action}.md"
            prompt_source="common"
        fi
    fi

    # 로그: 프롬프트 출처
    if [[ -n "$resolved_template" ]]; then
        echo "  프롬프트: ${prompt_source} (${resolved_template})" >&2
        call_opts+=(--template="$resolved_template")
    elif [[ -n "$action" ]]; then
        echo "  프롬프트: builtin (--action=$action)" >&2
        call_opts+=(--action="$action")
    fi

    # 입력 파일들
    for f in "${inputs[@]}"; do
        call_opts+=(--input="$f")
    done

    # 출력 파일 (claude_call에 위임)
    if [[ -n "$output" ]]; then
        call_opts+=(--output="$output")
    fi

    # claude_call 호출 (유일한 모델 실행 지점)
    local result
    local start_time
    start_time=$(date +%s%3N 2>/dev/null || date +%s)

    result=$(claude_call "${call_opts[@]}")
    local exit_code=$?

    local end_time
    end_time=$(date +%s%3N 2>/dev/null || date +%s)

    # duration 계산 (밀리초 지원 시 ms, 아니면 초*1000)
    local duration_ms
    if [[ ${#start_time} -gt 10 ]]; then
        duration_ms=$((end_time - start_time))
    else
        duration_ms=$(( (end_time - start_time) * 1000 ))
    fi

    # 결과 처리
    if [[ $exit_code -eq 0 ]]; then
        echo "✅ Claude 블록 완료 ($((duration_ms/1000))초)" >&2
    else
        echo "⚠️ Claude 블록 실패 (exit=$exit_code, $((duration_ms/1000))초)" >&2
    fi

    # 최종 출력 결정
    local final_output="$result"

    # Envelope 모드
    if [[ "$use_envelope" == "true" ]] && declare -f _wrap_envelope &>/dev/null; then
        final_output=$(_wrap_envelope "claude" "${action:-custom}" "$model" "$result" "$exit_code" "$duration_ms" 0)
        # envelope 래핑 후 exit_code는 envelope 내부 ok 필드로 전달되므로 0으로 정규화
        exit_code=0
    fi

    # 출력
    if [[ -n "$output" ]]; then
        echo "$final_output" > "$output"
    else
        echo "$final_output"
    fi

    return $exit_code
}

# ══════════════════════════════════════════════════════════════
# 결정 결과 처리 유틸리티
# ══════════════════════════════════════════════════════════════

# 결정 JSON 파일에서 decision 추출
# 사용법: decision=$(get_decision decision.json)
get_decision() {
    local file="$1"
    if [[ -f "$file" ]]; then
        python3 -c "
import json
with open('$file') as f:
    print(json.load(f).get('decision', ''))
" 2>/dev/null
    fi
}

# 결정에 따른 다음 액션 반환
# 사용법: next_action=$(route_decision decision.json)
route_decision() {
    local file="$1"
    local decision
    decision=$(get_decision "$file")

    case "$decision" in
        PASS)
            echo "next"
            ;;
        RERUN_PREV)
            echo "rerun"
            ;;
        GOTO)
            local goto_target
            goto_target=$(python3 -c "
import json
with open('$file') as f:
    print(json.load(f).get('goto', ''))
" 2>/dev/null)
            echo "goto:$goto_target"
            ;;
        STOP)
            echo "stop"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# ══════════════════════════════════════════════════════════════
# CLI 실행
# ══════════════════════════════════════════════════════════════

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    claude_block "$@"
fi
