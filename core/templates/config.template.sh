#!/bin/bash
# config.sh - 프로젝트 설정
# 생성일: {DATE}
# 프로젝트: {PROJECT_NAME}

# ══════════════════════════════════════════════════════════════
# 프로젝트 정보
# ══════════════════════════════════════════════════════════════
export PROJECT_NAME="{PROJECT_NAME}"
export PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AGENT_DIR="$(dirname "$(dirname "$PROJECT_DIR")")"
export COMMON_DIR="${AGENT_DIR}/common"
export CORE_DIR="${AGENT_DIR}/core"

# ══════════════════════════════════════════════════════════════
# ChatGPT 탭 구성
# ══════════════════════════════════════════════════════════════
# flow.yaml의 tabs 섹션과 일치해야 함
export CHATGPT_WINDOW="${CHATGPT_WINDOW:-1}"

export TAB_RESEARCH="${TAB_RESEARCH:-1}"
export TAB_WRITER="${TAB_WRITER:-2}"
export TAB_EVALUATOR="${TAB_EVALUATOR:-3}"
export TAB_CRITIC="${TAB_CRITIC:-4}"

# ══════════════════════════════════════════════════════════════
# 타임아웃 설정 (초)
# ══════════════════════════════════════════════════════════════
export TIMEOUT_RESEARCH="${TIMEOUT_RESEARCH:-300}"
export TIMEOUT_WRITER="${TIMEOUT_WRITER:-180}"
export TIMEOUT_EVALUATOR="${TIMEOUT_EVALUATOR:-120}"
export TIMEOUT_CRITIC="${TIMEOUT_CRITIC:-90}"

# ══════════════════════════════════════════════════════════════
# 프로젝트 URL (ChatGPT 프로젝트 내 새 채팅용)
# ══════════════════════════════════════════════════════════════
export PROJECT_URL="${PROJECT_URL:-}"

# ══════════════════════════════════════════════════════════════
# 경로 설정
# ══════════════════════════════════════════════════════════════
export PROMPTS_DIR="${PROJECT_DIR}/prompts"
export OUTPUTS_DIR="${PROJECT_DIR}/outputs"
export RESEARCH_DIR="${PROJECT_DIR}/research"

# ══════════════════════════════════════════════════════════════
# 로깅 설정
# ══════════════════════════════════════════════════════════════
export LOG_LEVEL="${LOG_LEVEL:-info}"

# ══════════════════════════════════════════════════════════════
# 공용 모듈 로드
# ══════════════════════════════════════════════════════════════
load_core() {
    # ChatGPT 스크립트
    if [[ -f "${COMMON_DIR}/chatgpt.sh" ]]; then
        source "${COMMON_DIR}/chatgpt.sh"
    fi

    # Flow Runner
    if [[ -f "${CORE_DIR}/flow_runner.sh" ]]; then
        source "${CORE_DIR}/flow_runner.sh"
    fi

    # Prompt Engine
    if [[ -f "${CORE_DIR}/prompt_engine.sh" ]]; then
        source "${CORE_DIR}/prompt_engine.sh"
    fi
}

# ══════════════════════════════════════════════════════════════
# 로깅 함수
# ══════════════════════════════════════════════════════════════
_log() {
    local level="$1"
    local msg="$2"
    local timestamp
    timestamp=$(date '+%H:%M:%S')

    case "$LOG_LEVEL" in
        debug) ;;
        info) [[ "$level" == "DEBUG" ]] && return ;;
        warn) [[ "$level" == "DEBUG" || "$level" == "INFO" ]] && return ;;
        error) [[ "$level" != "ERROR" ]] && return ;;
    esac

    echo "[$timestamp] [$level] $msg" >&2
}

log_debug() { _log "DEBUG" "$1"; }
log_info()  { _log "INFO" "$1"; }
log_warn()  { _log "WARN" "$1"; }
log_error() { _log "ERROR" "$1"; }
