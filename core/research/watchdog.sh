#!/bin/bash
# research/watchdog.sh - 리서치 폴더 감시 스크립트
#
# 사용법:
#   ./watchdog.sh <project_dir>           # 1분마다 폴더 감시
#   ./watchdog.sh <project_dir> --once    # 한 번만 체크
#
# 기능:
#   - /research/prompts/ 폴더 감시
#   - 새 파일 감지 시 runner.sh run 실행
#   - 완료된 리서치는 /research/responses/에 저장됨

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INTERVAL=60  # 1분마다 체크

# ══════════════════════════════════════════════════════════════
# 로깅
# ══════════════════════════════════════════════════════════════
log() {
    local timestamp
    timestamp=$(date '+%H:%M:%S')
    echo "[$timestamp] [WATCHDOG] $1" >&2
}

# ══════════════════════════════════════════════════════════════
# 대기 중인 리서치 확인
# ══════════════════════════════════════════════════════════════
check_pending() {
    local project_dir="$1"
    local prompts_dir="${project_dir}/research/prompts"
    local responses_dir="${project_dir}/research/responses"

    [[ ! -d "$prompts_dir" ]] && return 1

    local pending_count=0

    for f in "$prompts_dir"/*.md; do
        [[ ! -f "$f" ]] && continue
        local name=$(basename "$f" .md)

        # 응답이 이미 있으면 스킵
        [[ -f "${responses_dir}/${name}.md" ]] && continue
        [[ -f "${responses_dir}/${name}.pdf" ]] && continue

        pending_count=$((pending_count + 1))
    done

    echo "$pending_count"
}

# ══════════════════════════════════════════════════════════════
# 리서치 처리
# ══════════════════════════════════════════════════════════════
process_research() {
    local project_dir="$1"

    local pending
    pending=$(check_pending "$project_dir")

    if [[ "$pending" -gt 0 ]]; then
        log "📋 대기 중인 리서치: ${pending}개"
        log "🚀 runner.sh run 실행..."

        # runner.sh run 실행 (1개 처리)
        "${SCRIPT_DIR}/runner.sh" run "$project_dir"

        return 0
    fi

    return 1
}

# ══════════════════════════════════════════════════════════════
# 메인
# ══════════════════════════════════════════════════════════════
main() {
    local project_dir="${1:-.}"
    local mode="${2:-loop}"

    # 절대 경로로 변환
    project_dir="$(cd "$project_dir" 2>/dev/null && pwd)" || {
        echo "ERROR: Invalid project directory: $1" >&2
        exit 1
    }

    log "━━━ Research Watchdog 시작 ━━━"
    log "Project: $project_dir"
    log "Prompts: ${project_dir}/research/prompts/"
    log "Responses: ${project_dir}/research/responses/"

    if [[ "$mode" == "--once" ]]; then
        # 한 번만 체크
        process_research "$project_dir"
        exit $?
    fi

    # 무한 루프 모드
    log "감시 시작 (${INTERVAL}초 간격)"
    echo ""

    while true; do
        if process_research "$project_dir"; then
            log "✅ 리서치 처리 완료"
        else
            log "⏳ 대기 중인 리서치 없음"
        fi

        sleep "$INTERVAL"
    done
}

# 스크립트 실행
main "$@"
