#!/bin/bash
# project_manager.sh - 프로젝트 및 ChatGPT 세션 관리
# 여러 프로젝트와 ChatGPT 탭을 관리하는 공통 모듈

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
PROJECTS_DIR="${BASE_DIR}/projects"
TEMPLATES_DIR="${BASE_DIR}/templates"

# chatgpt.sh 로드
source "${SCRIPT_DIR}/chatgpt.sh"

# ══════════════════════════════════════════════════════════════
# ChatGPT 탭 관리 (제목 기반)
# ══════════════════════════════════════════════════════════════

# ChatGPT 탭을 제목으로 찾기
# 반환: "window_num:tab_num" 또는 빈 문자열
find_chatgpt_tab_by_title() {
    local search_title="$1"

    local result
    result=$(osascript <<EOF
tell application "Google Chrome"
    set output to ""
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

    echo "$result"
}

# 모든 ChatGPT 탭 목록 (구조화된 형식)
list_chatgpt_tabs() {
    osascript <<'EOF'
tell application "Google Chrome"
    set output to ""
    set winCount to count of windows
    repeat with i from 1 to winCount
        set tabCount to count of tabs of window i
        repeat with j from 1 to tabCount
            set t to tab j of window i
            if URL of t contains "chatgpt" then
                set output to output & i & ":" & j & "|" & title of t & linefeed
            end if
        end repeat
    end repeat
    return output
end tell
EOF
}

# 새 ChatGPT 대화 열기 (새 탭에서)
open_new_chatgpt_tab() {
    local win="${1:-1}"

    osascript <<EOF
tell application "Google Chrome"
    tell window $win
        set newTab to make new tab with properties {URL:"https://chatgpt.com/"}
        set tabIndex to index of newTab
        return tabIndex
    end tell
end tell
EOF
}

# 특정 ChatGPT 탭으로 포커스
focus_chatgpt_tab() {
    local win="$1"
    local tab="$2"

    osascript <<EOF
tell application "Google Chrome"
    set active tab index of window $win to $tab
    set index of window $win to 1
    activate
end tell
EOF
}

# ══════════════════════════════════════════════════════════════
# 프로젝트 관리
# ══════════════════════════════════════════════════════════════

# 프로젝트 목록 출력
list_projects() {
    echo ""
    echo "━━━ 프로젝트 목록 ━━━"

    local idx=1
    for proj_dir in "$PROJECTS_DIR"/*/; do
        if [[ -d "$proj_dir" ]]; then
            local proj_name=$(basename "$proj_dir")
            local state_file="${proj_dir}state.json"

            if [[ -f "$state_file" ]]; then
                local template=$(cat "$state_file" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('template','unknown'))" 2>/dev/null || echo "unknown")
                local status=$(cat "$state_file" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('global_state','unknown'))" 2>/dev/null || echo "unknown")
                local topic=$(cat "$state_file" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('topic','')[:40])" 2>/dev/null || echo "")

                printf "  %2d. %-20s [%s] %s - %s\n" "$idx" "$proj_name" "$template" "$status" "$topic"
            else
                printf "  %2d. %-20s [상태 없음]\n" "$idx" "$proj_name"
            fi
            ((idx++))
        fi
    done

    if [[ $idx -eq 1 ]]; then
        echo "  (프로젝트 없음)"
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━"
}

# 프로젝트 생성
# 사용법: create_project "프로젝트명" "템플릿명" "주제"
create_project() {
    local project_name="$1"
    local template="$2"
    local topic="$3"

    local proj_dir="${PROJECTS_DIR}/${project_name}"

    if [[ -d "$proj_dir" ]]; then
        echo "오류: 프로젝트 '${project_name}'이 이미 존재합니다."
        return 1
    fi

    # 템플릿 확인
    local template_dir="${TEMPLATES_DIR}/${template}"
    if [[ ! -d "$template_dir" ]]; then
        echo "오류: 템플릿 '${template}'을 찾을 수 없습니다."
        echo "사용 가능한 템플릿:"
        ls -1 "$TEMPLATES_DIR" 2>/dev/null | sed 's/^/  - /'
        return 1
    fi

    # 프로젝트 디렉토리 생성
    mkdir -p "${proj_dir}/drafts"
    mkdir -p "${proj_dir}/scores"
    mkdir -p "${proj_dir}/research"

    # 템플릿에서 초기 상태 복사
    if [[ -f "${template_dir}/init_state.json" ]]; then
        local init_state
        init_state=$(cat "${template_dir}/init_state.json")

        # 프로젝트 정보 주입
        echo "$init_state" | python3 -c "
import sys, json
from datetime import datetime
d = json.load(sys.stdin)
d['project_name'] = '$project_name'
d['template'] = '$template'
d['topic'] = '''$topic'''
d['created_at'] = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
d['updated_at'] = d['created_at']
print(json.dumps(d, ensure_ascii=False, indent=2))
" > "${proj_dir}/state.json"
    else
        # 기본 상태 생성
        cat > "${proj_dir}/state.json" <<INITEOF
{
  "project_name": "$project_name",
  "template": "$template",
  "topic": "$topic",
  "created_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "updated_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "global_state": "INIT",
  "chatgpt": {
    "window": 0,
    "tab": 0
  }
}
INITEOF
    fi

    echo "프로젝트 '${project_name}' 생성 완료 (템플릿: ${template})"
    echo "경로: ${proj_dir}"

    return 0
}

# 프로젝트 선택 (번호로)
# 반환: 프로젝트 디렉토리 경로
select_project_by_number() {
    local num="$1"

    local idx=1
    for proj_dir in "$PROJECTS_DIR"/*/; do
        if [[ -d "$proj_dir" ]]; then
            if [[ $idx -eq $num ]]; then
                echo "$proj_dir"
                return 0
            fi
            ((idx++))
        fi
    done

    return 1
}

# 프로젝트의 ChatGPT 탭 찾기 또는 생성
# 사용법: get_or_create_chatgpt_tab "프로젝트명" [기존탭제목]
# 반환: "window:tab"
get_or_create_chatgpt_tab() {
    local project_name="$1"
    local existing_title="$2"

    # 1. 기존 대화 제목으로 검색
    if [[ -n "$existing_title" ]]; then
        local found
        found=$(find_chatgpt_tab_by_title "$existing_title")
        if [[ -n "$found" ]]; then
            echo "$found"
            return 0
        fi
    fi

    # 2. 프로젝트명으로 검색
    local found
    found=$(find_chatgpt_tab_by_title "$project_name")
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi

    # 3. 새 탭 생성
    local new_tab
    new_tab=$(open_new_chatgpt_tab 1)
    sleep 2

    echo "1:${new_tab}"
    return 0
}

# ══════════════════════════════════════════════════════════════
# 세션 관리
# ══════════════════════════════════════════════════════════════

# 프로젝트 상태에 ChatGPT 탭 정보 저장
save_chatgpt_session() {
    local proj_dir="$1"
    local window="$2"
    local tab="$3"
    local title="${4:-}"

    local state_file="${proj_dir}/state.json"

    if [[ -f "$state_file" ]]; then
        python3 -c "
import sys, json
from datetime import datetime
with open('$state_file', 'r') as f:
    d = json.load(f)
d['chatgpt'] = d.get('chatgpt', {})
d['chatgpt']['window'] = $window
d['chatgpt']['tab'] = $tab
d['chatgpt']['title'] = '''$title'''
d['updated_at'] = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
with open('$state_file', 'w') as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
"
    fi
}

# 프로젝트 상태에서 ChatGPT 탭 정보 로드
load_chatgpt_session() {
    local proj_dir="$1"
    local state_file="${proj_dir}/state.json"

    if [[ -f "$state_file" ]]; then
        python3 -c "
import sys, json
with open('$state_file', 'r') as f:
    d = json.load(f)
chatgpt = d.get('chatgpt', {})
print(f\"{chatgpt.get('window', 0)}:{chatgpt.get('tab', 0)}:{chatgpt.get('title', '')}\")
"
    else
        echo "0:0:"
    fi
}

# ══════════════════════════════════════════════════════════════
# 유틸리티
# ══════════════════════════════════════════════════════════════

# 템플릿 목록
list_templates() {
    echo ""
    echo "━━━ 사용 가능한 템플릿 ━━━"

    for tmpl_dir in "$TEMPLATES_DIR"/*/; do
        if [[ -d "$tmpl_dir" ]]; then
            local tmpl_name=$(basename "$tmpl_dir")
            local desc_file="${tmpl_dir}/description.txt"

            if [[ -f "$desc_file" ]]; then
                local desc=$(head -1 "$desc_file")
                printf "  - %-15s : %s\n" "$tmpl_name" "$desc"
            else
                printf "  - %s\n" "$tmpl_name"
            fi
        fi
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 프로젝트 디렉토리 초기화 확인
ensure_projects_dir() {
    mkdir -p "$PROJECTS_DIR"
}

# 스크립트가 직접 실행된 경우 도움말
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "프로젝트 관리 모듈"
    echo ""
    echo "사용법: source project_manager.sh"
    echo ""
    echo "함수:"
    echo "  list_projects              - 프로젝트 목록"
    echo "  create_project NAME TMPL   - 새 프로젝트 생성"
    echo "  list_templates             - 템플릿 목록"
    echo "  list_chatgpt_tabs          - ChatGPT 탭 목록"
    echo "  find_chatgpt_tab_by_title  - 제목으로 탭 검색"
fi
