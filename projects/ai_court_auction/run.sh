#!/bin/bash
# ai_court_auction 프로젝트 실행 스크립트
# agent-run의 thin wrapper + 프로젝트별 기능
#
# 사용법:
#   ./run.sh                  # 상태 확인 및 메뉴
#   ./run.sh start            # 처음부터 시작
#   ./run.sh resume [section] # 섹션부터 재개
#   ./run.sh status           # 상태 확인
#   ./run.sh tabs             # ChatGPT 탭 목록
#   ./run.sh help             # 도움말

set -e

# ══════════════════════════════════════════════════════════════
# 경로 설정
# ══════════════════════════════════════════════════════════════

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(dirname "$(dirname "$PROJECT_DIR")")"
CORE_DIR="${AGENT_ROOT}/core"
BIN_DIR="${AGENT_ROOT}/bin"
COMMON_DIR="${AGENT_ROOT}/common"

export PROJECT_DIR
export PROJECT_NAME="ai_court_auction"

# ══════════════════════════════════════════════════════════════
# 모듈 로드
# ══════════════════════════════════════════════════════════════

# Core 모듈
source "${CORE_DIR}/util/notify.sh" 2>/dev/null || true
source "${CORE_DIR}/util/sections_loader.sh" 2>/dev/null || true

# Common 모듈 (ChatGPT 연동)
source "${COMMON_DIR}/chatgpt.sh" 2>/dev/null || true
source "${COMMON_DIR}/state.sh" 2>/dev/null || true

# Sections 초기화
_sections_init_order 2>/dev/null || true

# ══════════════════════════════════════════════════════════════
# 설정
# ══════════════════════════════════════════════════════════════

STATE_FILE="${PROJECT_DIR}/state.json"
OUTPUT_DIR="${PROJECT_DIR}"

# ══════════════════════════════════════════════════════════════
# 상태 확인
# ══════════════════════════════════════════════════════════════

show_status() {
    echo ""
    echo "━━━ 프로젝트 상태 ━━━"
    echo "프로젝트: $(basename "$PROJECT_DIR")"

    if [[ -f "$STATE_FILE" ]]; then
        echo "주제: $(state_get '.topic' 2>/dev/null || echo 'N/A')"
        echo "상태: $(state_get '.global_state' 2>/dev/null || echo 'N/A')"
        echo ""

        echo "섹션별 진행 상황:"

        # SECTION_ORDER 사용 또는 sections_list 사용
        local sections
        if [[ -n "${SECTION_ORDER[*]:-}" ]]; then
            sections=("${SECTION_ORDER[@]}")
        elif type sections_list &>/dev/null; then
            mapfile -t sections < <(sections_list 2>/dev/null)
        else
            echo "  (섹션 정보 없음)"
            return
        fi

        for section_id in "${sections[@]}"; do
            local name state score iter

            # section_get_name 또는 get_section_name 사용
            if type section_get_name &>/dev/null; then
                name=$(section_get_name "$section_id" 2>/dev/null)
            elif type get_section_name &>/dev/null; then
                name=$(get_section_name "$section_id" 2>/dev/null)
            else
                name="$section_id"
            fi

            state=$(state_get ".sections.\"$section_id\".state" 2>/dev/null || echo "-")
            score=$(state_get ".sections.\"$section_id\".score" 2>/dev/null || echo "0")
            iter=$(state_get ".sections.\"$section_id\".iteration" 2>/dev/null || echo "0")

            printf "  %-35s [%-10s] %3d점 (%d회)\n" "$name" "$state" "${score:-0}" "${iter:-0}"
        done
    else
        echo "상태 파일 없음 (신규 프로젝트)"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━"
}

# ══════════════════════════════════════════════════════════════
# ChatGPT 탭 설정
# ══════════════════════════════════════════════════════════════

