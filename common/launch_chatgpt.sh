#!/bin/bash
# launch_chatgpt.sh - ChatGPT 브라우저 런처
# Chrome Canary를 ChatGPT 프로젝트와 함께 실행
#
# 사용법:
#   ./launch_chatgpt.sh                    # 기본 프로젝트 URL로 실행
#   ./launch_chatgpt.sh --url="https://..."  # 특정 URL로 실행
#   ./launch_chatgpt.sh --check            # 브라우저 상태만 확인
#   ./launch_chatgpt.sh --install          # Canary 설치 (brew)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 설정 로드
if [[ -f "${SCRIPT_DIR}/chatgpt_config.sh" ]]; then
    source "${SCRIPT_DIR}/chatgpt_config.sh"
fi

# 기본값
: "${CHATGPT_BROWSER:=Google Chrome Canary}"
: "${CHATGPT_PROJECT_URL:=https://chatgpt.com}"

# ══════════════════════════════════════════════════════════════
# 함수들
# ══════════════════════════════════════════════════════════════

show_help() {
    cat <<EOF
launch_chatgpt.sh - ChatGPT 브라우저 런처

사용법:
  ./launch_chatgpt.sh [옵션]

옵션:
  --url=URL       특정 URL로 실행 (기본: $CHATGPT_PROJECT_URL)
  --check         브라우저 상태만 확인
  --install       Chrome Canary 설치 (brew)
  --help          도움말 표시

환경변수:
  CHATGPT_BROWSER      브라우저 이름 (기본: Google Chrome Canary)
  CHATGPT_PROJECT_URL  프로젝트 URL

예시:
  ./launch_chatgpt.sh
  ./launch_chatgpt.sh --url="https://chatgpt.com/g/g-p-xxx"
  CHATGPT_BROWSER="Google Chrome" ./launch_chatgpt.sh

EOF
}

# 브라우저 앱 경로 확인
get_browser_app_path() {
    local browser="$1"
    case "$browser" in
        "Google Chrome Canary")
            echo "/Applications/Google Chrome Canary.app"
            ;;
        "Google Chrome")
            echo "/Applications/Google Chrome.app"
            ;;
        "Chromium")
            echo "/Applications/Chromium.app"
            ;;
        *)
            echo "/Applications/${browser}.app"
            ;;
    esac
}

# 브라우저 설치 여부 확인
is_browser_installed() {
    local app_path
    app_path=$(get_browser_app_path "$CHATGPT_BROWSER")
    [[ -d "$app_path" ]]
}

# 브라우저 실행 여부 확인
is_browser_running() {
    pgrep -f "$CHATGPT_BROWSER" >/dev/null 2>&1
}

# 브라우저 실행
launch_browser() {
    local url="$1"
    local app_path
    app_path=$(get_browser_app_path "$CHATGPT_BROWSER")

    echo "브라우저 실행: $CHATGPT_BROWSER"
    echo "URL: $url"

    open -a "$app_path" "$url"
}

# Canary 설치
install_canary() {
    echo "Chrome Canary 설치 중..."

    if ! command -v brew &>/dev/null; then
        echo "ERROR: Homebrew가 설치되어 있지 않습니다."
        echo "설치: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi

    brew install --cask google-chrome-canary

    echo ""
    echo "설치 완료!"
    echo ""
    echo "다음 단계:"
    echo "1. ./launch_chatgpt.sh 실행"
    echo "2. ChatGPT 로그인 (최초 1회)"
    echo "3. 이후 자동 로그인 유지됨"
}

# 브라우저 상태 확인
check_status() {
    echo "━━━ ChatGPT 브라우저 상태 ━━━"
    echo ""
    echo "설정된 브라우저: $CHATGPT_BROWSER"
    echo "프로젝트 URL: $CHATGPT_PROJECT_URL"
    echo ""

    if is_browser_installed; then
        echo "설치 상태: ✅ 설치됨"
    else
        echo "설치 상태: ❌ 미설치"
        echo ""
        echo "설치 명령: ./launch_chatgpt.sh --install"
        return 1
    fi

    if is_browser_running; then
        echo "실행 상태: ✅ 실행 중"

        # 열린 탭 수 확인
        local tab_count
        tab_count=$(osascript -e "tell application \"$CHATGPT_BROWSER\" to count of tabs of window 1" 2>/dev/null || echo "?")
        echo "열린 탭: ${tab_count}개"
    else
        echo "실행 상태: ⏸️ 미실행"
    fi

    echo ""
}

# ══════════════════════════════════════════════════════════════
# 메인
# ══════════════════════════════════════════════════════════════

URL="$CHATGPT_PROJECT_URL"
ACTION="launch"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --url=*)
            URL="${1#--url=}"
            shift
            ;;
        --check)
            ACTION="check"
            shift
            ;;
        --install)
            ACTION="install"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "알 수 없는 옵션: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

case "$ACTION" in
    install)
        install_canary
        ;;
    check)
        check_status
        ;;
    launch)
        # 설치 확인
        if ! is_browser_installed; then
            echo "ERROR: $CHATGPT_BROWSER 가 설치되어 있지 않습니다." >&2
            echo ""
            echo "설치 방법:"
            if [[ "$CHATGPT_BROWSER" == "Google Chrome Canary" ]]; then
                echo "  brew install --cask google-chrome-canary"
                echo "  또는: ./launch_chatgpt.sh --install"
            else
                echo "  $CHATGPT_BROWSER 를 수동으로 설치하세요."
            fi
            exit 1
        fi

        # 실행
        if is_browser_running; then
            echo "$CHATGPT_BROWSER 이미 실행 중"
            echo "새 탭으로 URL 열기: $URL"
        else
            echo "$CHATGPT_BROWSER 시작 중..."
        fi

        launch_browser "$URL"

        echo ""
        echo "✅ 완료"
        echo ""
        echo "최초 실행 시 ChatGPT 로그인이 필요합니다."
        echo "로그인 후에는 자동으로 로그인 상태가 유지됩니다."
        ;;
esac
