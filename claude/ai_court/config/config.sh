#!/bin/bash
# config.sh - PlanLLM 프로젝트 설정
# 모든 스크립트에서 source 하여 사용

# ══════════════════════════════════════════════════════════════
# 프로젝트 정보
# ══════════════════════════════════════════════════════════════
export PROJECT_NAME="planllm"
# config/ 폴더의 부모가 PROJECT_DIR (이미 정의되어 있으면 유지)
export PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export COMMON_DIR="$(dirname "$(dirname "$PROJECT_DIR")")/common"

# ══════════════════════════════════════════════════════════════
# ChatGPT 설정 (단순화)
# ══════════════════════════════════════════════════════════════
export CHATGPT_WINDOW="${CHATGPT_WINDOW:-1}"
export CHATGPT_TAB="${CHATGPT_TAB:-1}"
export CHATGPT_PROJECT_URL="${CHATGPT_PROJECT_URL:-https://chatgpt.com/g/g-p-69847ea187ec81919c424d62ee85ea25-plan}"
export CHATGPT_NEW_CHAT="${CHATGPT_NEW_CHAT:-true}"

# ══════════════════════════════════════════════════════════════
# 타임아웃 설정 (초)
# ══════════════════════════════════════════════════════════════
export TIMEOUT_WRITER="${TIMEOUT_WRITER:-1500}"      # 25분 (Deep Think 모드 대응)
export TIMEOUT_EVALUATOR="${TIMEOUT_EVALUATOR:-1500}" # 25분 (통일)
export TIMEOUT_CRITIC="${TIMEOUT_CRITIC:-1500}"       # 25분 (통일)

# ══════════════════════════════════════════════════════════════
# 재시도 설정
# ══════════════════════════════════════════════════════════════
export MAX_STEP_RETRIES="${MAX_STEP_RETRIES:-2}"     # 각 step 최대 재시도 횟수

# ══════════════════════════════════════════════════════════════
# 버전 정책
# ══════════════════════════════════════════════════════════════
export MAX_VERSION="${MAX_VERSION:-5}"               # 섹션당 최대 버전 (v5까지)
export TARGET_SCORE="${TARGET_SCORE:-85}"            # 목표 점수 (85점 이상 시 다음 섹션)

# ══════════════════════════════════════════════════════════════
# 실행 설정
# ══════════════════════════════════════════════════════════════
export DEFAULT_SUITE="${DEFAULT_SUITE:-suite-5}"
export DEFAULT_RUNS="${DEFAULT_RUNS:-5}"

# ══════════════════════════════════════════════════════════════
# 경로 설정
# ══════════════════════════════════════════════════════════════
export SUITES_DIR="${PROJECT_DIR}/suites"
export PROMPTS_DIR="${PROJECT_DIR}/prompts"
export RUNS_DIR="${PROJECT_DIR}/runs"

# ══════════════════════════════════════════════════════════════
# 로깅 설정
# ══════════════════════════════════════════════════════════════
export LOG_LEVEL="${LOG_LEVEL:-INFO}"  # DEBUG, INFO, WARN, ERROR

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
