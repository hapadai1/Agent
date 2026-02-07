#!/bin/bash
# claude.sh - Claude API Provider
# Anthropic Claude API를 직접 호출

CLAUDE_PROVIDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ══════════════════════════════════════════════════════════════
# 설정
# ══════════════════════════════════════════════════════════════

# API 설정
: "${ANTHROPIC_API_KEY:=}"
: "${CLAUDE_MODEL:=claude-sonnet-4-20250514}"
: "${CLAUDE_MAX_TOKENS:=4096}"
: "${CLAUDE_TIMEOUT:=120}"
: "${CLAUDE_RETRY_COUNT:=3}"
: "${CLAUDE_RETRY_DELAY:=2}"

# API 엔드포인트
CLAUDE_API_URL="https://api.anthropic.com/v1/messages"

# ══════════════════════════════════════════════════════════════
# Claude Provider 호출 함수
# ══════════════════════════════════════════════════════════════
# 사용법: claude_call [옵션] "메시지"
#
# 옵션:
#   --model=MODEL       모델 (기본: claude-sonnet-4-20250514)
#   --max-tokens=N      최대 토큰 (기본: 4096)
#   --timeout=N         타임아웃 초 (기본: 120)
#   --retry             재시도 활성화
#   --retry-count=N     재시도 횟수 (기본: 3)
#   --system=TEXT       시스템 프롬프트
#   --temperature=N     온도 (0.0-1.0)
#
# 예시:
#   claude_call "코드 작성해줘"
#   claude_call --model=claude-opus-4-20250514 --system="You are a developer" "질문"
# ══════════════════════════════════════════════════════════════
claude_call() {
    # API 키 확인
    if [[ -z "$ANTHROPIC_API_KEY" ]]; then
        echo "ERROR: ANTHROPIC_API_KEY not set" >&2
        echo "Export your API key: export ANTHROPIC_API_KEY=sk-..." >&2
        return 1
    fi

    # 옵션 파싱
    local model="$CLAUDE_MODEL"
    local max_tokens="$CLAUDE_MAX_TOKENS"
    local timeout="$CLAUDE_TIMEOUT"
    local retry=false
    local retry_count="$CLAUDE_RETRY_COUNT"
    local system_prompt=""
    local temperature=""
    local message=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model=*)
                model="${1#--model=}"
                shift
                ;;
            --max-tokens=*)
                max_tokens="${1#--max-tokens=}"
                shift
                ;;
            --timeout=*)
                timeout="${1#--timeout=}"
                shift
                ;;
            --retry)
                retry=true
                shift
                ;;
            --retry-count=*)
                retry_count="${1#--retry-count=}"
                shift
                ;;
            --system=*)
                system_prompt="${1#--system=}"
                shift
                ;;
            --temperature=*)
                temperature="${1#--temperature=}"
                shift
                ;;
            -*)
                echo "WARNING: Unknown option: $1" >&2
                shift
                ;;
            *)
                if [[ -z "$message" ]]; then
                    message="$1"
                else
                    message="$message $1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$message" ]]; then
        echo "ERROR: Message required" >&2
        return 1
    fi

    # API 호출 실행
    if [[ "$retry" == "true" ]]; then
        _claude_call_with_retry "$message" "$model" "$max_tokens" "$timeout" "$retry_count" "$system_prompt" "$temperature"
    else
        _claude_call_once "$message" "$model" "$max_tokens" "$timeout" "$system_prompt" "$temperature"
    fi
}

