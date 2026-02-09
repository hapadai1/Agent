#!/bin/bash
# errors.sh - 에러 핸들링 공통 모듈
# 사용법: source lib/util/errors.sh
#
# 설계 원칙 (de_claude블록.md):
#   - Legacy 모드: 기존 센티넬 코드 (__FAILED__, __TIMEOUT__ 등)
#   - Envelope 모드: JSON { ok: bool, error: { code, legacy_code, message } }
#   - 통합 함수로 두 모드 모두 지원

# ══════════════════════════════════════════════════════════════
# Envelope 모드 감지 및 파싱
# ══════════════════════════════════════════════════════════════

# 응답이 Envelope 형식인지 확인
# 사용법: if is_envelope "$response"; then ...
is_envelope() {
    local response="$1"

    # JSON이고 최상위에 ok 필드가 있으면 Envelope
    python3 -c "
import json, sys
try:
    obj = json.loads(sys.argv[1])
    if 'ok' in obj and isinstance(obj['ok'], bool):
        sys.exit(0)
    sys.exit(1)
except:
    sys.exit(1)
" "$response" 2>/dev/null
}

# Envelope에서 ok 값 추출
# 사용법: ok=$(get_envelope_ok "$response")  # "true" 또는 "false"
get_envelope_ok() {
    local response="$1"
    python3 -c "
import json, sys
try:
    obj = json.loads(sys.argv[1])
    print('true' if obj.get('ok', False) else 'false')
except:
    print('false')
" "$response" 2>/dev/null
}

# Envelope에서 error.code 추출
# 사용법: code=$(get_envelope_error_code "$response")
get_envelope_error_code() {
    local response="$1"
    python3 -c "
import json, sys
try:
    obj = json.loads(sys.argv[1])
    print(obj.get('error', {}).get('code', ''))
except:
    print('')
" "$response" 2>/dev/null
}

# Envelope에서 error.legacy_code 추출
# 사용법: legacy=$(get_envelope_legacy_code "$response")
get_envelope_legacy_code() {
    local response="$1"
    python3 -c "
import json, sys
try:
    obj = json.loads(sys.argv[1])
    print(obj.get('error', {}).get('legacy_code', ''))
except:
    print('')
" "$response" 2>/dev/null
}

# Envelope에서 result 추출
# 사용법: result=$(get_envelope_result "$response")
get_envelope_result() {
    local response="$1"
    python3 -c "
import json, sys
try:
    obj = json.loads(sys.argv[1])
    result = obj.get('result', '')
    if isinstance(result, dict):
        print(json.dumps(result, ensure_ascii=False))
    else:
        print(result)
except:
    print('')
" "$response" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 통합 에러 감지 (Legacy + Envelope)
# ══════════════════════════════════════════════════════════════

# 응답이 에러인지 확인 (Legacy/Envelope 모두 지원)
# 사용법: if is_response_error "$response"; then handle_error; fi
is_response_error() {
    local response="$1"

    # Envelope 모드 체크
    if is_envelope "$response"; then
        local ok
        ok=$(get_envelope_ok "$response")
        [[ "$ok" == "false" ]]
        return $?
    fi

    # Legacy 모드 (기존 로직)
    is_chatgpt_error "$response"
}

# 에러 코드 추출 (Legacy/Envelope 모두 지원)
# 사용법: code=$(get_response_error_code "$response")
# 반환: TIMEOUT, EMPTY_OUTPUT, TRANSIENT, FATAL, UNKNOWN (표준 코드)
get_response_error_code() {
    local response="$1"

    # Envelope 모드
    if is_envelope "$response"; then
        get_envelope_error_code "$response"
        return
    fi

    # Legacy 모드 - 센티넬을 표준 코드로 변환
    case "$response" in
        "__TIMEOUT__")
            echo "TIMEOUT"
            ;;
        "__COMPLETED_BUT_EMPTY__"|"__EMPTY__")
            echo "EMPTY_OUTPUT"
            ;;
        "__STUCK__")
            echo "TRANSIENT"
            ;;
        "__STOPPED__")
            echo "TRANSIENT"
            ;;
        "__FAILED__")
            echo "UNKNOWN"
            ;;
        __ERROR__:*)
            echo "UNKNOWN"
            ;;
        "")
            echo "EMPTY_OUTPUT"
            ;;
        *)
            echo ""
            ;;
    esac
}

