#!/bin/bash
# openai.sh - OpenAI/ChatGPT Provider (Chrome 자동화)
# common/chatgpt.sh를 래핑하여 통합 인터페이스 제공

OPENAI_PROVIDER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(dirname "$OPENAI_PROVIDER_DIR")"
AGENT_ROOT="$(dirname "$CORE_DIR")"

# 기존 chatgpt.sh 로드
_openai_load_chatgpt() {
    local chatgpt_paths=(
        "${AGENT_ROOT}/common/chatgpt.sh"
        "${CHATGPT_SCRIPT:-}"
    )

    for path in "${chatgpt_paths[@]}"; do
        if [[ -f "$path" ]]; then
            source "$path"
            return 0
        fi
    done

    echo "ERROR: chatgpt.sh not found" >&2
    echo "Expected at: ${AGENT_ROOT}/common/chatgpt.sh" >&2
    return 1
}

# 초기 로드
_openai_load_chatgpt 2>/dev/null

# ══════════════════════════════════════════════════════════════
# OpenAI Provider 호출 함수
# ══════════════════════════════════════════════════════════════
# 사용법: openai_call [옵션] "메시지"
#
# 옵션:
#   --mode=MODE     모드 (normal, research, new_chat, continue, get_response)
#   --tab=N         탭 번호
#   --win=N         윈도우 번호
#   --timeout=N     타임아웃 초
#   --retry         재시도 활성화
#   --retry-count=N 재시도 횟수
#   --project=URL   프로젝트 URL
#   --section=ID    섹션 ID (변경 시 자동 new chat)
#   --no-wait       응답 대기 없이 전송만
#
# 예시:
#   openai_call --tab=2 --retry "질문"
#   openai_call --mode=research --timeout=300 "리서치 요청"
# ══════════════════════════════════════════════════════════════
openai_call() {
    # chatgpt.sh 로드 확인
    if ! type chatgpt_call &>/dev/null; then
        _openai_load_chatgpt || return 1
    fi

    # chatgpt_call로 전달
    chatgpt_call "$@"
}

# ══════════════════════════════════════════════════════════════
# 편의 함수들
# ══════════════════════════════════════════════════════════════

# 일반 질문
openai_ask() {
    local message="$1"
    local tab="${2:-1}"
    local timeout="${3:-90}"

    openai_call --tab="$tab" --timeout="$timeout" "$message"
}

# 재시도 포함 질문
openai_ask_retry() {
    local message="$1"
    local tab="${2:-1}"
    local timeout="${3:-90}"

    openai_call --tab="$tab" --timeout="$timeout" --retry "$message"
}

# 심층 리서치
openai_research() {
    local message="$1"
    local tab="${2:-1}"
    local timeout="${3:-300}"

    openai_call --mode=research --tab="$tab" --timeout="$timeout" "$message"
}

# 새 대화 시작
openai_new_chat() {
    local tab="${1:-1}"
    local project_url="${2:-}"

    if [[ -n "$project_url" ]]; then
        openai_call --mode=new_chat --tab="$tab" --project="$project_url"
    else
        openai_call --mode=new_chat --tab="$tab"
    fi
}

# 마지막 응답 가져오기
openai_get_response() {
    local tab="${1:-1}"
    openai_call --mode=get_response --tab="$tab"
}

# ══════════════════════════════════════════════════════════════
# 탭 관리
# ══════════════════════════════════════════════════════════════

# 탭 목록
openai_tabs() {
    if type chatgpt_tabs &>/dev/null; then
        chatgpt_tabs
    else
        echo "ERROR: chatgpt_tabs not available" >&2
        return 1
    fi
}

# 탭 감지
openai_detect_tabs() {
    if type chatgpt_detect_tabs &>/dev/null; then
        chatgpt_detect_tabs "$@"
    else
        echo "ERROR: chatgpt_detect_tabs not available" >&2
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════
# 세션 관리
# ══════════════════════════════════════════════════════════════

openai_session_status() {
    if type chatgpt_session_status &>/dev/null; then
        chatgpt_session_status
    fi
}

openai_session_reset() {
    if type chatgpt_session_reset &>/dev/null; then
        chatgpt_session_reset
    fi
}

# ══════════════════════════════════════════════════════════════
# Provider 정보
# ══════════════════════════════════════════════════════════════

openai_info() {
    echo "OpenAI Provider (Chrome ChatGPT Automation)"
    echo "═══════════════════════════════════════════"
    echo ""
    echo "Backend: common/chatgpt.sh"
    echo "Method:  Chrome + osascript"
    echo ""
    echo "Loaded: $(type chatgpt_call &>/dev/null && echo 'Yes' || echo 'No')"
    echo ""
    if type chatgpt_call &>/dev/null; then
        echo "Available tabs:"
        openai_tabs 2>/dev/null | head -5
    fi
}

# 직접 실행 시 정보 출력
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    openai_info
fi
