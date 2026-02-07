#!/bin/bash
# research/runner.sh - 리서치 실행 스크립트
#
# 사용법:
#   ./runner.sh status <project_dir>       # 현황 확인
#   ./runner.sh run <project_dir>          # 대기 중인 리서치 1개 처리
#   ./runner.sh run-all <project_dir>      # 전부 처리

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "${AGENT_ROOT}/common/chatgpt.sh" 2>/dev/null
source "${SCRIPT_DIR}/loader.sh" 2>/dev/null

RESEARCH_TAB=1
RESEARCH_WIN=1
DOWNLOAD_DIR="$HOME/Downloads"

# ══════════════════════════════════════════════════════════════
# 대기 중인 프롬프트 찾기
# ══════════════════════════════════════════════════════════════
find_pending() {
    local project_dir="$1"
    local prompts_dir="${project_dir}/research/prompts"
    local responses_dir="${project_dir}/research/responses"

    [[ ! -d "$prompts_dir" ]] && return

    for f in "$prompts_dir"/*.md; do
        [[ ! -f "$f" ]] && continue
        local name=$(basename "$f" .md)
        [[ -f "${responses_dir}/${name}.md" ]] && continue
        [[ -f "${responses_dir}/${name}.pdf" ]] && continue
        echo "$f"
    done
}

# ══════════════════════════════════════════════════════════════
# 리서치 완료 대기
# ══════════════════════════════════════════════════════════════
wait_complete() {
    local max_wait=1800  # 30분
    local elapsed=0

    echo "⏳ 리서치 완료 대기 중..." >&2

    while [[ $elapsed -lt $max_wait ]]; do
        sleep 60
        elapsed=$((elapsed + 60))

        local status
        status=$(osascript <<EOF
tell application "Google Chrome"
    set t to tab $RESEARCH_TAB of window $RESEARCH_WIN
    execute t javascript "(function(){
        if(document.querySelector('button[data-testid=\"stop-button\"]')) return 'STREAMING';
        if(document.querySelector('[data-testid=\"copy-turn-action-button\"]')) return 'COMPLETE';
        return 'UNKNOWN';
    })()"
end tell
EOF
        )

        echo "  ${elapsed}초 경과 - 상태: $status" >&2

        [[ "$status" == "COMPLETE" ]] && return 0
    done

    echo "⚠️ 타임아웃" >&2
    return 1
}

# ══════════════════════════════════════════════════════════════
# 마크다운 내보내기
# ══════════════════════════════════════════════════════════════
export_markdown() {
    echo "📥 마크다운 내보내기..." >&2

    # 다운로드 버튼 클릭
    osascript <<EOF >/dev/null 2>&1
tell application "Google Chrome"
    set t to tab $RESEARCH_TAB of window $RESEARCH_WIN
    execute t javascript "(function(){
        var btn = document.querySelector('[aria-label*=\"다운로드\"]');
        if(!btn) btn = document.querySelector('[aria-label*=\"Download\"]');
        if(btn) btn.click();
    })()"
end tell
EOF

    sleep 2

    # 마크다운 선택
    osascript <<EOF >/dev/null 2>&1
tell application "Google Chrome"
    set t to tab $RESEARCH_TAB of window $RESEARCH_WIN
    execute t javascript "(function(){
        var items = document.querySelectorAll('[role=\"menuitem\"]');
        for(var i=0; i<items.length; i++) {
            if(items[i].innerText.includes('마크다운') || items[i].innerText.includes('Markdown')) {
                items[i].click();
                return;
            }
        }
    })()"
end tell
EOF

    sleep 3
}

# ══════════════════════════════════════════════════════════════
# 다운로드 파일 이동
# ══════════════════════════════════════════════════════════════
move_download() {
    local name="$1"
    local responses_dir="$2"

    local downloaded=$(find "$DOWNLOAD_DIR" -name "*.md" -type f -mmin -2 2>/dev/null | head -1)

    if [[ -n "$downloaded" ]]; then
        mkdir -p "$responses_dir"
        mv "$downloaded" "${responses_dir}/${name}.md"
        echo "✅ 저장: ${responses_dir}/${name}.md" >&2
        return 0
    fi

    echo "⚠️ 다운로드 파일 없음" >&2
    return 1
}

# ══════════════════════════════════════════════════════════════
# 단일 리서치 처리
# ══════════════════════════════════════════════════════════════
process_one() {
    local prompt_file="$1"
    local project_dir="$2"

    local name=$(basename "$prompt_file" .md)
    local responses_dir="${project_dir}/research/responses"

    echo "━━━ 리서치: $name ━━━" >&2

    # 1. 프롬프트 전송
    local content=$(cat "$prompt_file")
    _chatgpt_start_research "$content" "$RESEARCH_WIN" "$RESEARCH_TAB"

    # 2. 완료 대기
    wait_complete || return 1

    # 3. 마크다운 내보내기
    export_markdown

    # 4. 파일 이동
    move_download "$name" "$responses_dir"

    echo "━━━ 완료: $name ━━━" >&2
}

# ══════════════════════════════════════════════════════════════
# 명령어
# ══════════════════════════════════════════════════════════════
case "${1:-help}" in
    status)
        project_dir="${2:-.}"
        echo "━━━ 리서치 현황 ━━━"
        pending=$(find_pending "$project_dir")
        if [[ -n "$pending" ]]; then
            echo "대기 중:"
            echo "$pending" | while read f; do echo "  - $(basename "$f")"; done
        else
            echo "대기 중인 리서치 없음"
        fi
        ;;

    run)
        project_dir="${2:-.}"
        pending=$(find_pending "$project_dir" | head -1)
        if [[ -n "$pending" ]]; then
            process_one "$pending" "$project_dir"
        else
            echo "처리할 리서치 없음"
        fi
        ;;

    run-all)
        project_dir="${2:-.}"
        pending=$(find_pending "$project_dir")
        if [[ -z "$pending" ]]; then
            echo "처리할 리서치 없음"
            exit 0
        fi
        echo "$pending" | while read f; do
            [[ -n "$f" ]] && process_one "$f" "$project_dir"
        done
        ;;

    *)
        echo "사용법:"
        echo "  $0 status <project_dir>    현황 확인"
        echo "  $0 run <project_dir>       1개 처리"
        echo "  $0 run-all <project_dir>   전부 처리"
        ;;
esac
