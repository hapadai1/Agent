#!/bin/bash
# test_block.sh - 블록 시스템 테스트
# 사용법: ./test_block.sh
#
# 테스트 대상:
#   1. 정적 검사: claude_block에서 직접 CLI 호출 제거 확인
#   2. error_mapper.sh: 센티넬 → 표준 코드 변환
#   3. envelope.sh: Envelope 생성 및 파싱
#   4. 통합 테스트: 블록 실행 흐름

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLOCK_DIR="$(dirname "$SCRIPT_DIR")"  # 상위 block/ 디렉토리

# 테스트 카운터
TESTS_PASSED=0
TESTS_FAILED=0

# ══════════════════════════════════════════════════════════════
# 테스트 유틸리티
# ══════════════════════════════════════════════════════════════

pass() {
    echo "  ✅ $1"
    ((TESTS_PASSED++))
}

fail() {
    echo "  ❌ $1"
    ((TESTS_FAILED++))
}

section() {
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  $1"
    echo "═══════════════════════════════════════════════════"
}

# ══════════════════════════════════════════════════════════════
# 1. 정적 검사: 직접 CLI 호출 제거 확인
# ══════════════════════════════════════════════════════════════

test_static_checks() {
    section "1. 정적 검사 - 금지 패턴 확인"

    local claude_block="$BLOCK_DIR/claude_block.sh"

    # 1-1. claude --print 직접 호출 없어야 함
    if grep -q 'claude --print' "$claude_block" 2>/dev/null; then
        fail "claude_block.sh에 'claude --print' 직접 호출 존재"
    else
        pass "claude_block.sh에 직접 CLI 호출 없음"
    fi

    # 1-2. 2>/dev/null 패턴으로 stderr 숨김 없어야 함 (claude 호출 시)
    if grep -E 'claude.*2>/dev/null' "$claude_block" 2>/dev/null; then
        fail "claude 호출에서 stderr 숨김 패턴 존재"
    else
        pass "stderr 숨김 패턴 없음"
    fi

    # 1-3. claude_call 호출이 있어야 함
    if grep -q 'claude_call' "$claude_block" 2>/dev/null; then
        pass "claude_call 래퍼 사용 확인"
    else
        fail "claude_call 래퍼 사용하지 않음"
    fi
}

# ══════════════════════════════════════════════════════════════
# 2. error_mapper.sh 테스트
# ══════════════════════════════════════════════════════════════

test_error_mapper() {
    section "2. error_mapper.sh - 에러 코드 매핑"

    source "$BLOCK_DIR/error_mapper.sh"

    # 테스트 케이스: [입력, 기대값]
    local -a test_cases=(
        "__TIMEOUT__|TIMEOUT"
        "__COMPLETED_BUT_EMPTY__|EMPTY_OUTPUT"
        "__EMPTY__|EMPTY_OUTPUT"
        "__STUCK__|TRANSIENT"
        "__STOPPED__|TRANSIENT"
        "__ERROR__:authentication failed|FATAL"
        "__ERROR__:rate limit exceeded|TRANSIENT"
        "__ERROR__:unknown issue|UNKNOWN"
        "__FAILED__|UNKNOWN"
    )

    for tc in "${test_cases[@]}"; do
        local input="${tc%%|*}"
        local expected="${tc##*|}"
        local actual
        actual=$(_map_error_code "$input")

        if [[ "$actual" == "$expected" ]]; then
            pass "$input → $expected"
        else
            fail "$input → 기대: $expected, 실제: $actual"
        fi
    done

    # _is_retriable 테스트
    echo ""
    echo "  --- 재시도 가능 여부 ---"

    if _is_retriable "TIMEOUT"; then
        pass "TIMEOUT → 재시도 가능"
    else
        fail "TIMEOUT → 재시도 가능해야 함"
    fi

    if _is_retriable "TRANSIENT"; then
        pass "TRANSIENT → 재시도 가능"
    else
        fail "TRANSIENT → 재시도 가능해야 함"
    fi

    if ! _is_retriable "FATAL"; then
        pass "FATAL → 재시도 불가"
    else
        fail "FATAL → 재시도 불가해야 함"
    fi
}

# ══════════════════════════════════════════════════════════════
# 3. envelope.sh 테스트
# ══════════════════════════════════════════════════════════════

