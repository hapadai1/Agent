#!/bin/bash
# error_mapper.sh - 에러 코드 매핑 함수
#
# 설계 원칙 (de_claude블록.md):
#   - 표준 코드: TIMEOUT, EMPTY_OUTPUT, TRANSIENT, FATAL, UNKNOWN
#   - UNKNOWN 과다 방지: TRANSIENT/FATAL 최소 분류
#   - 기존 센티넬 → 표준 코드 매핑
#
# 매핑 규칙:
#   __TIMEOUT__                  → TIMEOUT
#   __COMPLETED_BUT_EMPTY__      → EMPTY_OUTPUT
#   __EMPTY__                    → EMPTY_OUTPUT
#   __STUCK__                    → TRANSIENT
#   __STOPPED__                  → TRANSIENT (사용자 개입/차단 시 FATAL)
#   __ERROR__:*                  → FATAL (auth/cli_not_found/bad_input) 또는 UNKNOWN
#   __FAILED__                   → UNKNOWN (입력파일/권한 문제 시 FATAL)

# ══════════════════════════════════════════════════════════════
# 표준 에러 코드 상수
# ══════════════════════════════════════════════════════════════

# 중복 로드 방지
if [[ -z "${_ERROR_MAPPER_LOADED:-}" ]]; then
    readonly ERROR_TIMEOUT="TIMEOUT"
    readonly ERROR_EMPTY="EMPTY_OUTPUT"
    readonly ERROR_TRANSIENT="TRANSIENT"
    readonly ERROR_FATAL="FATAL"
    readonly ERROR_UNKNOWN="UNKNOWN"
    _ERROR_MAPPER_LOADED=true
fi

# ══════════════════════════════════════════════════════════════
# 에러 코드 매핑 함수
# ══════════════════════════════════════════════════════════════

# 센티넬 → 표준 코드 매핑
# 사용법: code=$(_map_error_code "$legacy_code" "$provider")
_map_error_code() {
    local legacy="$1"
    local provider="${2:-}"  # claude 또는 gpt (선택)

    case "$legacy" in
        __TIMEOUT__)
            echo "$ERROR_TIMEOUT"
            ;;

        __COMPLETED_BUT_EMPTY__|__EMPTY__)
            echo "$ERROR_EMPTY"
            ;;

        __STUCK__)
            # 브라우저 통신 이상 - 일시적 오류
            echo "$ERROR_TRANSIENT"
            ;;

        __STOPPED__)
            # 기본은 TRANSIENT, 사용자 개입/차단 감지 시 FATAL
            # (향후 reason 파싱으로 분류 정교화 가능)
            echo "$ERROR_TRANSIENT"
            ;;

        __ERROR__:*)
            # reason 파싱
            local reason="${legacy#__ERROR__:}"
            reason_lower=$(echo "$reason" | tr '[:upper:]' '[:lower:]')

            # FATAL 판정 패턴
            if [[ "$reason_lower" == *"auth"* ]] || \
               [[ "$reason_lower" == *"authentication"* ]] || \
               [[ "$reason_lower" == *"api key"* ]] || \
               [[ "$reason_lower" == *"apikey"* ]] || \
               [[ "$reason_lower" == *"not found"* ]] || \
               [[ "$reason_lower" == *"notfound"* ]] || \
               [[ "$reason_lower" == *"permission"* ]] || \
               [[ "$reason_lower" == *"denied"* ]] || \
               [[ "$reason_lower" == *"forbidden"* ]] || \
               [[ "$reason_lower" == *"invalid"* ]] || \
               [[ "$reason_lower" == *"cli"* ]] || \
               [[ "$reason_lower" == *"binary"* ]] || \
               [[ "$reason_lower" == *"command"* ]]; then
                echo "$ERROR_FATAL"
            # TRANSIENT 판정 패턴
            elif [[ "$reason_lower" == *"rate limit"* ]] || \
                 [[ "$reason_lower" == *"ratelimit"* ]] || \
                 [[ "$reason_lower" == *"too many"* ]] || \
                 [[ "$reason_lower" == *"overload"* ]] || \
                 [[ "$reason_lower" == *"temporary"* ]] || \
                 [[ "$reason_lower" == *"retry"* ]] || \
                 [[ "$reason_lower" == *"network"* ]] || \
                 [[ "$reason_lower" == *"connection"* ]] || \
                 [[ "$reason_lower" == *"timeout"* ]]; then
                echo "$ERROR_TRANSIENT"
            else
                echo "$ERROR_UNKNOWN"
            fi
            ;;

        __FAILED__)
            # 기본은 UNKNOWN, 특정 패턴 감지 시 FATAL
            # (현재는 기본값, 향후 stderr 분석으로 정교화)
            echo "$ERROR_UNKNOWN"
            ;;

        *)
            # 알 수 없는 센티넬
            echo "$ERROR_UNKNOWN"
            ;;
    esac
}

