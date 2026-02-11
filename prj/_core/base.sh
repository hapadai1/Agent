#!/bin/bash
# prj/_core/base.sh - 모든 프로젝트가 공유하는 기본 설정 및 함수

# ══════════════════════════════════════════════════════════════
# 경로 설정 (자동 계산)
# ══════════════════════════════════════════════════════════════
CORE_DIR="${CORE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export CORE_LIB_DIR="${CORE_DIR}/lib"
export CORE_SCRIPTS_DIR="${CORE_DIR}/scripts"
export CORE_PROMPTS_DIR="${CORE_DIR}/prompts"

# PROJECT_DIR, PROJECT_NAME은 호출하는 run.sh에서 설정
# (source하는 쪽에서 export PROJECT_DIR, PROJECT_NAME을 미리 설정해야 함)

# Agent 루트 디렉토리 (prj의 부모)
export AGENT_ROOT="$(cd "$(dirname "$(dirname "$CORE_DIR")")" && pwd)"
export COMMON_DIR="${AGENT_ROOT}/common"

# ══════════════════════════════════════════════════════════════
# 프로젝트 경로 설정 (정의 영역 - 정적)
# ══════════════════════════════════════════════════════════════
# PROJECT_DIR이 set되었다고 가정
if [[ -n "$PROJECT_DIR" ]]; then
    export CONFIG_DIR="${PROJECT_DIR}/config"
    export DATA_DIR="${PROJECT_DIR}/data"
    export SAMPLES_DIR="${DATA_DIR}/samples"
    export RESEARCH_DIR="${DATA_DIR}/research"
    export PROMPTS_DIR="${PROJECT_DIR}/prompts"

    # ══════════════════════════════════════════════════════════════
    # 경로 설정 (런타임 영역 - 동적)
    # ══════════════════════════════════════════════════════════════
    export RUNTIME_DIR="${PROJECT_DIR}/runtime"
    export STATE_DIR="${RUNTIME_DIR}/state"
    export RUNS_DIR="${RUNTIME_DIR}/runs"
    export LOGS_DIR="${RUNTIME_DIR}/logs"

    # 하위 호환성
    export SUITES_DIR="${SAMPLES_DIR}"
fi

# ══════════════════════════════════════════════════════════════
# 로깅 설정
# ══════════════════════════════════════════════════════════════
export LOG_LEVEL="${LOG_LEVEL:-INFO}"
export LOG_FILE="${LOG_FILE:-}"

# ══════════════════════════════════════════════════════════════
# 공통 로깅 함수
# ══════════════════════════════════════════════════════════════
log_info() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️  $msg"
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $msg" >> "$LOG_FILE"
}

log_success() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $msg"
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $msg" >> "$LOG_FILE"
}

log_warn() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $msg" >&2
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $msg" >> "$LOG_FILE"
}

log_error() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $msg" >&2
    [[ -n "$LOG_FILE" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $msg" >> "$LOG_FILE"
}

# ══════════════════════════════════════════════════════════════
# 공통 유틸 함수
# ══════════════════════════════════════════════════════════════

# 런타임 디렉토리 초기화
setup_runtime_dirs() {
    local project_dir="$1"
    [[ -z "$project_dir" ]] && project_dir="$PROJECT_DIR"

    mkdir -p "$project_dir/runtime/logs"
    mkdir -p "$project_dir/runtime/runs"
    mkdir -p "$project_dir/runtime/state"

    log_info "Runtime directories initialized: $project_dir/runtime"
}

# 코어 라이브러리 로드
load_core_lib() {
    local module="$1"
    local script="${CORE_LIB_DIR}/core/${module}.sh"

    if [[ ! -f "$script" ]]; then
        script="${CORE_LIB_DIR}/util/${module}.sh"
    fi

    if [[ -f "$script" ]]; then
        source "$script"
        return 0
    else
        log_error "Core library not found: $module"
        return 1
    fi
}

# ChatGPT 스크립트 로드
load_chatgpt() {
    local chatgpt_script="${COMMON_DIR}/chatgpt.sh"
    if [[ -f "$chatgpt_script" ]]; then
        source "$chatgpt_script"
        return 0
    else
        log_error "chatgpt.sh not found at $chatgpt_script"
        return 1
    fi
}

# 프로젝트 초기화
init_project() {
    [[ -z "$PROJECT_DIR" ]] && {
        log_error "PROJECT_DIR not set"
        return 1
    }
    [[ -z "$PROJECT_NAME" ]] && {
        log_error "PROJECT_NAME not set"
        return 1
    }

    # 경로 확인
    [[ ! -d "$CONFIG_DIR" ]] && {
        log_error "CONFIG_DIR not found: $CONFIG_DIR"
        return 1
    }

    # 런타임 디렉토리 생성
    setup_runtime_dirs "$PROJECT_DIR"

    log_success "Project initialized: $PROJECT_NAME ($PROJECT_DIR)"
    return 0
}

# ══════════════════════════════════════════════════════════════
# 프로젝트 설정 파일 로드 헬퍼
# ══════════════════════════════════════════════════════════════
load_project_settings() {
    local settings_file="${CONFIG_DIR}/settings.sh"
    if [[ -f "$settings_file" ]]; then
        source "$settings_file"
        return 0
    else
        log_warn "Project settings not found: $settings_file"
        return 0
    fi
}

# ══════════════════════════════════════════════════════════════
# 디버그 정보 출력
# ══════════════════════════════════════════════════════════════
debug_info() {
    cat <<EOF
=== Project Debug Info ===
PROJECT_NAME: $PROJECT_NAME
PROJECT_DIR: $PROJECT_DIR
CONFIG_DIR: $CONFIG_DIR
DATA_DIR: $DATA_DIR
PROMPTS_DIR: $PROMPTS_DIR
RUNTIME_DIR: $RUNTIME_DIR
CORE_DIR: $CORE_DIR
AGENT_ROOT: $AGENT_ROOT
========================
EOF
}

export -f log_info log_success log_warn log_error
export -f setup_runtime_dirs load_core_lib load_chatgpt init_project load_project_settings debug_info
