#!/bin/bash
# context.sh - 실행 컨텍스트 관리
# 프로젝트 경로, 작업 디렉토리, 출력 디렉토리 규칙 정의

RUNTIME_CONTEXT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(dirname "$RUNTIME_CONTEXT_DIR")"
AGENT_ROOT="$(dirname "$CORE_DIR")"

# ══════════════════════════════════════════════════════════════
# 전역 경로 변수
# ══════════════════════════════════════════════════════════════

# Agent 루트 디렉토리
export AGENT_ROOT="${AGENT_ROOT}"

# 프로젝트 디렉토리 (context_init에서 설정)
export PROJECT_DIR="${PROJECT_DIR:-}"
export PROJECT_NAME="${PROJECT_NAME:-}"

# 작업 디렉토리
export WORK_DIR="${WORK_DIR:-}"
export OUTPUT_DIR="${OUTPUT_DIR:-}"
export LOGS_DIR="${LOGS_DIR:-}"
export CACHE_DIR="${CACHE_DIR:-}"

# 실행 ID
export RUN_ID="${RUN_ID:-}"
export CURRENT_STEP="${CURRENT_STEP:-}"

# ══════════════════════════════════════════════════════════════
# 컨텍스트 초기화
# ══════════════════════════════════════════════════════════════

# 프로젝트 컨텍스트 초기화
# 사용법: context_init <project_name> [options]
#
# 옵션:
#   --run-id=ID     실행 ID 지정 (기본: 타임스탬프)
#   --output=PATH   출력 디렉토리 오버라이드
#   --work=PATH     작업 디렉토리 오버라이드
#
# 예시:
#   context_init ai_court_auction
#   context_init my_project --run-id=test-001
context_init() {
    local project_name="$1"
    shift

    if [[ -z "$project_name" ]]; then
        echo "ERROR: Project name required" >&2
        echo "Usage: context_init <project_name>" >&2
        return 1
    fi

    # 옵션 파싱
    local custom_run_id=""
    local custom_output=""
    local custom_work=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --run-id=*)
                custom_run_id="${1#--run-id=}"
                shift
                ;;
            --output=*)
                custom_output="${1#--output=}"
                shift
                ;;
            --work=*)
                custom_work="${1#--work=}"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # 프로젝트 디렉토리 찾기
    local project_dir
    project_dir=$(_context_find_project "$project_name")

    if [[ -z "$project_dir" || ! -d "$project_dir" ]]; then
        echo "ERROR: Project not found: $project_name" >&2
        echo "Searched in: ${AGENT_ROOT}/projects/" >&2
        return 1
    fi

    # 전역 변수 설정
    export PROJECT_NAME="$project_name"
    export PROJECT_DIR="$project_dir"

    # 실행 ID 생성
    if [[ -n "$custom_run_id" ]]; then
        export RUN_ID="$custom_run_id"
    else
        export RUN_ID="$(date +%Y%m%d_%H%M%S)"
    fi

    # 디렉토리 경로 설정
    if [[ -n "$custom_work" ]]; then
        export WORK_DIR="$custom_work"
    else
        export WORK_DIR="${PROJECT_DIR}/runs/${RUN_ID}"
    fi

    if [[ -n "$custom_output" ]]; then
        export OUTPUT_DIR="$custom_output"
    else
        export OUTPUT_DIR="${WORK_DIR}/outputs"
    fi

    export LOGS_DIR="${WORK_DIR}/logs"
    export CACHE_DIR="${PROJECT_DIR}/.cache"

    # 디렉토리 생성
    mkdir -p "$WORK_DIR" "$OUTPUT_DIR" "$LOGS_DIR" "$CACHE_DIR" 2>/dev/null

    # 컨텍스트 정보 저장
    _context_save

    echo "Context initialized:" >&2
    echo "  Project:  $PROJECT_NAME" >&2
    echo "  Run ID:   $RUN_ID" >&2
    echo "  Work Dir: $WORK_DIR" >&2

    return 0
}

# 프로젝트 디렉토리 찾기
_context_find_project() {
    local project_name="$1"

    # 1. 직접 경로 체크
    if [[ -d "$project_name" ]]; then
        echo "$(cd "$project_name" && pwd)"
        return
    fi

    # 2. projects/ 하위에서 찾기
    local project_path="${AGENT_ROOT}/projects/${project_name}"
    if [[ -d "$project_path" ]]; then
        echo "$project_path"
        return
    fi

    # 3. 현재 디렉토리가 프로젝트인지 체크
    if [[ -f "./flow.yaml" || -f "./config.yaml" ]]; then
        pwd
        return
    fi

    return 1
}