# 센티넬에서 사람용 메시지 추출
# 사용법: message=$(_get_error_message "$legacy_code")
_get_error_message() {
    local legacy="$1"

    case "$legacy" in
        __TIMEOUT__)
            echo "Request timed out"
            ;;
        __COMPLETED_BUT_EMPTY__)
            echo "Response completed but content was empty"
            ;;
        __EMPTY__)
            echo "Empty response received"
            ;;
        __STUCK__)
            echo "Browser communication stuck or unresponsive"
            ;;
        __STOPPED__)
            echo "Response was stopped or interrupted"
            ;;
        __ERROR__:*)
            local reason="${legacy#__ERROR__:}"
            echo "Error: $reason"
            ;;
        __FAILED__)
            echo "Operation failed"
            ;;
        *)
            echo "Unknown error: $legacy"
            ;;
    esac
}

# 에러 코드가 재시도 가치가 있는지 확인
# 사용법: if _is_retriable "$code"; then ...
_is_retriable() {
    local code="$1"

    case "$code" in
        "$ERROR_TIMEOUT"|"$ERROR_TRANSIENT")
            return 0  # 재시도 가치 있음
            ;;
        "$ERROR_EMPTY")
            return 0  # 재시도 가치 있음 (일시적일 수 있음)
            ;;
        "$ERROR_FATAL"|"$ERROR_UNKNOWN")
            return 1  # 재시도 무의미
            ;;
        *)
            return 1
            ;;
    esac
}

# 에러 코드가 즉시 중단해야 하는지 확인
# 사용법: if _is_fatal "$code"; then ...
_is_fatal() {
    local code="$1"
    [[ "$code" == "$ERROR_FATAL" ]]
}

# ══════════════════════════════════════════════════════════════
# 스크립트 직접 실행 시 도움말/테스트
# ══════════════════════════════════════════════════════════════

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "에러 코드 매핑 함수 스크립트"
    echo ""
    echo "사용법: source error_mapper.sh 로 로드 후 함수 사용"
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "표준 에러 코드"
    echo "═══════════════════════════════════════════════════"
    echo "  TIMEOUT      - 요청 시간 초과"
    echo "  EMPTY_OUTPUT - 빈 응답"
    echo "  TRANSIENT    - 일시적 오류 (재시도 가치 있음)"
    echo "  FATAL        - 치명적 오류 (즉시 중단)"
    echo "  UNKNOWN      - 알 수 없는 오류"
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "매핑 테스트"
    echo "═══════════════════════════════════════════════════"
    echo ""

    test_cases=(
        "__TIMEOUT__"
        "__COMPLETED_BUT_EMPTY__"
        "__EMPTY__"
        "__STUCK__"
        "__STOPPED__"
        "__ERROR__:authentication failed"
        "__ERROR__:rate limit exceeded"
        "__ERROR__:unknown issue"
        "__FAILED__"
    )

    printf "%-35s → %-12s | %s\n" "Legacy Code" "Standard" "Message"
    printf "%-35s   %-12s   %s\n" "-----------------------------------" "------------" "-----------------------------------"

    for tc in "${test_cases[@]}"; do
        code=$(_map_error_code "$tc")
        msg=$(_get_error_message "$tc")
        printf "%-35s → %-12s | %s\n" "$tc" "$code" "$msg"
    done
fi
