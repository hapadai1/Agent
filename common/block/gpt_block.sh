#!/bin/bash
# gpt_block.sh - GPT 블록 실행기 (Thin Adapter)
# Flow에서 GPT 작업을 실행하는 통일된 인터페이스
#
# 설계 원칙 (de_claude블록.md):
#   - 모델 호출은 chatgpt_call만 담당 (block은 call만 호출)
#   - block은 인자 파싱/입력 조합/call 호출만 담당
#   - 재시도는 call 레이어에서만 (block retry=0)
#
# 사용법:
#   ./gpt_block.sh --action=writer --input=prompt.md --output=content.md
#   ./gpt_block.sh --action=evaluator --input=content.md --output=eval.json
#
# 블록 인터페이스 (GPT/Claude 공통):
#   --action    : 액션 이름
#   --input     : 입력 파일 (여러 개 가능)
#   --output    : 출력 파일
#   --config    : 설정 파일 (선택)
#   --envelope  : Envelope 모드 (표준 JSON 출력, 환경변수 BLOCK_ENVELOPE=true로도 가능)

# set -euo pipefail  # source 시 문제 방지

_GPT_BLOCK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_GPT_BLOCK_COMMON_DIR="$(dirname "$_GPT_BLOCK_DIR")"

# chatgpt.sh 로드 (이미 로드되지 않은 경우)
if ! declare -f chatgpt_call &>/dev/null; then
    source "$_GPT_BLOCK_COMMON_DIR/chatgpt.sh"
fi

# envelope.sh 로드 (Envelope 모드용)
if [[ -f "$_GPT_BLOCK_DIR/envelope.sh" ]]; then
    source "$_GPT_BLOCK_DIR/envelope.sh"
fi

# ══════════════════════════════════════════════════════════════
# 설정
# ══════════════════════════════════════════════════════════════
: "${GPT_BLOCK_TAB:=1}"
: "${GPT_BLOCK_WIN:=1}"
: "${GPT_BLOCK_TIMEOUT:=1500}"
: "${GPT_BLOCK_MIN_LEN:=100}"

# [정책] GPT_BLOCK_RETRY는 무효 - 재시도는 call 레이어에서만
# 기존 설정은 하위 호환성을 위해 유지하되 무시됨
: "${GPT_BLOCK_RETRY:=0}"
_GPT_BLOCK_RETRY_WARNED=false

# Envelope 모드 (환경변수로 활성화 가능)
: "${BLOCK_ENVELOPE:=false}"

# ══════════════════════════════════════════════════════════════
# 메인 함수
# ══════════════════════════════════════════════════════════════

gpt_block() {
    local action=""
    local inputs=()
    local output=""
    local config=""
    local tab="$GPT_BLOCK_TAB"
    local timeout="$GPT_BLOCK_TIMEOUT"
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
            --tab=*)
                tab="${1#--tab=}"
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

    # 액션별 탭 매핑 (기본값)
    case "$action" in
        prompt|prompt_gen)
            : "${tab:=6}"
            ;;
        writer|content_write)
            : "${tab:=7}"
            ;;
        evaluator|evaluate)
            : "${tab:=8}"
            ;;
    esac

    # [정책] GPT_BLOCK_RETRY 경고 (1회만)
    if [[ "${GPT_BLOCK_RETRY:-0}" -gt 0 && "$_GPT_BLOCK_RETRY_WARNED" == false ]]; then
        echo "⚠️ GPT_BLOCK_RETRY는 정책상 무효화됨 (재시도는 call 레이어 CHATGPT_MAX_RETRIES로 제어)" >&2
        _GPT_BLOCK_RETRY_WARNED=true
    fi

    # 입력 검증
    if [[ ${#inputs[@]} -eq 0 ]]; then
        echo "ERROR: 입력 파일이 필요합니다 (--input=FILE)" >&2
        return 1
    fi

    # 입력 파일 합치기
    local combined_input=""
    for input_file in "${inputs[@]}"; do
        if [[ -f "$input_file" ]]; then
            combined_input+="$(cat "$input_file")"$'\n\n'
        else
            echo "ERROR: 입력 파일 없음: $input_file" >&2
            return 1
        fi
    done

    echo "━━━ [GPT 블록] 액션: $action, 탭: $tab ━━━" >&2

    # ChatGPT 호출 (재시도는 call 레이어에서 처리)
    local result
    local start_time
    start_time=$(date +%s%3N 2>/dev/null || date +%s)

    result=$(chatgpt_call \
        --tab="$tab" \
        --timeout="$timeout" \
        "$combined_input"
    )

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

    # 결과 검증 및 센티넬 변환
    local final_result="$result"
    local final_exit_code=$exit_code

    if [[ $exit_code -ne 0 ]]; then
        echo "ERROR: GPT 호출 실패" >&2
        final_result="__FAILED__"
        final_exit_code=1
    elif [[ -z "$result" || ${#result} -lt $GPT_BLOCK_MIN_LEN ]]; then
        echo "ERROR: 응답이 너무 짧음 (${#result}자)" >&2
        final_result="__EMPTY__"
        final_exit_code=1
    else
        echo "✅ GPT 블록 완료 (${#result}자, $((duration_ms/1000))초)" >&2
    fi

    # 최종 출력 결정
    local final_output="$final_result"

    # Envelope 모드
    if [[ "$use_envelope" == "true" ]] && declare -f _wrap_envelope &>/dev/null; then
        final_output=$(_wrap_envelope "gpt" "${action:-custom}" "gpt-4o" "$final_result" "$final_exit_code" "$duration_ms" 0)
        # envelope 래핑 후 exit_code는 envelope 내부 ok 필드로 전달되므로 0으로 정규화
        final_exit_code=0
    fi

    # 출력
    if [[ -n "$output" ]]; then
        echo "$final_output" > "$output"
    else
        echo "$final_output"
    fi

    return $final_exit_code
}

# ══════════════════════════════════════════════════════════════
# CLI 실행
# ══════════════════════════════════════════════════════════════

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    gpt_block "$@"
fi