# 단일 API 호출
_claude_call_once() {
    local message="$1"
    local model="$2"
    local max_tokens="$3"
    local timeout="$4"
    local system_prompt="$5"
    local temperature="$6"

    # JSON 페이로드 구성
    local payload
    payload=$(python3 -c "
import json
import sys

data = {
    'model': '$model',
    'max_tokens': $max_tokens,
    'messages': [
        {'role': 'user', 'content': '''$message'''}
    ]
}

if '''$system_prompt''':
    data['system'] = '''$system_prompt'''

if '''$temperature''':
    data['temperature'] = float('$temperature')

print(json.dumps(data, ensure_ascii=False))
" 2>/dev/null)

    if [[ -z "$payload" ]]; then
        echo "ERROR: Failed to build request payload" >&2
        return 1
    fi

    # API 호출
    local response
    response=$(curl -s --max-time "$timeout" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d "$payload" \
        "$CLAUDE_API_URL" 2>/dev/null)

    if [[ -z "$response" ]]; then
        echo "ERROR: Empty response from API" >&2
        return 1
    fi

    # 에러 체크
    local error_type
    error_type=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error',{}).get('type',''))" 2>/dev/null)

    if [[ -n "$error_type" ]]; then
        local error_msg
        error_msg=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error',{}).get('message','Unknown error'))" 2>/dev/null)
        echo "ERROR: $error_type - $error_msg" >&2
        return 1
    fi

    # 응답 텍스트 추출
    local content
    content=$(echo "$response" | python3 -c "
import json
import sys

try:
    data = json.load(sys.stdin)
    contents = data.get('content', [])
    texts = [c.get('text', '') for c in contents if c.get('type') == 'text']
    print(''.join(texts))
except Exception as e:
    print(f'Parse error: {e}', file=sys.stderr)
" 2>/dev/null)

    echo "$content"
}

# 재시도 포함 API 호출
_claude_call_with_retry() {
    local message="$1"
    local model="$2"
    local max_tokens="$3"
    local timeout="$4"
    local retry_count="$5"
    local system_prompt="$6"
    local temperature="$7"

    local attempt=1
    local response=""

    while [[ $attempt -le $retry_count ]]; do
        echo "━━━ Claude 시도 ${attempt}/${retry_count} ━━━" >&2

        response=$(_claude_call_once "$message" "$model" "$max_tokens" "$timeout" "$system_prompt" "$temperature")
        local exit_code=$?

        if [[ $exit_code -eq 0 && -n "$response" && ${#response} -gt 10 ]]; then
            echo "✅ 응답 수신 (${#response}자)" >&2
            echo "$response"
            return 0
        fi

        echo "⚠️ 실패 또는 응답 너무 짧음" >&2

        if [[ $attempt -lt $retry_count ]]; then
            echo "🔄 ${CLAUDE_RETRY_DELAY}초 후 재시도..." >&2
            sleep "$CLAUDE_RETRY_DELAY"
        fi

        ((attempt++))
    done

    echo "❌ ${retry_count}회 모두 실패" >&2
    echo "$response"
    return 1
}

# ══════════════════════════════════════════════════════════════
# 편의 함수들
# ══════════════════════════════════════════════════════════════

# 일반 질문
claude_ask() {
    local message="$1"
    claude_call "$message"
}

# 코드 작성 (시스템 프롬프트 포함)
claude_code() {
    local message="$1"
    local language="${2:-}"

    local system="You are an expert programmer. Write clean, efficient code with proper error handling."
    if [[ -n "$language" ]]; then
        system="$system Focus on $language."
    fi

    claude_call --system="$system" "$message"
}

# 코드 리뷰
claude_review() {
    local code="$1"

    claude_call --system="You are a code reviewer. Analyze the code for bugs, security issues, and improvements." \
        "Review this code:\n\n$code"
}

# ══════════════════════════════════════════════════════════════
# 모델 선택
# ══════════════════════════════════════════════════════════════

claude_use_sonnet() {
    export CLAUDE_MODEL="claude-sonnet-4-20250514"
    echo "Model set to: $CLAUDE_MODEL" >&2
}

claude_use_opus() {
    export CLAUDE_MODEL="claude-opus-4-20250514"
    echo "Model set to: $CLAUDE_MODEL" >&2
}

claude_use_haiku() {
    export CLAUDE_MODEL="claude-haiku-4-20250514"
    echo "Model set to: $CLAUDE_MODEL" >&2
}

# ══════════════════════════════════════════════════════════════
# Provider 정보
# ══════════════════════════════════════════════════════════════

claude_info() {
    echo "Claude Provider (Anthropic API)"
    echo "═══════════════════════════════════════════"
    echo ""
    echo "API URL:    $CLAUDE_API_URL"
    echo "Model:      $CLAUDE_MODEL"
    echo "Max Tokens: $CLAUDE_MAX_TOKENS"
    echo "Timeout:    ${CLAUDE_TIMEOUT}s"
    echo ""
    if [[ -n "$ANTHROPIC_API_KEY" ]]; then
        echo "API Key:    ${ANTHROPIC_API_KEY:0:10}... (set)"
    else
        echo "API Key:    NOT SET"
        echo ""
        echo "Set your API key:"
        echo "  export ANTHROPIC_API_KEY=sk-ant-..."
    fi
}

# 직접 실행 시 정보 출력
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    claude_info
fi
