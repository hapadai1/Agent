#!/bin/bash
# ai_court_auction 프로젝트 실행 스크립트
# 사용법: ./run.sh [start|resume|status]

set -e

# 경로 설정
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="$(dirname "$(dirname "$PROJECT_DIR")")"
COMMON_DIR="${AGENT_DIR}/common"

# 공통 모듈 로드
source "${COMMON_DIR}/chatgpt.sh"
source "${COMMON_DIR}/state.sh"

# 프로젝트 전용 모듈 로드
source "${PROJECT_DIR}/lib/util/sections.sh"
source "${PROJECT_DIR}/lib/prompt/prompts.sh"
source "${PROJECT_DIR}/lib/eval/scoring.sh"
source "${PROJECT_DIR}/lib/util/notify.sh"
source "${PROJECT_DIR}/lib/core/workflow.sh"

# 상태 파일 설정
STATE_FILE="${PROJECT_DIR}/state.json"
OUTPUT_DIR="$PROJECT_DIR"

# ══════════════════════════════════════════════════════════════
# 메인 함수
# ══════════════════════════════════════════════════════════════

show_status() {
    echo ""
    echo "━━━ 프로젝트 상태 ━━━"
    echo "프로젝트: $(basename "$PROJECT_DIR")"
    echo "주제: $(state_get '.topic')"
    echo "상태: $(state_get '.global_state')"
    echo ""

    echo "섹션별 진행 상황:"
    for section_id in "${SECTION_ORDER[@]}"; do
        local name state score iter
        name=$(get_section_name "$section_id")
        state=$(state_get ".sections.\"$section_id\".state")
        score=$(state_get ".sections.\"$section_id\".score")
        iter=$(state_get ".sections.\"$section_id\".iteration")
        printf "  %-35s [%-10s] %3d점 (%d회)\n" "$name" "$state" "${score:-0}" "${iter:-0}"
    done
    echo "━━━━━━━━━━━━━━━━━━━━━"
}

start_workflow() {
    local start_section="${1:-}"

    # ChatGPT 탭 확인
    local win tab
    win=$(state_get ".chatgpt.window")
    tab=$(state_get ".chatgpt.tab")

    # 탭 자동 감지 시도
    chatgpt_detect_tabs "$win"

    if [[ -n "$CHATGPT_ASK_TAB" && -n "$CHATGPT_RESEARCH_TAB" ]]; then
        echo ""
        echo "✅ 탭 자동 감지 완료"
        echo "   일반 질문: Tab $CHATGPT_ASK_TAB"
        echo "   심층 리서치: Tab $CHATGPT_RESEARCH_TAB"
        echo ""
    elif [[ -n "$CHATGPT_ASK_TAB" ]]; then
        echo ""
        echo "⚠️  일반 탭만 감지됨 (심층 리서치 탭 없음)"
        echo "   심층 리서치도 일반 탭에서 진행됩니다."
        echo ""
    fi

    if [[ "$win" == "0" || "$tab" == "0" || "$win" == "null" ]]; then
        echo "ChatGPT 탭이 설정되지 않았습니다."
        echo "탭 제목으로 검색 (없으면 Enter):"
        read -r search_title

        if [[ -n "$search_title" ]]; then
            # 탭 찾기
            local found
            found=$(osascript <<EOF
tell application "Google Chrome"
    set winCount to count of windows
    repeat with i from 1 to winCount
        set tabCount to count of tabs of window i
        repeat with j from 1 to tabCount
            set t to tab j of window i
            if URL of t contains "chatgpt" then
                if title of t contains "$search_title" then
                    return (i as string) & ":" & (j as string)
                end if
            end if
        end repeat
    end repeat
    return ""
end tell
EOF
            )
            if [[ -n "$found" ]]; then
                win=$(echo "$found" | cut -d: -f1)
                tab=$(echo "$found" | cut -d: -f2)
            fi
        fi

        if [[ -z "$win" || "$win" == "0" ]]; then
            echo "ChatGPT 탭을 찾을 수 없습니다. Window/Tab 번호 직접 입력:"
            echo "Window 번호 (기본 1):"
            read -r win
            win=${win:-1}
            echo "Tab 번호 (기본 1):"
            read -r tab
            tab=${tab:-1}
        fi

        state_set ".chatgpt.window" "$win"
        state_set ".chatgpt.tab" "$tab"
    fi

    echo ""
    echo "ChatGPT: Window $win, Tab $tab"
    echo ""

    if [[ -n "$start_section" ]]; then
        echo "섹션 '$start_section'부터 시작..."
        resume_from_section "$start_section"
    else
        run_workflow
    fi
}

show_help() {
    echo "사용법: $0 [명령어] [옵션]"
    echo ""
    echo "명령어:"
    echo "  start              처음부터 시작"
    echo "  resume [섹션ID]    특정 섹션부터 재개 (예: s1_2)"
    echo "  status             현재 상태 확인"
    echo "  tabs               ChatGPT 탭 목록"
    echo "  help               도움말"
    echo ""
    echo "섹션 ID 목록:"
    for section_id in "${SECTION_ORDER[@]}"; do
        local name
        name=$(get_section_name "$section_id")
        printf "  %-12s : %s\n" "$section_id" "$name"
    done
}

# ══════════════════════════════════════════════════════════════
# 메인
# ══════════════════════════════════════════════════════════════

case "${1:-}" in
    start)
        start_workflow
        ;;
    resume)
        if [[ -z "${2:-}" ]]; then
            echo "섹션 ID를 입력하세요 (예: s1_2)"
            read -r section_id
            start_workflow "$section_id"
        else
            start_workflow "$2"
        fi
        ;;
    status)
        show_status
        ;;
    tabs)
        echo "━━━ ChatGPT 탭 목록 ━━━"
        chatgpt_tabs
        ;;
    help|--help|-h)
        show_help
        ;;
    "")
        echo ""
        echo "╔══════════════════════════════════════════════╗"
        echo "║     AI 법원 경매 - 사업계획서 Agent          ║"
        echo "╚══════════════════════════════════════════════╝"
        echo ""
        show_status
        echo ""
        echo "실행: $0 start | resume [섹션] | status | help"
        ;;
    *)
        echo "알 수 없는 명령어: $1"
        show_help
        exit 1
        ;;
esac
