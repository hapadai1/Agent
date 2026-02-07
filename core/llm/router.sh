#!/bin/bash
# router.sh - LLM Provider 통합 라우터
# 사용법: llm_call <provider> [옵션] "메시지"
#
# Provider: openai, claude
# 옵션은 각 provider 구현체로 전달됨

LLM_ROUTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Provider 구현체 로드
_llm_load_provider() {
    local provider="$1"
    local provider_file="${LLM_ROUTER_DIR}/${provider}.sh"

    if [[ ! -f "$provider_file" ]]; then
        echo "ERROR: Unknown provider: $provider" >&2
        echo "Available providers: openai, claude" >&2
        return 1
    fi

    source "$provider_file"
}

# Usage meter 로드
if [[ -f "${LLM_ROUTER_DIR}/usage_meter.sh" ]]; then
    source "${LLM_ROUTER_DIR}/usage_meter.sh"
fi

# ══════════════════════════════════════════════════════════════
# 통합 LLM 호출 함수
# ══════════════════════════════════════════════════════════════
# 사용법: llm_call <provider> [옵션] "메시지"
#
# 공통 옵션:
#   --tab=N         탭 번호 (openai)
#   --timeout=N     타임아웃 초
#   --retry         재시도 활성화
#   --mode=MODE     모드 (normal, research, new_chat 등)
#   --output=PATH   결과 저장 경로
#   --log           사용량 로깅 활성화
#
# 예시:
#   llm_call openai --tab=2 --retry "질문 내용"
#   llm_call claude --timeout=120 "코드 작성해줘"
# ══════════════════════════════════════════════════════════════
llm_call() {
    local provider="$1"
    shift

    if [[ -z "$provider" ]]; then
        echo "ERROR: Provider required" >&2
        echo "Usage: llm_call <provider> [options] \"message\"" >&2
        return 1
    fi

    # Provider 로드
    _llm_load_provider "$provider" || return 1

    # 옵션 파싱 (공통 옵션 추출)
    local output_path=""
    local enable_log=false
    local start_time
    local args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output=*)
                output_path="${1#--output=}"
                shift
                ;;
            --log)
                enable_log=true
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # 시작 시간 기록
    start_time=$(date +%s%3N 2>/dev/null || date +%s)

    # Provider별 호출
    local response
    local exit_code

    case "$provider" in
        openai)
            response=$(openai_call "${args[@]}")
            exit_code=$?
            ;;
        claude)
            response=$(claude_call "${args[@]}")
            exit_code=$?
            ;;
        *)
            echo "ERROR: Provider '$provider' not implemented" >&2
            return 1
            ;;
    esac

    # 종료 시간 및 latency 계산
    local end_time
    end_time=$(date +%s%3N 2>/dev/null || date +%s)
    local latency=$((end_time - start_time))

    # 사용량 로깅
    if [[ "$enable_log" == "true" ]] && type usage_log &>/dev/null; then
        usage_log "$provider" "$latency" "${#response}" "$exit_code"
    fi

    # 결과 저장
    if [[ -n "$output_path" ]]; then
        mkdir -p "$(dirname "$output_path")"
        echo "$response" > "$output_path"
        echo "Saved: $output_path" >&2
    fi

    echo "$response"
    return $exit_code
}

# ══════════════════════════════════════════════════════════════
# Provider 목록 조회
# ══════════════════════════════════════════════════════════════
llm_providers() {
    echo "Available LLM Providers:"
    echo ""

    for f in "${LLM_ROUTER_DIR}"/*.sh; do
        local name=$(basename "$f" .sh)
        if [[ "$name" != "router" && "$name" != "usage_meter" ]]; then
            echo "  - $name"
        fi
    done
}

# ══════════════════════════════════════════════════════════════
# Provider 상태 확인
# ══════════════════════════════════════════════════════════════
llm_status() {
    echo "LLM Router Status"
    echo "═══════════════════════════════════════"
    echo ""

    # OpenAI (ChatGPT Chrome)
    echo "[OpenAI - Chrome ChatGPT]"
    if type chatgpt_tabs &>/dev/null; then
        chatgpt_tabs 2>/dev/null | head -5
    else
        echo "  Not loaded (source core/llm/openai.sh)"
    fi
    echo ""

    # Claude
    echo "[Claude - API]"
    if [[ -n "$ANTHROPIC_API_KEY" ]]; then
        echo "  API Key: ${ANTHROPIC_API_KEY:0:10}..."
    else
        echo "  API Key: Not set (export ANTHROPIC_API_KEY=...)"
    fi
    echo ""

    # Usage stats
    if type usage_stats &>/dev/null; then
        echo "[Usage Stats]"
        usage_stats
    fi
}

# ══════════════════════════════════════════════════════════════
# 직접 실행 시 도움말
# ══════════════════════════════════════════════════════════════
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "LLM Router - 통합 LLM 호출 인터페이스"
    echo ""
    echo "사용법:"
    echo "  source router.sh"
    echo "  llm_call <provider> [options] \"message\""
    echo ""
    echo "Provider:"
    echo "  openai    - ChatGPT (Chrome 자동화)"
    echo "  claude    - Claude API"
    echo ""
    echo "공통 옵션:"
    echo "  --output=PATH   결과 저장 경로"
    echo "  --log           사용량 로깅"
    echo ""
    echo "예시:"
    echo "  llm_call openai --tab=2 --retry \"질문\""
    echo "  llm_call claude --timeout=120 \"코드 작성\""
    echo ""
    echo "함수:"
    echo "  llm_providers   사용 가능한 provider 목록"
    echo "  llm_status      provider 상태 확인"
fi
