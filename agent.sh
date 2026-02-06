#!/bin/bash
# agent.sh - 멀티 프로젝트 Agent 메인 진입점
# 여러 프로젝트와 워크플로우를 관리하는 통합 에이전트

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="${SCRIPT_DIR}/common"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
PROJECTS_DIR="${SCRIPT_DIR}/projects"

# 공통 모듈 로드
source "${COMMON_DIR}/chatgpt.sh"
source "${COMMON_DIR}/state.sh"
source "${COMMON_DIR}/project_manager.sh"

# 전역 변수
PROJECT_DIR=""
TEMPLATE=""

# ══════════════════════════════════════════════════════════════
# UI 헬퍼
# ══════════════════════════════════════════════════════════════

print_header() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              멀티 프로젝트 Agent v1.0                    ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
}

print_menu() {
    echo ""
    echo "━━━ 메뉴 ━━━"
    echo "  1. 프로젝트 목록 보기"
    echo "  2. 프로젝트 선택/재개"
    echo "  3. 새 프로젝트 생성"
    echo "  4. ChatGPT 탭 목록"
    echo "  5. 템플릿 목록"
    echo "  q. 종료"
    echo "━━━━━━━━━━━━"
}

# ══════════════════════════════════════════════════════════════
# 프로젝트 생성 인터페이스
# ══════════════════════════════════════════════════════════════

interactive_create_project() {
    echo ""
    echo "━━━ 새 프로젝트 생성 ━━━"
    echo ""

    # 템플릿 선택
    list_templates
    echo ""
    echo "템플릿 선택 (이름 입력):"
    read -r template_name

    if [[ ! -d "${TEMPLATES_DIR}/${template_name}" ]]; then
        echo "오류: 템플릿을 찾을 수 없습니다."
        return 1
    fi

    # 프로젝트명 입력
    echo ""
    echo "프로젝트명 입력 (영문, 언더스코어 사용):"
    read -r project_name

    if [[ -z "$project_name" ]]; then
        echo "오류: 프로젝트명이 필요합니다."
        return 1
    fi

    # 주제 입력
    echo ""
    echo "프로젝트 주제/설명 입력:"
    read -r topic

    # 생성
    create_project "$project_name" "$template_name" "$topic"

    # ChatGPT 탭 설정
    echo ""
    echo "ChatGPT 탭 설정:"
    echo "  1. 기존 대화 사용 (제목으로 검색)"
    echo "  2. 새 대화 시작"
    read -r tab_choice

    local proj_dir="${PROJECTS_DIR}/${project_name}"

    case "$tab_choice" in
        1)
            echo "ChatGPT 대화 제목 입력 (부분 일치):"
            read -r chat_title
            local found
            found=$(find_chatgpt_tab_by_title "$chat_title")
            if [[ -n "$found" ]]; then
                local win tab
                win=$(echo "$found" | cut -d: -f1)
                tab=$(echo "$found" | cut -d: -f2)
                save_chatgpt_session "$proj_dir" "$win" "$tab" "$chat_title"
                echo "탭 연결됨: Window $win, Tab $tab"
            else
                echo "탭을 찾을 수 없습니다. 새 탭을 생성합니다."
                local new_tab
                new_tab=$(open_new_chatgpt_tab 1)
                sleep 2
                save_chatgpt_session "$proj_dir" 1 "$new_tab" ""
                echo "새 탭 생성됨: Window 1, Tab $new_tab"
            fi
            ;;
        2)
            local new_tab
            new_tab=$(open_new_chatgpt_tab 1)
            sleep 2
            save_chatgpt_session "$proj_dir" 1 "$new_tab" ""
            echo "새 탭 생성됨: Window 1, Tab $new_tab"
            ;;
    esac

    echo ""
    echo "프로젝트 생성 완료!"
    echo "실행하려면: ./agent.sh run $project_name"
}

# ══════════════════════════════════════════════════════════════
# 프로젝트 선택 및 실행
# ══════════════════════════════════════════════════════════════

interactive_select_project() {
    list_projects
    echo ""
    echo "프로젝트 번호 선택:"
    read -r num

    local proj_dir
    proj_dir=$(select_project_by_number "$num")

    if [[ -z "$proj_dir" ]]; then
        echo "오류: 잘못된 선택입니다."
        return 1
    fi

    PROJECT_DIR="$proj_dir"
    run_project
}

