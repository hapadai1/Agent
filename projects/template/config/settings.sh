#!/bin/bash
# settings.sh - 프로젝트 설정
# 모든 스크립트에서 source 하여 사용

# ══════════════════════════════════════════════════════════════
# 프로젝트 정보
# ══════════════════════════════════════════════════════════════
export PROJECT_NAME="ai_court"
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
# 브라우저 설정 (Canary 사용 시 탭 전환 없이 백그라운드 실행 가능)
#   "Google Chrome"        - 기본 Chrome
#   "Google Chrome Canary" - Canary (권장: 메인 Chrome과 분리)
export CHATGPT_BROWSER="${CHATGPT_BROWSER:-Google Chrome Canary}"
export CHATGPT_TAB_ACTIVATE="${CHATGPT_TAB_ACTIVATE:-false}"  # Canary: false 권장

export CHATGPT_WINDOW="${CHATGPT_WINDOW:-1}"
export CHATGPT_TAB="${CHATGPT_TAB:-1}"
export CHATGPT_PROJECT_URL="${CHATGPT_PROJECT_URL:-https://chatgpt.com/g/g-p-69847ea187ec81919c424d62ee85ea25-plan}"
export CHATGPT_NEW_CHAT="${CHATGPT_NEW_CHAT:-true}"

# ══════════════════════════════════════════════════════════════
# 타임아웃 설정 (초)
# ══════════════════════════════════════════════════════════════
export TIMEOUT_WRITER="${TIMEOUT_WRITER:-1500}"      # 25분
export TIMEOUT_EVALUATOR="${TIMEOUT_EVALUATOR:-1500}" # 25분
export TIMEOUT_CRITIC="${TIMEOUT_CRITIC:-1500}"       # 25분

# ══════════════════════════════════════════════════════════════
# 재시도 설정
# ══════════════════════════════════════════════════════════════
export MAX_STEP_RETRIES="${MAX_STEP_RETRIES:-2}"

# ══════════════════════════════════════════════════════════════
# 버전 정책
# ══════════════════════════════════════════════════════════════
export MAX_VERSION="${MAX_VERSION:-5}"
export TARGET_SCORE="${TARGET_SCORE:-85}"

# ══════════════════════════════════════════════════════════════
# 실행 설정
# ══════════════════════════════════════════════════════════════
export DEFAULT_SUITE="${DEFAULT_SUITE:-suite-5}"
export DEFAULT_RUNS="${DEFAULT_RUNS:-5}"

# ══════════════════════════════════════════════════════════════
# 경로 설정 (정의 영역 - 정적)
# ══════════════════════════════════════════════════════════════
export CONFIG_DIR="${PROJECT_DIR}/config"
export DATA_DIR="${PROJECT_DIR}/data"
export SAMPLES_DIR="${DATA_DIR}/samples"
export RESEARCH_DIR="${DATA_DIR}/research"
export PROMPTS_DIR="${PROJECT_DIR}/prompts"
export SCRIPTS_DIR="${PROJECT_DIR}/scripts"

# ══════════════════════════════════════════════════════════════
# 경로 설정 (런타임 영역 - 동적)
# ══════════════════════════════════════════════════════════════
export RUNTIME_DIR="${PROJECT_DIR}/runtime"
export STATE_DIR="${RUNTIME_DIR}/state"
export RUNS_DIR="${RUNTIME_DIR}/runs"
export LOGS_DIR="${RUNTIME_DIR}/logs"

# 하위 호환성 (deprecated)
export SUITES_DIR="${SAMPLES_DIR}"

# ══════════════════════════════════════════════════════════════
# 로깅 설정
# ══════════════════════════════════════════════════════════════
export LOG_LEVEL="${LOG_LEVEL:-INFO}"

# ══════════════════════════════════════════════════════════════
# 공통 모듈 로드
# ══════════════════════════════════════════════════════════════
# 프로젝트 로컬 로거 (있으면)
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
        writer) echo "$TIMEOUT_WRITER" ;;
        evaluator) echo "$TIMEOUT_EVALUATOR" ;;
        critic) echo "$TIMEOUT_CRITIC" ;;
        *) echo "90" ;;
    esac
}
