#!/bin/bash
# config.sh - AI 법원 경매 프로젝트 설정
# 모든 스크립트에서 source 하여 사용

# ══════════════════════════════════════════════════════════════
# 프로젝트 정보
# ══════════════════════════════════════════════════════════════
export PROJECT_NAME="ai_court_auction"
export PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export COMMON_DIR="$(dirname "$(dirname "$PROJECT_DIR")")/common"

# ══════════════════════════════════════════════════════════════
# ChatGPT 탭 구성 (5-Tab 시스템)
# ══════════════════════════════════════════════════════════════
# Tab1: 리서치
# Tab2: Writer (Champion) - 고정 프롬프트
# Tab3: Writer (Challenger) - 개선 프롬프트
# Tab4: Evaluator (Frozen) - 평가 (매번 New Chat)
# Tab5: Prompt Critic + Builder

export CHATGPT_WINDOW="${CHATGPT_WINDOW:-1}"

# 탭 번호 (환경변수로 오버라이드 가능)
export TAB_RESEARCH="${TAB_RESEARCH:-1}"
export TAB_WRITER_CHAMPION="${TAB_WRITER_CHAMPION:-2}"
export TAB_WRITER_CHALLENGER="${TAB_WRITER_CHALLENGER:-3}"
export TAB_EVALUATOR="${TAB_EVALUATOR:-4}"
export TAB_CRITIC="${TAB_CRITIC:-5}"

# ══════════════════════════════════════════════════════════════
# 타임아웃 설정 (초)
# ══════════════════════════════════════════════════════════════
export TIMEOUT_WRITER="${TIMEOUT_WRITER:-180}"
export TIMEOUT_EVALUATOR="${TIMEOUT_EVALUATOR:-120}"
export TIMEOUT_CRITIC="${TIMEOUT_CRITIC:-90}"
export TIMEOUT_RESEARCH="${TIMEOUT_RESEARCH:-300}"

# ══════════════════════════════════════════════════════════════
# 프로젝트 URL (ChatGPT 프로젝트 내 새 채팅용)
# ══════════════════════════════════════════════════════════════
# plan 프로젝트 URL (Evaluator가 이 프로젝트 내에서 new chat 생성)
export PLAN_PROJECT_URL="${PLAN_PROJECT_URL:-https://chatgpt.com/g/g-p-69847ea187ec81919c424d62ee85ea25-plan}"
export EVALUATOR_PROJECT_URL="${EVALUATOR_PROJECT_URL:-$PLAN_PROJECT_URL}"
export WRITER_PROJECT_URL="${WRITER_PROJECT_URL:-$PLAN_PROJECT_URL}"

# ══════════════════════════════════════════════════════════════
# 실행 설정
# ══════════════════════════════════════════════════════════════
export EVALUATOR_NEW_CHAT="${EVALUATOR_NEW_CHAT:-true}"
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
export LOG_LEVEL="${LOG_LEVEL:-info}"  # debug, info, warn, error
export LOG_FILE="${LOG_FILE:-}"  # 비어있으면 stderr만 사용

# ══════════════════════════════════════════════════════════════
# ChatGPT 스크립트 로드
# ══════════════════════════════════════════════════════════════
load_chatgpt() {
    local CHATGPT_SCRIPT="${COMMON_DIR}/chatgpt.sh"
    if [[ -f "$CHATGPT_SCRIPT" ]]; then
        source "$CHATGPT_SCRIPT"
        return 0
    else
        echo "ERROR: chatgpt.sh not found at $CHATGPT_SCRIPT" >&2
        return 1
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

    # 레벨 필터링
    case "$LOG_LEVEL" in
        debug) ;;
        info) [[ "$level" == "DEBUG" ]] && return ;;
        warn) [[ "$level" == "DEBUG" || "$level" == "INFO" ]] && return ;;
        error) [[ "$level" != "ERROR" ]] && return ;;
    esac

    local output="[$timestamp] [$level] $msg"

    # stderr 출력
    echo "$output" >&2

    # 파일 출력 (설정된 경우)
    if [[ -n "$LOG_FILE" ]]; then
        echo "$output" >> "$LOG_FILE"
    fi
}

log_debug() { _log "DEBUG" "$1"; }
log_info()  { _log "INFO" "$1"; }
log_warn()  { _log "WARN" "$1"; }
log_error() { _log "ERROR" "$1"; }

# ══════════════════════════════════════════════════════════════
# 탭 헬퍼 함수
# ══════════════════════════════════════════════════════════════
get_writer_tab() {
    local writer="${1:-champion}"
    if [[ "$writer" == "champion" ]]; then
        echo "$TAB_WRITER_CHAMPION"
    else
        echo "$TAB_WRITER_CHALLENGER"
    fi
}

get_timeout_for() {
    local role="$1"
    case "$role" in
        writer) echo "$TIMEOUT_WRITER" ;;
        evaluator) echo "$TIMEOUT_EVALUATOR" ;;
        critic) echo "$TIMEOUT_CRITIC" ;;
        research) echo "$TIMEOUT_RESEARCH" ;;
        *) echo "90" ;;
    esac
}