test_envelope() {
    section "3. envelope.sh - Envelope 생성"

    source "$BLOCK_DIR/envelope.sh"

    # 3-1. 센티넬 판별 테스트 (내부 case 문이므로 안정적)
    echo "  --- 센티넬 판별 ---"

    if _is_sentinel '__TIMEOUT__'; then
        pass '__TIMEOUT__ → 센티넬'
    else
        fail '__TIMEOUT__ → 센티넬이어야 함'
    fi

    if _is_sentinel '__ERROR__:auth failed'; then
        pass '__ERROR__:auth failed → 센티넬'
    else
        fail '__ERROR__:auth failed → 센티넬이어야 함'
    fi

    if ! _is_sentinel '{"decision": "PASS"}'; then
        pass '{"decision": "PASS"} → 센티넬 아님'
    else
        fail '{"decision": "PASS"} → 센티넬 아니어야 함'
    fi

    # 3-2. Envelope 생성 테스트
    echo ""
    echo "  --- Envelope 생성 ---"

    # 성공 케이스
    local success_env
    success_env=$(_wrap_envelope "claude" "review" "sonnet" '{"decision": "PASS"}' 0 1500 0)

    if echo "$success_env" | python3 -c "import json,sys; obj=json.load(sys.stdin); exit(0 if obj.get('ok')==True else 1)" 2>/dev/null; then
        pass "성공 Envelope: ok=true"
    else
        fail "성공 Envelope: ok=true여야 함"
    fi

    # 실패 케이스
    local fail_env
    fail_env=$(_wrap_envelope "claude" "review" "sonnet" '__TIMEOUT__' 1 5000 0)

    if echo "$fail_env" | python3 -c "import json,sys; obj=json.load(sys.stdin); exit(0 if obj.get('ok')==False else 1)" 2>/dev/null; then
        pass "실패 Envelope: ok=false"
    else
        fail "실패 Envelope: ok=false여야 함"
    fi

    # 에러 코드 확인
    local error_code
    error_code=$(echo "$fail_env" | python3 -c "import json,sys; obj=json.load(sys.stdin); print(obj.get('error',{}).get('code',''))" 2>/dev/null)

    if [[ "$error_code" == "TIMEOUT" ]]; then
        pass "실패 Envelope: error.code=TIMEOUT"
    else
        fail "실패 Envelope: error.code=TIMEOUT이어야 함 (실제: $error_code)"
    fi
}

# ══════════════════════════════════════════════════════════════
# 4. errors.sh 이중 모드 테스트
# ══════════════════════════════════════════════════════════════

test_errors_dual_mode() {
    section "4. errors.sh - Legacy/Envelope 이중 모드"

    local errors_file="$BLOCK_DIR/../../claude/ai_court/lib/util/errors.sh"

    if [[ ! -f "$errors_file" ]]; then
        echo "  ⚠️ errors.sh 파일 없음, 테스트 건너뜀"
        return
    fi

    source "$errors_file"

    # 4-1. Legacy 모드 테스트
    echo "  --- Legacy 모드 ---"

    if is_response_error "__TIMEOUT__"; then
        pass "__TIMEOUT__ → 에러 감지"
    else
        fail "__TIMEOUT__ → 에러로 감지해야 함"
    fi

    if is_response_error "__FAILED__"; then
        pass "__FAILED__ → 에러 감지"
    else
        fail "__FAILED__ → 에러로 감지해야 함"
    fi

    if ! is_response_error '{"decision": "PASS"}'; then
        pass '{"decision": "PASS"} → 에러 아님'
    else
        fail '{"decision": "PASS"} → 에러 아니어야 함'
    fi

    # 4-2. 에러 코드 추출 테스트 (Legacy)
    echo ""
    echo "  --- 에러 코드 추출 ---"

    local code
    code=$(get_response_error_code "__TIMEOUT__")
    if [[ "$code" == "TIMEOUT" ]]; then
        pass "Legacy __TIMEOUT__ → TIMEOUT"
    else
        fail "Legacy __TIMEOUT__ → TIMEOUT이어야 함 (실제: $code)"
    fi

    code=$(get_response_error_code "__STUCK__")
    if [[ "$code" == "TRANSIENT" ]]; then
        pass "Legacy __STUCK__ → TRANSIENT"
    else
        fail "Legacy __STUCK__ → TRANSIENT이어야 함 (실제: $code)"
    fi

    # 4-3. 함수 정의 확인
    echo ""
    echo "  --- Envelope 함수 존재 확인 ---"

    if declare -f is_envelope &>/dev/null; then
        pass "is_envelope 함수 정의됨"
    else
        fail "is_envelope 함수 정의 안됨"
    fi

    if declare -f get_envelope_ok &>/dev/null; then
        pass "get_envelope_ok 함수 정의됨"
    else
        fail "get_envelope_ok 함수 정의 안됨"
    fi

    if declare -f get_envelope_error_code &>/dev/null; then
        pass "get_envelope_error_code 함수 정의됨"
    else
        fail "get_envelope_error_code 함수 정의 안됨"
    fi
}

# ══════════════════════════════════════════════════════════════
# 5. 블록 retry 정책 테스트
# ══════════════════════════════════════════════════════════════

test_retry_policy() {
    section "5. Retry 정책 - 블록 레벨 retry 무효화"

    # claude_block.sh에서 CLAUDE_BLOCK_RETRY 경고 로직 확인
    if grep -q 'CLAUDE_BLOCK_RETRY' "$BLOCK_DIR/claude_block.sh"; then
        pass "claude_block.sh에 RETRY 정책 경고 로직 존재"
    else
        fail "claude_block.sh에 RETRY 정책 경고 로직 없음"
    fi

    # gpt_block.sh에서 GPT_BLOCK_RETRY 경고 로직 확인
    if grep -q 'GPT_BLOCK_RETRY' "$BLOCK_DIR/gpt_block.sh"; then
        pass "gpt_block.sh에 RETRY 정책 경고 로직 존재"
    else
        fail "gpt_block.sh에 RETRY 정책 경고 로직 없음"
    fi
}

# ══════════════════════════════════════════════════════════════
# 메인 실행
# ══════════════════════════════════════════════════════════════

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  🧪 블록 시스템 테스트                                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"

    test_static_checks
    test_error_mapper
    test_envelope
    test_errors_dual_mode
    test_retry_policy

    # 결과 요약
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  테스트 결과"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "  통과: $TESTS_PASSED"
    echo "  실패: $TESTS_FAILED"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "  🎉 모든 테스트 통과!"
        return 0
    else
        echo "  ⚠️ 일부 테스트 실패"
        return 1
    fi
}

main "$@"