# 에러가 재시도 가치 있는지 확인
# 사용법: if is_retriable_error "$response"; then retry; fi
is_retriable_error() {
    local response="$1"
    local code
    code=$(get_response_error_code "$response")

    case "$code" in
        "TIMEOUT"|"TRANSIENT"|"EMPTY_OUTPUT")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 에러가 즉시 중단해야 하는지 확인
# 사용법: if is_fatal_error "$response"; then abort; fi
is_fatal_error() {
    local response="$1"
    local code
    code=$(get_response_error_code "$response")

    [[ "$code" == "FATAL" ]]
}

# ══════════════════════════════════════════════════════════════
# ChatGPT 에러 감지 (Legacy - 하위 호환성)
# ══════════════════════════════════════════════════════════════

# ChatGPT 응답이 에러인지 확인 (Legacy)
# 사용법: if is_chatgpt_error "$response"; then handle_error; fi
is_chatgpt_error() {
    local response="$1"

    # v2 에러 코드 체크
    case "$response" in
        "__STOPPED__"|"__FAILED__"|"__STUCK__"|"__COMPLETED_BUT_EMPTY__"|"__TIMEOUT__"|"__EMPTY__")
            return 0
            ;;
        __ERROR__:*)
            return 0
            ;;
        "")
            return 0
            ;;
    esac

    return 1
}

# 에러 코드에서 에러 타입 추출
# 사용법: error_type=$(get_error_type "$response")
get_error_type() {
    local response="$1"

    case "$response" in
        "__STOPPED__")
            echo "stopped"
            ;;
        "__FAILED__")
            echo "failed"
            ;;
        "__STUCK__")
            echo "stuck"
            ;;
        "__COMPLETED_BUT_EMPTY__")
            echo "empty"
            ;;
        __ERROR__:*)
            echo "error:${response#__ERROR__:}"
            ;;
        "")
            echo "empty_response"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# 에러 메시지 생성 (Legacy/Envelope 모두 지원)
# 사용법: msg=$(get_error_message "$response")
get_error_message() {
    local response="$1"

    # Envelope 모드
    if is_envelope "$response"; then
        python3 -c "
import json, sys
try:
    obj = json.loads(sys.argv[1])
    msg = obj.get('error', {}).get('message', '')
    if msg:
        print(msg)
    else:
        print('Envelope 에러 (메시지 없음)')
except:
    print('Envelope 파싱 오류')
" "$response" 2>/dev/null
        return
    fi

    # Legacy 모드
    case "$response" in
        "__TIMEOUT__")
            echo "요청 시간 초과"
            ;;
        "__STOPPED__")
            echo "ChatGPT가 중단되었습니다 (사용자 취소 또는 타임아웃)"
            ;;
        "__FAILED__")
            echo "ChatGPT 호출이 실패했습니다"
            ;;
        "__STUCK__")
            echo "ChatGPT가 응답하지 않습니다 (멈춤)"
            ;;
        "__COMPLETED_BUT_EMPTY__"|"__EMPTY__")
            echo "ChatGPT가 완료되었으나 응답이 비어있습니다"
            ;;
        __ERROR__:streaming_stalled)
            echo "스트리밍이 중지됨 - 재시도 필요"
            ;;
        __ERROR__:*)
            echo "ChatGPT 오류: ${response#__ERROR__:}"
            ;;
        "")
            echo "빈 응답을 받았습니다"
            ;;
        *)
            echo "알 수 없는 오류"
            ;;
    esac
}