setup_chatgpt_tabs() {
    # 기존 탭 정보 확인
    local win tab
    win=$(state_get ".chatgpt.window" 2>/dev/null || echo "0")
    tab=$(state_get ".chatgpt.tab" 2>/dev/null || echo "0")

    # 탭 자동 감지 시도
    if type chatgpt_detect_tabs &>/dev/null; then
        chatgpt_detect_tabs "$win" 2>/dev/null || true
    fi

    if [[ -n "${CHATGPT_ASK_TAB:-}" && -n "${CHATGPT_RESEARCH_TAB:-}" ]]; then
        echo ""
        echo "✅ 탭 자동 감지 완료"
        echo "   일반 질문: Tab $CHATGPT_ASK_TAB"
        echo "   심층 리서치: Tab $CHATGPT_RESEARCH_TAB"
        echo ""
        return 0
    elif [[ -n "${CHATGPT_ASK_TAB:-}" ]]; then
        echo ""
        echo "⚠️  일반 탭만 감지됨 (심층 리서치 탭 없음)"
        echo ""
        return 0
    fi

    # 수동 설정
    if [[ "$win" == "0" || "$tab" == "0" || "$win" == "null" ]]; then
        echo "ChatGPT 탭이 설정되지 않았습니다."
        echo "탭 제목으로 검색 (없으면 Enter):"
        read -r search_title

        if [[ -n "$search_title" ]]; then
            local found
            found=$(osascript <<EOF 2>/dev/null
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

        state_set ".chatgpt.window" "$win" 2>/dev/null || true
        state_set ".chatgpt.tab" "$tab" 2>/dev/null || true
    fi

    echo ""
    echo "ChatGPT: Window $win, Tab $tab"
    echo ""
}

# ══════════════════════════════════════════════════════════════
# 워크플로우 실행
# ══════════════════════════════════════════════════════════════

start_workflow() {
    local start_section="${1:-}"

    # ChatGPT 탭 설정
    setup_chatgpt_tabs

    # agent-run 호출 또는 레거시 워크플로우
    if [[ -x "${BIN_DIR}/agent-run" ]]; then
        local args=("--project=$PROJECT_NAME")

        if [[ -n "$start_section" ]]; then
            args+=("--section=$start_section")
        fi

        echo "Executing: agent-run ${args[*]}"
        "${BIN_DIR}/agent-run" "${args[@]}"
    else
        # 레거시 워크플로우 (핸들러 직접 로드)
        echo "[LEGACY MODE] agent-run을 찾을 수 없어 레거시 모드로 실행"

        # 프로젝트 핸들러 로드
        if [[ -f "${PROJECT_DIR}/handlers/workflow.sh" ]]; then
            source "${PROJECT_DIR}/handlers/workflow.sh"
        elif [[ -f "${PROJECT_DIR}/lib/core/workflow.sh" ]]; then
            source "${PROJECT_DIR}/lib/core/workflow.sh"
        fi

        if [[ -n "$start_section" ]]; then
            echo "섹션 '$start_section'부터 시작..."
            if type resume_from_section &>/dev/null; then
                resume_from_section "$start_section"
            else
                echo "ERROR: resume_from_section function not found"
                exit 1
            fi
        else
            if type run_workflow &>/dev/null; then
                run_workflow
            else
                echo "ERROR: run_workflow function not found"
                exit 1
            fi
        fi
    fi
}

# ══════════════════════════════════════════════════════════════
# 도움말
# ══════════════════════════════════════════════════════════════

show_help() {
    echo "사용법: $0 [명령어] [옵션]"
    echo ""
    echo "명령어:"
    echo "  start              처음부터 시작"
    echo "  resume [섹션ID]    특정 섹션부터 재개 (예: s1_2)"
    echo "  challenger [섹션]  Challenger 모드 (섹션별 5회 반복 + 평가)"
    echo "  status             현재 상태 확인"
    echo "  tabs               ChatGPT 탭 목록"
    echo "  help               도움말"
    echo ""
    echo "Challenger 옵션:"
    echo "  --max=N            최대 반복 횟수 (기본: 5)"
    echo "  --target=N         목표 점수 (기본: 95)"
    echo "  --from=섹션ID      해당 섹션부터 전체 실행"
    echo ""
    echo "예시:"
    echo "  $0 challenger s1_2              # s1_2만 5회 반복"
    echo "  $0 challenger                   # 전체 섹션 순차 실행"
    echo "  $0 challenger --from=s1_2       # s1_2부터 끝까지"
    echo "  $0 challenger s1_2 --max=3      # 최대 3회"
    echo "  $0 challenger s1_2 --target=90  # 90점 목표"
    echo ""
    echo "섹션 ID 목록:"

    local sections
    if [[ -n "${SECTION_ORDER[*]:-}" ]]; then
        sections=("${SECTION_ORDER[@]}")
    elif type sections_list &>/dev/null; then
        mapfile -t sections < <(sections_list 2>/dev/null)
    fi

    for section_id in "${sections[@]:-}"; do
        local name
        if type section_get_name &>/dev/null; then
            name=$(section_get_name "$section_id" 2>/dev/null)
        elif type get_section_name &>/dev/null; then
            name=$(get_section_name "$section_id" 2>/dev/null)
        else
            name="$section_id"
        fi
        printf "  %-12s : %s\n" "$section_id" "$name"
    done

    echo ""
    echo "또는 agent-run 직접 사용:"
    echo "  agent-run --project=$PROJECT_NAME [options]"
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
        if type chatgpt_tabs &>/dev/null; then
            chatgpt_tabs
        else
            echo "(chatgpt_tabs 함수 없음)"
        fi
        ;;
    help|--help|-h)
        show_help
        ;;
    challenger)
        # Challenger 모드: 섹션별 5회 반복 + 평가 + 자동 판정
        echo ""
        echo "╔══════════════════════════════════════════════╗"
        echo "║     Challenger 모드 시작                     ║"
        echo "╚══════════════════════════════════════════════╝"
        echo ""

        # actions.sh 로드
        source "${AGENT_ROOT}/core/agent/actions.sh"

        # 인자 파싱
        section="${2:-}"
        max_iter=5
        target_score=95
        from_section=""

        # 두번째 인자가 --로 시작하면 옵션임
        if [[ "$section" == --* ]]; then
            section=""
        fi

        # 옵션 파싱
        shift 1 2>/dev/null || true
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --max=*) max_iter="${1#--max=}" ;;
                --target=*) target_score="${1#--target=}" ;;
                --from=*) from_section="${1#--from=}" ;;
                --*) ;;  # 다른 옵션 무시
                *) [[ -z "$section" ]] && section="$1" ;;  # 첫 위치 인자는 섹션
            esac
            shift
        done

        if [[ -n "$section" ]]; then
            # 특정 섹션만 실행
            echo "섹션: $section, 반복: ${max_iter}회, 목표: ${target_score}점"
            agent_section_loop "$section" "$max_iter" "$target_score" "challenger"
        elif [[ -n "$from_section" ]]; then
            # 특정 섹션부터 전체 실행
            echo "시작: $from_section 부터, 반복: ${max_iter}회, 목표: ${target_score}점"
            agent_run_all_sections "$max_iter" "$target_score" "challenger" "$from_section"
        else
            # 전체 섹션 실행
            echo "전체 섹션 실행, 반복: ${max_iter}회, 목표: ${target_score}점"
            agent_run_all_sections "$max_iter" "$target_score" "challenger"
        fi
        ;;
    "")
        echo ""
        echo "╔══════════════════════════════════════════════╗"
        echo "║     AI 법원 경매 - 사업계획서 Agent          ║"
        echo "╚══════════════════════════════════════════════╝"
        echo ""
        show_status
        echo ""
        echo "실행: $0 start | resume [섹션] | challenger [섹션] | status | help"
        ;;
    *)
        # agent-run 스타일 인자 전달
        if [[ "$1" == --* ]]; then
            echo "agent-run으로 전달: $*"
            "${BIN_DIR}/agent-run" --project="$PROJECT_NAME" "$@"
        else
            echo "알 수 없는 명령어: $1"
            show_help
            exit 1
        fi
        ;;
esac
