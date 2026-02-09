#!/bin/bash
# envelope.sh - 표준 출력 엔벨로프 래핑 함수
#
# 설계 원칙 (de_claude블록.md):
#   - Envelope 모드: 항상 표준 JSON 한 덩어리만 출력
#   - 최상위에 ok(boolean) 필드 필수 (Legacy와 구분)
#   - Legacy 모드에서는 ok 최상위 필드 없음
#
# 사용법:
#   source envelope.sh
#   _wrap_envelope "claude" "review" "sonnet" "$result" "$exit_code" "$duration_ms" "$retries"

_ENVELOPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB_CORE="${_ENVELOPE_DIR}/../../lib/core"

# lib/core/json.sh 로드 (있으면 사용)
if [[ -f "$_LIB_CORE/json.sh" ]]; then
    # shellcheck source=/dev/null
    source "$_LIB_CORE/json.sh"
    _USE_LIB_CORE=true
else
    _USE_LIB_CORE=false
fi

# error_mapper.sh 로드
if [[ -f "$_ENVELOPE_DIR/error_mapper.sh" ]]; then
    source "$_ENVELOPE_DIR/error_mapper.sh"
fi

# ══════════════════════════════════════════════════════════════
# 유틸리티 함수
# ══════════════════════════════════════════════════════════════

# JSON 유효성 검사
# 사용법: if _is_json "$string"; then ...
_is_json() {
    local str="$1"

    # lib/core 사용 가능하면 활용
    if [[ "$_USE_LIB_CORE" == "true" ]]; then
        json_validate "$str"
        return $?
    fi

    python3 -c "
import json, sys
try:
    json.loads(sys.argv[1])
    sys.exit(0)
except:
    sys.exit(1)
" "$str" 2>/dev/null
}

# 센티넬 코드인지 확인
# 사용법: if _is_sentinel "$string"; then ...
_is_sentinel() {
    local str="$1"
    case "$str" in
        __TIMEOUT__|__FAILED__|__STOPPED__|__STUCK__|__EMPTY__|__COMPLETED_BUT_EMPTY__|__ERROR__:*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ══════════════════════════════════════════════════════════════
# 엔벨로프 래핑 함수
# ══════════════════════════════════════════════════════════════

# 성공 엔벨로프 생성
# 사용법: _wrap_envelope_success "provider" "action" "model" "result_json" duration_ms retries
_wrap_envelope_success() {
    local provider="$1"
    local action="$2"
    local model="$3"
    local result="$4"
    local duration_ms="${5:-0}"
    local retries="${6:-0}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    python3 -c "
import json, sys

provider = sys.argv[1]
action = sys.argv[2]
model = sys.argv[3]
result_str = sys.argv[4]
duration_ms = int(sys.argv[5])
retries = int(sys.argv[6])
timestamp = sys.argv[7]

# result가 JSON이면 파싱, 아니면 문자열로
try:
    result = json.loads(result_str)
except:
    result = result_str

envelope = {
    'ok': True,
    'provider': provider,
    'action': action,
    'model': model,
    'result': result,
    'meta': {
        'duration_ms': duration_ms,
        'retries': retries,
        'timestamp': timestamp
    }
}

print(json.dumps(envelope, ensure_ascii=False, indent=2))
" "$provider" "$action" "$model" "$result" "$duration_ms" "$retries" "$timestamp"
}

# 실패 엔벨로프 생성
# 사용법: _wrap_envelope_error "provider" "action" "model" "code" "legacy_code" "message" duration_ms retries
_wrap_envelope_error() {
    local provider="$1"
    local action="$2"
    local model="$3"
    local code="$4"
    local legacy_code="$5"
    local message="$6"
    local duration_ms="${7:-0}"
    local retries="${8:-0}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    python3 -c "
import json, sys

provider = sys.argv[1]
action = sys.argv[2]
model = sys.argv[3]
code = sys.argv[4]
legacy_code = sys.argv[5]
message = sys.argv[6]
duration_ms = int(sys.argv[7])
retries = int(sys.argv[8])
timestamp = sys.argv[9]

envelope = {
    'ok': False,
    'provider': provider,
    'action': action,
    'model': model,
    'error': {
        'code': code,
        'legacy_code': legacy_code,
        'message': message
    },
    'meta': {
        'duration_ms': duration_ms,
        'retries': retries,
        'timestamp': timestamp
    }
}

print(json.dumps(envelope, ensure_ascii=False, indent=2))
" "$provider" "$action" "$model" "$code" "$legacy_code" "$message" "$duration_ms" "$retries" "$timestamp"
}

# 통합 엔벨로프 래핑 (자동 판별)
# 사용법: _wrap_envelope "provider" "action" "model" "$result" $exit_code $duration_ms $retries
_wrap_envelope() {
    local provider="$1"
    local action="$2"
    local model="$3"
    local result="$4"
    local exit_code="${5:-0}"
    local duration_ms="${6:-0}"
    local retries="${7:-0}"

    # exit_code가 0이 아니면 에러
    if [[ "$exit_code" -ne 0 ]]; then
        local code
        local legacy_code="$result"
        local message=""

        # 센티넬이면 매핑
        if _is_sentinel "$result"; then
            code=$(_map_error_code "$result" "$provider")
            message=$(_get_error_message "$result")
        else
            # 센티넬이 아닌 에러
            code="UNKNOWN"
            legacy_code="__FAILED__"
            message="Unknown error: ${result:0:200}"
        fi

        _wrap_envelope_error "$provider" "$action" "$model" "$code" "$legacy_code" "$message" "$duration_ms" "$retries"
        return 1
    fi

    # exit_code=0인데 센티넬이면 에러로 처리
    if _is_sentinel "$result"; then
        local code
        code=$(_map_error_code "$result" "$provider")
        local message
        message=$(_get_error_message "$result")

        _wrap_envelope_error "$provider" "$action" "$model" "$code" "$result" "$message" "$duration_ms" "$retries"
        return 1
    fi

    # JSON이면 성공
    if _is_json "$result"; then
        _wrap_envelope_success "$provider" "$action" "$model" "$result" "$duration_ms" "$retries"
        return 0
    fi

    # JSON도 아니고 센티넬도 아님 - 텍스트 결과로 성공 처리
    _wrap_envelope_success "$provider" "$action" "$model" "$result" "$duration_ms" "$retries"
    return 0
}

# ══════════════════════════════════════════════════════════════
# 스크립트 직접 실행 시 도움말
# ══════════════════════════════════════════════════════════════

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "Envelope 래핑 함수 스크립트"
    echo ""
    echo "사용법: source envelope.sh 로 로드 후 함수 사용"
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "주요 함수"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "_wrap_envelope provider action model result exit_code duration_ms retries"
    echo "  - 자동으로 성공/실패 판별 후 엔벨로프 생성"
    echo ""
    echo "_wrap_envelope_success provider action model result duration_ms retries"
    echo "  - 성공 엔벨로프 생성"
    echo ""
    echo "_wrap_envelope_error provider action model code legacy_code message duration_ms retries"
    echo "  - 실패 엔벨로프 생성"
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "예시 출력 (성공)"
    echo "═══════════════════════════════════════════════════"
    _wrap_envelope_success "claude" "review" "sonnet" '{"decision":"PASS","reasons":["good"]}' 1234 0
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "예시 출력 (실패)"
    echo "═══════════════════════════════════════════════════"
    _wrap_envelope_error "claude" "review" "sonnet" "TIMEOUT" "__TIMEOUT__" "Request timed out after 300s" 300000 2
fi