# ══════════════════════════════════════════════════════════════
# 응답 품질 검사
# ══════════════════════════════════════════════════════════════

# 응답에서 실제 결과 추출 (Legacy/Envelope 모두 지원)
# 사용법: result=$(get_response_result "$response")
get_response_result() {
    local response="$1"

    # Envelope 모드
    if is_envelope "$response"; then
        get_envelope_result "$response"
        return
    fi

    # Legacy 모드 - 응답 그대로 반환 (에러가 아니면)
    if is_chatgpt_error "$response"; then
        echo ""
    else
        echo "$response"
    fi
}

# 응답 길이 검사 (Legacy/Envelope 모두 지원)
# 사용법: if check_response_length "$response" 500; then ... fi
check_response_length() {
    local response="$1"
    local min_length="${2:-100}"

    # Envelope 모드면 result 기준으로 체크
    local actual_content
    actual_content=$(get_response_result "$response")

    [[ ${#actual_content} -ge $min_length ]]
}

# Writer 응답 품질 검사 (500자 이상) - Legacy/Envelope 모두 지원
# 사용법: if is_valid_writer_response "$response"; then ... fi
is_valid_writer_response() {
    local response="$1"
    local min_length="${2:-500}"

    # 통합 에러 체크 (Legacy + Envelope)
    if is_response_error "$response"; then
        return 1
    fi

    # 길이 체크 (실제 결과 기준)
    check_response_length "$response" "$min_length"
}

# Evaluator 응답 품질 검사 (JSON 포함, 50자 이상) - Legacy/Envelope 모두 지원
# 사용법: if is_valid_evaluator_response "$response"; then ... fi
is_valid_evaluator_response() {
    local response="$1"

    # 통합 에러 체크
    if is_response_error "$response"; then
        return 1
    fi

    # 실제 결과 추출
    local actual_result
    actual_result=$(get_response_result "$response")

    # 길이 체크 (최소 50자)
    if [[ ${#actual_result} -lt 50 ]]; then
        return 1
    fi

    # JSON 포함 여부 (간단한 체크)
    if [[ "$actual_result" != *"{"* ]] || [[ "$actual_result" != *"}"* ]]; then
        return 1
    fi

    return 0
}

# ══════════════════════════════════════════════════════════════
# 에러 컨텍스트 출력
# ══════════════════════════════════════════════════════════════

# 에러 컨텍스트 출력 (step_runner용)
# 사용법: print_error_context "writer" "$prompt_file" "$out_file"
print_error_context() {
    local step="$1"
    local input_file="$2"
    local output_file="$3"

    echo "────────────────────────────────────" >&2
    echo "❌ ${step^} 실행 오류" >&2
    echo "────────────────────────────────────" >&2

    if [[ -n "$input_file" ]]; then
        if [[ -f "$input_file" ]]; then
            echo "  입력: $input_file ($(wc -c < "$input_file" | tr -d ' ')자)" >&2
        else
            echo "  입력: $input_file (파일 없음)" >&2
        fi
    fi

    if [[ -n "$output_file" ]]; then
        if [[ -f "$output_file" ]]; then
            echo "  출력: $output_file ($(wc -c < "$output_file" | tr -d ' ')자)" >&2
        else
            echo "  출력: $output_file (생성되지 않음)" >&2
        fi
    fi

    echo "────────────────────────────────────" >&2
}

# Prerequisites 오류 출력
# 사용법: print_prerequisites_error "writer" "$prompt_file" "먼저 --step=prompt를 실행하세요"
print_prerequisites_error() {
    local step="$1"
    local missing_file="$2"
    local action="$3"

    echo "────────────────────────────────────" >&2
    echo "❌ ${step^} 실행 전제조건 오류" >&2
    echo "────────────────────────────────────" >&2
    echo "  필요 파일: $missing_file" >&2
    echo "  조치: $action" >&2
    echo "────────────────────────────────────" >&2
}

# ══════════════════════════════════════════════════════════════
# 연속 실패 관리
# ══════════════════════════════════════════════════════════════

# 전역 변수 (source 시 초기화)
_CONSECUTIVE_FAILURES=${_CONSECUTIVE_FAILURES:-0}
_MAX_CONSECUTIVE_FAILURES=${_MAX_CONSECUTIVE_FAILURES:-3}

# 연속 실패 카운터 증가
# 사용법: increment_failure_count
increment_failure_count() {
    ((_CONSECUTIVE_FAILURES++))
}

# 연속 실패 카운터 리셋
# 사용법: reset_failure_count
reset_failure_count() {
    _CONSECUTIVE_FAILURES=0
}

# 연속 실패 한계 도달 확인
# 사용법: if has_reached_failure_limit; then abort; fi
has_reached_failure_limit() {
    [[ $_CONSECUTIVE_FAILURES -ge $_MAX_CONSECUTIVE_FAILURES ]]
}

# 현재 연속 실패 횟수 반환
# 사용법: count=$(get_failure_count)
get_failure_count() {
    echo "$_CONSECUTIVE_FAILURES"
}

# 최대 연속 실패 횟수 설정
# 사용법: set_max_failures 5
set_max_failures() {
    _MAX_CONSECUTIVE_FAILURES="${1:-3}"
}

# ══════════════════════════════════════════════════════════════
# 안전한 ChatGPT 호출 래퍼
# ══════════════════════════════════════════════════════════════

# ChatGPT 호출 + 에러 처리 래퍼 (Legacy/Envelope 모두 지원)
# 사용법: response=$(safe_chatgpt_call "$tab" "$timeout" "$prompt")
#        if [[ $? -ne 0 ]]; then handle_error; fi
safe_chatgpt_call() {
    local tab="$1"
    local timeout="$2"
    local prompt="$3"

    # chatgpt_call 함수 존재 확인
    if ! type chatgpt_call &>/dev/null; then
        echo "__ERROR__:chatgpt_call_not_found"
        return 1
    fi

    local response
    response=$(chatgpt_call --tab="$tab" --timeout="$timeout" --retry "$prompt")

    # 통합 에러 체크 (Legacy + Envelope)
    if is_response_error "$response"; then
        echo "$response"
        return 1
    fi

    echo "$response"
    return 0
}

# 재시도 포함 ChatGPT 호출 (에러 타입에 따른 재시도 결정)
# 사용법: response=$(retry_chatgpt_call "$tab" "$timeout" "$prompt" 3)
retry_chatgpt_call() {
    local tab="$1"
    local timeout="$2"
    local prompt="$3"
    local max_retries="${4:-2}"

    local retry_count=0
    local response=""

    while [[ $retry_count -lt $max_retries ]]; do
        ((retry_count++))

        response=$(safe_chatgpt_call "$tab" "$timeout" "$prompt")
        local exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            echo "$response"
            return 0
        fi

        # FATAL 에러면 즉시 중단 (재시도 무의미)
        if is_fatal_error "$response"; then
            echo "⚠️ FATAL 에러 - 재시도 중단: $(get_error_message "$response")" >&2
            echo "$response"
            return 1
        fi

        # 재시도 가치가 없으면 중단
        if ! is_retriable_error "$response"; then
            echo "⚠️ 재시도 불가 에러: $(get_response_error_code "$response")" >&2
            echo "$response"
            return 1
        fi

        # 재시도 전 새 채팅 시작
        if [[ $retry_count -lt $max_retries ]]; then
            echo "🔄 재시도 ($retry_count/$max_retries): $(get_error_message "$response")" >&2
            chatgpt_call --mode=new_chat --tab="$tab" >/dev/null 2>&1
            sleep 2
        fi
    done

    # 모든 재시도 실패
    echo "$response"
    return 1
}