run_project() {
    if [[ -z "$PROJECT_DIR" ]]; then
        echo "오류: 프로젝트가 선택되지 않았습니다."
        return 1
    fi

    # 상태 파일 설정
    STATE_FILE="${PROJECT_DIR}/state.json"
    OUTPUT_DIR="$PROJECT_DIR"

    # 템플릿 확인
    TEMPLATE=$(state_get ".template")

    if [[ -z "$TEMPLATE" ]]; then
        echo "오류: 템플릿 정보가 없습니다."
        return 1
    fi

    local workflow_file="${TEMPLATES_DIR}/${TEMPLATE}/workflow.sh"

    if [[ ! -f "$workflow_file" ]]; then
        echo "오류: 워크플로우 파일을 찾을 수 없습니다 - $workflow_file"
        return 1
    fi

    # ChatGPT 세션 복원
    local session
    session=$(load_chatgpt_session "$PROJECT_DIR")
    local win tab title
    win=$(echo "$session" | cut -d: -f1)
    tab=$(echo "$session" | cut -d: -f2)
    title=$(echo "$session" | cut -d: -f3-)

    if [[ "$win" == "0" || "$tab" == "0" ]]; then
        echo ""
        echo "ChatGPT 탭이 설정되지 않았습니다."
        echo "제목으로 검색할 대화 제목 입력 (없으면 Enter):"
        read -r search_title

        if [[ -n "$search_title" ]]; then
            local found
            found=$(find_chatgpt_tab_by_title "$search_title")
            if [[ -n "$found" ]]; then
                win=$(echo "$found" | cut -d: -f1)
                tab=$(echo "$found" | cut -d: -f2)
                save_chatgpt_session "$PROJECT_DIR" "$win" "$tab" "$search_title"
            fi
        fi

        if [[ "$win" == "0" || "$tab" == "0" ]]; then
            echo "새 ChatGPT 탭을 생성합니다..."
            tab=$(open_new_chatgpt_tab 1)
            win=1
            sleep 2
            save_chatgpt_session "$PROJECT_DIR" "$win" "$tab" ""
        fi
    fi

    echo ""
    echo "프로젝트: $(basename "$PROJECT_DIR")"
    echo "템플릿: $TEMPLATE"
    echo "ChatGPT: Window $win, Tab $tab"

    # 워크플로우 로드 및 실행
    source "$workflow_file"

    echo ""
    echo "워크플로우를 시작합니다..."
    echo "  1. 처음부터 시작"
    echo "  2. 특정 섹션부터 재개"
    echo "  3. 현재 상태 확인만"
    read -r choice

    case "$choice" in
        1)
            run_workflow
            ;;
        2)
            echo "섹션 ID 입력 (예: s1_1, s2_2):"
            read -r section_id
            resume_from_section "$section_id"
            ;;
        3)
            echo ""
            echo "현재 상태:"
            cat "$STATE_FILE" | python3 -m json.tool 2>/dev/null || cat "$STATE_FILE"
            ;;
    esac
}

# ══════════════════════════════════════════════════════════════
# 메인 인터페이스
# ══════════════════════════════════════════════════════════════

interactive_mode() {
    print_header

    while true; do
        print_menu
        echo ""
        echo "선택:"
        read -r choice

        case "$choice" in
            1)
                list_projects
                ;;
            2)
                interactive_select_project
                ;;
            3)
                interactive_create_project
                ;;
            4)
                echo ""
                echo "━━━ ChatGPT 탭 목록 ━━━"
                list_chatgpt_tabs
                ;;
            5)
                list_templates
                ;;
            q|Q)
                echo "종료합니다."
                exit 0
                ;;
            *)
                echo "잘못된 선택입니다."
                ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
# CLI 명령어 처리
# ══════════════════════════════════════════════════════════════

show_help() {
    echo "사용법: $0 [명령어] [옵션]"
    echo ""
    echo "명령어:"
    echo "  (없음)              대화형 모드"
    echo "  list                프로젝트 목록"
    echo "  create NAME TMPL    새 프로젝트 생성"
    echo "  run NAME            프로젝트 실행"
    echo "  tabs                ChatGPT 탭 목록"
    echo "  templates           템플릿 목록"
    echo "  help                도움말"
    echo ""
    echo "예시:"
    echo "  $0                           # 대화형 모드"
    echo "  $0 create my_plan bizplan    # bizplan 템플릿으로 프로젝트 생성"
    echo "  $0 run my_plan               # 프로젝트 실행"
}

# 디렉토리 초기화
ensure_projects_dir

# 명령어 처리
case "${1:-}" in
    "")
        interactive_mode
        ;;
    list)
        list_projects
        ;;
    create)
        if [[ -z "${2:-}" || -z "${3:-}" ]]; then
            echo "사용법: $0 create <프로젝트명> <템플릿명> [주제]"
            exit 1
        fi
        create_project "$2" "$3" "${4:-}"
        ;;
    run)
        if [[ -z "${2:-}" ]]; then
            echo "사용법: $0 run <프로젝트명>"
            exit 1
        fi
        PROJECT_DIR="${PROJECTS_DIR}/${2}"
        if [[ ! -d "$PROJECT_DIR" ]]; then
            echo "오류: 프로젝트를 찾을 수 없습니다 - $2"
            exit 1
        fi
        run_project
        ;;
    tabs)
        echo "━━━ ChatGPT 탭 목록 ━━━"
        list_chatgpt_tabs
        ;;
    templates)
        list_templates
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "알 수 없는 명령어: $1"
        show_help
        exit 1
        ;;
esac
