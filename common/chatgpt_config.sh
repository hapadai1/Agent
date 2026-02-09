#!/bin/bash
# chatgpt_config.sh - ChatGPT 자동화 설정
# chatgpt.sh에서 source하여 사용

# ══════════════════════════════════════════════════════════════
# 브라우저 설정
# ══════════════════════════════════════════════════════════════
# 사용 가능한 값:
#   "Google Chrome"        - 기본 Chrome (기존 동작)
#   "Google Chrome Canary" - Canary (별도 브라우저로 분리)
#   "Chromium"             - Chromium
#
# Canary 사용 시 장점:
#   - 메인 Chrome과 완전 분리되어 탭 전환 없음
#   - 백그라운드에서 독립 실행 가능
#
# 설치: brew install --cask google-chrome-canary
# ══════════════════════════════════════════════════════════════
: "${CHATGPT_BROWSER:=Google Chrome Canary}"

# ══════════════════════════════════════════════════════════════
# 탭 활성화 설정
# ══════════════════════════════════════════════════════════════
# true  - 폴링 시 탭 자동 활성화 (스로틀링 방지, 탭 전환됨)
# false - 탭 활성화 안함 (Canary 사용 시 권장)
#
# Canary 사용 시 false로 설정하면 탭 전환 없이 동작
# ══════════════════════════════════════════════════════════════
: "${CHATGPT_TAB_ACTIVATE:=true}"

# ══════════════════════════════════════════════════════════════
# 폴링 설정
# ══════════════════════════════════════════════════════════════
: "${CHATGPT_WAIT_SEC:=90}"
: "${CHATGPT_EXTRA_WAIT:=120}"
: "${CHATGPT_EXTRA_ROUNDS:=3}"
: "${CHATGPT_MAX_RETRIES:=3}"
: "${CHATGPT_MIN_RESPONSE_LEN:=10}"
: "${CHATGPT_RETRY_DELAY:=2}"
: "${CHATGPT_SESSION_DIR:=/tmp/chatgpt_sessions}"
: "${CHATGPT_AUTO_NEW_CHAT:=true}"

# ══════════════════════════════════════════════════════════════
# Canary 프리셋 (편의 함수)
# ══════════════════════════════════════════════════════════════
# 사용법: use_canary 호출 시 Canary 설정으로 전환
use_canary() {
    export CHATGPT_BROWSER="Google Chrome Canary"
    export CHATGPT_TAB_ACTIVATE=false
    echo "Canary 모드 활성화: CHATGPT_BROWSER=$CHATGPT_BROWSER, TAB_ACTIVATE=$CHATGPT_TAB_ACTIVATE" >&2
}

# 기본 Chrome으로 복귀
use_chrome() {
    export CHATGPT_BROWSER="Google Chrome"
    export CHATGPT_TAB_ACTIVATE=true
    echo "Chrome 모드 활성화: CHATGPT_BROWSER=$CHATGPT_BROWSER, TAB_ACTIVATE=$CHATGPT_TAB_ACTIVATE" >&2
}

# ══════════════════════════════════════════════════════════════
# 브라우저 상태 확인
# ══════════════════════════════════════════════════════════════
is_browser_running() {
    local browser="${1:-$CHATGPT_BROWSER}"
    pgrep -f "$browser" >/dev/null 2>&1
}

# 브라우저 실행 (ChatGPT 프로젝트 URL로)
launch_browser() {
    local url="${1:-https://chatgpt.com}"
    local browser="${CHATGPT_BROWSER:-Google Chrome}"

    if [[ "$browser" == "Google Chrome Canary" ]]; then
        open -a "Google Chrome Canary" "$url"
    elif [[ "$browser" == "Chromium" ]]; then
        open -a "Chromium" "$url"
    else
        open -a "Google Chrome" "$url"
    fi
}
