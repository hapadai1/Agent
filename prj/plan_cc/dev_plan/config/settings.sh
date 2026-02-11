#!/bin/bash
# settings.sh - dev_plan 프로젝트 설정
# 모든 스크립트에서 source 하여 사용

# ══════════════════════════════════════════════════════════════
# 프로젝트 정보
# ══════════════════════════════════════════════════════════════
export PROJECT_NAME="dev_plan"
# config/ 폴더의 부모가 PROJECT_DIR
export PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# Agent 루트 디렉토리 (projects/의 부모)
export AGENT_ROOT="$(dirname "$(dirname "$PROJECT_DIR")")"
# 공통 모듈 경로
export COMMON_DIR="${AGENT_ROOT}/common"
export LIB_CORE_DIR="${AGENT_ROOT}/lib/core"

# ══════════════════════════════════════════════════════════════
# ChatGPT 설정
# ══════════════════════════════════════════════════════════════
export CHATGPT_BROWSER="${CHATGPT_BROWSER:-Google Chrome Canary}"
export CHATGPT_TAB_ACTIVATE="${CHATGPT_TAB_ACTIVATE:-false}"

export CHATGPT_WINDOW="${CHATGPT_WINDOW:-1}"
export CHATGPT_TAB="${CHATGPT_TAB:-1}"
export CHATGPT_PROJECT_URL="${CHATGPT_PROJECT_URL:-https://chatgpt.com/g/g-p-698a6e2b4fc081918dacfa8d23267212-plan/}"
export CHATGPT_NEW_CHAT="${CHATGPT_NEW_CHAT:-true}"

# ══════════════════════════════════════════════════════════════
# 설계 Phase 설정
# ══════════════════════════════════════════════════════════════
export MAX_DESIGN_VERSIONS="${MAX_DESIGN_VERSIONS:-3}"
export TARGET_DESIGN_SCORE="${TARGET_DESIGN_SCORE:-85}"
export TIMEOUT_DESIGN_WRITER="${TIMEOUT_DESIGN_WRITER:-1500}"     # GPT 설계 작성 (25분)
export TIMEOUT_DESIGN_EVALUATOR="${TIMEOUT_DESIGN_EVALUATOR:-1500}" # Claude 설계 평가 (25분)

# ══════════════════════════════════════════════════════════════
# 개발 Phase 설정
# ══════════════════════════════════════════════════════════════
export MAX_DEV_VERSIONS="${MAX_DEV_VERSIONS:-5}"
export TIMEOUT_DEVELOPER="${TIMEOUT_DEVELOPER:-1500}"   # Claude 코드 작성 (25분)
export TIMEOUT_DEV_EVALUATOR="${TIMEOUT_DEV_EVALUATOR:-1500}" # GPT 테스트 평가 (25분)

# ══════════════════════════════════════════════════════════════
# 경로 설정 (정의 영역 - 정적)
# ══════════════════════════════════════════════════════════════
export CONFIG_DIR="${PROJECT_DIR}/config"
export DATA_DIR="${PROJECT_DIR}/data"
export PROMPTS_DIR="${PROJECT_DIR}/prompts"
export SCRIPTS_DIR="${PROJECT_DIR}/scripts"

# ══════════════════════════════════════════════════════════════
# 경로 설정 (런타임 영역 - 동적)
# ══════════════════════════════════════════════════════════════
export RUNTIME_DIR="${PROJECT_DIR}/runtime"
export STATE_DIR="${RUNTIME_DIR}/state"
export RUNS_DIR="${RUNTIME_DIR}/runs"
export LOGS_DIR="${RUNTIME_DIR}/logs"

# ══════════════════════════════════════════════════════════════
# 로깅 설정
# ══════════════════════════════════════════════════════════════
export LOG_LEVEL="${LOG_LEVEL:-INFO}"

# ══════════════════════════════════════════════════════════════
# 공통 모듈 로드
# ══════════════════════════════════════════════════════════════
LOGGER_SCRIPT="${PROJECT_DIR}/lib/util/logger.sh"
if [[ -f "$LOGGER_SCRIPT" ]]; then
    source "$LOGGER_SCRIPT"
fi

# ══════════════════════════════════════════════════════════════
# ChatGPT 스크립트 로드
# ══════════════════════════════════════════════════════════════
load_chatgpt() {
    CHATGPT_SCRIPT="${COMMON_DIR}/chatgpt.sh"
    if [[ -f "$CHATGPT_SCRIPT" ]]; then
        source "$CHATGPT_SCRIPT"
        return 0
    else
        echo "ERROR: chatgpt.sh not found at $CHATGPT_SCRIPT" >&2
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════
# Claude 스크립트 로드
# ══════════════════════════════════════════════════════════════
load_claude() {
    CLAUDE_SCRIPT="${COMMON_DIR}/claude.sh"
    if [[ -f "$CLAUDE_SCRIPT" ]]; then
        source "$CLAUDE_SCRIPT"
        return 0
    else
        echo "ERROR: claude.sh not found at $CLAUDE_SCRIPT" >&2
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════
# 공통 코어 라이브러리 로드
# ══════════════════════════════════════════════════════════════
load_core() {
    local module="$1"
    local script="${LIB_CORE_DIR}/${module}.sh"
    if [[ -f "$script" ]]; then
        source "$script"
        return 0
    else
        echo "ERROR: core module not found: $script" >&2
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════
# 헬퍼 함수
# ══════════════════════════════════════════════════════════════
get_timeout_for() {
    local role="$1"
    case "$role" in
        design_writer) echo "$TIMEOUT_DESIGN_WRITER" ;;
        design_evaluator) echo "$TIMEOUT_DESIGN_EVALUATOR" ;;
        developer) echo "$TIMEOUT_DEVELOPER" ;;
        dev_evaluator) echo "$TIMEOUT_DEV_EVALUATOR" ;;
        *) echo "90" ;;
    esac
}