# 컨텍스트 정보 저장
_context_save() {
    local context_file="${WORK_DIR}/.context.json"

    python3 -c "
import json
from datetime import datetime

context = {
    'project_name': '$PROJECT_NAME',
    'project_dir': '$PROJECT_DIR',
    'run_id': '$RUN_ID',
    'work_dir': '$WORK_DIR',
    'output_dir': '$OUTPUT_DIR',
    'logs_dir': '$LOGS_DIR',
    'started_at': datetime.now().isoformat(),
    'agent_root': '$AGENT_ROOT'
}

with open('$context_file', 'w') as f:
    json.dump(context, f, indent=2, ensure_ascii=False)
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 컨텍스트 조회
# ══════════════════════════════════════════════════════════════

# 현재 컨텍스트 출력
context_info() {
    echo "Current Context"
    echo "═══════════════════════════════════════════"
    echo ""
    echo "Project:    ${PROJECT_NAME:-<not set>}"
    echo "Project Dir: ${PROJECT_DIR:-<not set>}"
    echo "Run ID:     ${RUN_ID:-<not set>}"
    echo ""
    echo "Directories:"
    echo "  Work:   ${WORK_DIR:-<not set>}"
    echo "  Output: ${OUTPUT_DIR:-<not set>}"
    echo "  Logs:   ${LOGS_DIR:-<not set>}"
    echo "  Cache:  ${CACHE_DIR:-<not set>}"
    echo ""
    echo "Agent Root: ${AGENT_ROOT}"
}

# 컨텍스트 검증
context_check() {
    local errors=0

    if [[ -z "$PROJECT_DIR" ]]; then
        echo "ERROR: PROJECT_DIR not set" >&2
        ((errors++))
    elif [[ ! -d "$PROJECT_DIR" ]]; then
        echo "ERROR: PROJECT_DIR does not exist: $PROJECT_DIR" >&2
        ((errors++))
    fi

    if [[ -z "$RUN_ID" ]]; then
        echo "WARNING: RUN_ID not set" >&2
    fi

    if [[ $errors -gt 0 ]]; then
        echo "" >&2
        echo "Run 'context_init <project>' to initialize context" >&2
        return 1
    fi

    echo "Context OK" >&2
    return 0
}

# 컨텍스트 필요 함수 데코레이터
context_require() {
    if [[ -z "$PROJECT_DIR" ]]; then
        echo "ERROR: Context not initialized" >&2
        echo "Run: context_init <project_name>" >&2
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════
# 경로 유틸리티
# ══════════════════════════════════════════════════════════════

# 프로젝트 상대 경로를 절대 경로로 변환
context_path() {
    local relative_path="$1"

    if [[ "$relative_path" == /* ]]; then
        echo "$relative_path"
    else
        echo "${PROJECT_DIR}/${relative_path}"
    fi
}

# 출력 경로 생성
context_output_path() {
    local filename="$1"
    local subdir="${2:-}"

    if [[ -n "$subdir" ]]; then
        mkdir -p "${OUTPUT_DIR}/${subdir}" 2>/dev/null
        echo "${OUTPUT_DIR}/${subdir}/${filename}"
    else
        echo "${OUTPUT_DIR}/${filename}"
    fi
}

# 로그 경로 생성
context_log_path() {
    local filename="$1"
    echo "${LOGS_DIR}/${filename}"
}

# 캐시 경로 생성
context_cache_path() {
    local key="$1"
    echo "${CACHE_DIR}/${key}"
}

# ══════════════════════════════════════════════════════════════
# 프로젝트 목록
# ══════════════════════════════════════════════════════════════

# 사용 가능한 프로젝트 목록
context_list_projects() {
    local projects_dir="${AGENT_ROOT}/projects"

    echo "Available Projects:"
    echo ""

    if [[ -d "$projects_dir" ]]; then
        for dir in "$projects_dir"/*/; do
            if [[ -d "$dir" ]]; then
                local name=$(basename "$dir")
                local has_flow=""
                local has_config=""

                [[ -f "${dir}/flow.yaml" ]] && has_flow="flow"
                [[ -f "${dir}/config.yaml" ]] && has_config="config"

                printf "  %-25s [%s %s]\n" "$name" "$has_flow" "$has_config"
            fi
        done
    else
        echo "  No projects directory found"
    fi
}

# ══════════════════════════════════════════════════════════════
# 컨텍스트 정리
# ══════════════════════════════════════════════════════════════

# 컨텍스트 종료 (결과 저장)
context_finalize() {
    local status="${1:-completed}"

    if [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
        return
    fi

    local context_file="${WORK_DIR}/.context.json"

    python3 -c "
import json
from datetime import datetime

try:
    with open('$context_file', 'r') as f:
        context = json.load(f)
except:
    context = {}

context['status'] = '$status'
context['finished_at'] = datetime.now().isoformat()

with open('$context_file', 'w') as f:
    json.dump(context, f, indent=2, ensure_ascii=False)
" 2>/dev/null

    echo "Context finalized: $status" >&2
}

# 변수 초기화
context_clear() {
    unset PROJECT_DIR PROJECT_NAME
    unset WORK_DIR OUTPUT_DIR LOGS_DIR CACHE_DIR
    unset RUN_ID CURRENT_STEP
    echo "Context cleared" >&2
}

# 직접 실행 시
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Context Manager - 실행 컨텍스트 관리"
    echo ""
    echo "함수:"
    echo "  context_init <project>     컨텍스트 초기화"
    echo "  context_info               현재 컨텍스트 출력"
    echo "  context_check              컨텍스트 검증"
    echo "  context_list_projects      프로젝트 목록"
    echo "  context_path <path>        절대 경로 변환"
    echo "  context_finalize [status]  컨텍스트 종료"
    echo "  context_clear              변수 초기화"
fi
