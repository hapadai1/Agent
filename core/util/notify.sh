#!/bin/bash
# notify.sh - 사용자 알림 및 출력 포맷팅 (범용화)
# 기존 projects/*/lib/util/notify.sh를 범용화

NOTIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ══════════════════════════════════════════════════════════════
# 색상 코드 (터미널 지원시)
# ══════════════════════════════════════════════════════════════

_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[1;33m'
_BLUE='\033[0;34m'
_CYAN='\033[0;36m'
_MAGENTA='\033[0;35m'
_BOLD='\033[1m'
_NC='\033[0m' # No Color

# 색상 비활성화 옵션
if [[ "${NO_COLOR:-}" == "1" ]] || [[ ! -t 1 ]]; then
    _RED=''
    _GREEN=''
    _YELLOW=''
    _BLUE=''
    _CYAN=''
    _MAGENTA=''
    _BOLD=''
    _NC=''
fi

# ══════════════════════════════════════════════════════════════
# 섹션 구분자 출력
# ══════════════════════════════════════════════════════════════

print_section() {
    local title="$1"
    echo ""
    echo "######"
    echo "$title"
    echo "######"
    echo ""
}

print_subsection() {
    local title="$1"
    echo ""
    echo "━━━ $title ━━━"
}

print_divider() {
    echo "────────────────────────────────────────"
}

print_header() {
    local title="$1"
    local width="${2:-60}"
    echo ""
    printf '═%.0s' $(seq 1 $width)
    echo ""
    echo -e "${_BOLD}${title}${_NC}"
    printf '═%.0s' $(seq 1 $width)
    echo ""
}

# ══════════════════════════════════════════════════════════════
# 상태 메시지 출력
# ══════════════════════════════════════════════════════════════

print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        "OK"|"PASS"|"SUCCESS")
            echo -e "  ${_GREEN}[OK]${_NC} $message" ;;
        "FAIL"|"ERROR")
            echo -e "  ${_RED}[FAIL]${_NC} $message" ;;
        "WAIT"|"PENDING")
            echo -e "  ${_YELLOW}[대기]${_NC} $message" ;;
        "WORK"|"PROGRESS"|"RUN")
            echo -e "  ${_BLUE}[진행]${_NC} $message" ;;
        "INFO")
            echo -e "  ${_CYAN}[정보]${_NC} $message" ;;
        "SCORE")
            echo -e "  ${_CYAN}[점수]${_NC} $message" ;;
        "WARN"|"WARNING")
            echo -e "  ${_YELLOW}[주의]${_NC} $message" ;;
        "SKIP")
            echo -e "  ${_MAGENTA}[스킵]${_NC} $message" ;;
        *)
            echo "  [$status] $message" ;;
    esac
}

# 로그 레벨 출력
log_debug() {
    [[ "${DEBUG:-}" == "1" ]] && echo -e "${_CYAN}[DEBUG]${_NC} $*" >&2
}

log_info() {
    echo -e "${_BLUE}[INFO]${_NC} $*" >&2
}

log_warn() {
    echo -e "${_YELLOW}[WARN]${_NC} $*" >&2
}

log_error() {
    echo -e "${_RED}[ERROR]${_NC} $*" >&2
}

# ══════════════════════════════════════════════════════════════
# 사용자 입력 요청
# ══════════════════════════════════════════════════════════════

# 터미널 벨 + 강조 메시지로 사용자 주의 환기
notify_human() {
    local message="$1"
    printf '\a'  # 터미널 벨
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  [사용자 입력 필요]                                          ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║"
    echo "║  $message"
    echo "║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

# 사용자가 파일을 검토하도록 요청하고 대기
notify_human_review() {
    local section_id="$1"
    local section_name="$2"
    local draft_file="$3"
    local review_hints="${4:-}"

    printf '\a'
    print_section "사용자 검토 필요"

    echo "  섹션: $section_name"
    echo "  파일: $draft_file"
    echo ""
    echo "  이 섹션은 개인 경험/정보가 필요합니다."
    echo "  AI가 예시 기반으로 초안을 작성했습니다."
    echo ""
    echo "  확인/수정 필요 사항:"
    echo "    - [사용자 확인 필요] 표시된 부분"

    if [[ -n "$review_hints" ]]; then
        echo "    - $review_hints"
    fi
    echo ""

    # 에디터에서 파일 열기 시도
    _open_in_editor "$draft_file"

    echo ""
    read -r -p "  수정 완료 후 Enter를 눌러주세요... "
}

# 에디터에서 파일 열기
_open_in_editor() {
    local file="$1"

    # 환경변수로 지정된 에디터
    if [[ -n "${EDITOR:-}" ]]; then
        "$EDITOR" "$file" 2>/dev/null &
        echo "  (${EDITOR}에서 파일을 열었습니다)"
        return
    fi

    # VSCode
    if command -v code &>/dev/null; then
        code "$file" 2>/dev/null
        echo "  (VSCode에서 파일을 열었습니다)"
        return
    fi

    # macOS 기본
    if [[ "$(uname)" == "Darwin" ]]; then
        open "$file" 2>/dev/null
        echo "  (기본 앱에서 파일을 열었습니다)"
        return
    fi
}

# 확인 프롬프트
confirm() {
    local message="${1:-계속하시겠습니까?}"
    local default="${2:-n}"

    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    read -r -p "$message $prompt " response
    response="${response:-$default}"

    [[ "$response" =~ ^[Yy] ]]
}

# ══════════════════════════════════════════════════════════════
# 진행 상황 표시
# ══════════════════════════════════════════════════════════════

# 섹션 작업 시작 알림
print_section_start() {
    local section_id="$1"
    local section_name="$2"
    local current="$3"
    local total="$4"

    print_section "섹션 $current/$total: $section_name"
}

# 점수 결과 출력
print_score_result() {
    local score="$1"
    local target="${2:-85}"
    local iteration="${3:-1}"

    print_subsection "평가 결과"
    echo "  점수: $score / 100 (목표: $target)"
    echo "  반복: ${iteration}회"

    if [[ $score -ge $target ]]; then
        print_status "OK" "목표 점수 달성"
    elif [[ $score -ge 75 ]]; then
        print_status "INFO" "양호 - 추가 개선 시도"
    else
        print_status "WAIT" "재작성 필요"
    fi
}

# 최종 결과 출력
print_final_result() {
    local overall_score="$1"
    local output_file="$2"
    local project_name="${3:-}"

    print_section "완료"

    echo "  종합 점수: $overall_score / 100"
    if [[ -n "$project_name" ]]; then
        echo "  프로젝트: $project_name"
    fi
    echo ""
    echo "  최종 파일: $output_file"
    echo ""

    if [[ $overall_score -ge 85 ]]; then
        print_status "OK" "우수한 결과가 완성되었습니다"
    elif [[ $overall_score -ge 75 ]]; then
        print_status "INFO" "양호한 결과입니다. 세부 검토를 권장합니다"
    else
        print_status "WAIT" "추가 보완이 필요할 수 있습니다"
    fi
}

# ══════════════════════════════════════════════════════════════
# 프로그레스 바
# ══════════════════════════════════════════════════════════════

# 간단한 프로그레스 바
print_progress() {
    local current="$1"
    local total="$2"
    local width="${3:-40}"
    local label="${4:-Progress}"

    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "\r  %s: [" "$label"
    printf '%*s' "$filled" '' | tr ' ' '█'
    printf '%*s' "$empty" '' | tr ' ' '░'
    printf "] %3d%% (%d/%d)" "$percent" "$current" "$total"

    if [[ $current -eq $total ]]; then
        echo ""
    fi
}

# 스피너 (백그라운드 작업용)
_SPINNER_PID=""

start_spinner() {
    local message="${1:-작업 중...}"
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

    (
        while true; do
            for (( i=0; i<${#chars}; i++ )); do
                printf "\r  ${_CYAN}%s${_NC} %s" "${chars:$i:1}" "$message"
                sleep 0.1
            done
        done
    ) &
    _SPINNER_PID=$!
}

stop_spinner() {
    local message="${1:-완료}"

    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null
        wait "$_SPINNER_PID" 2>/dev/null
        _SPINNER_PID=""
    fi
    printf "\r  ${_GREEN}✓${_NC} %s\n" "$message"
}

# ══════════════════════════════════════════════════════════════
# 초기화/완료 메시지 (커스터마이징 가능)
# ══════════════════════════════════════════════════════════════

print_welcome() {
    local title="${1:-Agent}"
    local width="${2:-60}"

    echo ""
    printf '╔'
    printf '═%.0s' $(seq 1 $((width - 2)))
    printf '╗\n'

    printf '║'
    local padding=$(( (width - 2 - ${#title}) / 2 ))
    printf '%*s' "$padding" ''
    printf '%s' "$title"
    printf '%*s' "$((width - 2 - padding - ${#title}))" ''
    printf '║\n'

    printf '╚'
    printf '═%.0s' $(seq 1 $((width - 2)))
    printf '╝\n'
    echo ""
}

print_resume_info() {
    local topic="$1"
    local state="$2"

    print_section "이전 작업 재개"
    echo "  주제: $topic"
    echo "  상태: $state"
}

print_run_info() {
    local run_id="$1"
    local project="$2"
    local flow="${3:-}"

    print_subsection "실행 정보"
    echo "  Run ID: $run_id"
    echo "  Project: $project"
    if [[ -n "$flow" ]]; then
        echo "  Flow: $flow"
    fi
}

# ══════════════════════════════════════════════════════════════
# 호환성 레이어
# ══════════════════════════════════════════════════════════════

# 기존 함수명 그대로 사용 가능

# 직접 실행 시
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Notify Module (Core)"
    echo ""
    echo "함수:"
    echo "  print_section <title>                 섹션 제목"
    echo "  print_subsection <title>              서브섹션"
    echo "  print_status <status> <message>       상태 메시지"
    echo "  notify_human <message>                사용자 알림"
    echo "  notify_human_review <section> ...     파일 검토 요청"
    echo "  print_score_result <score> [target]   점수 출력"
    echo "  print_final_result <score> <file>     최종 결과"
    echo "  print_progress <cur> <total>          프로그레스 바"
    echo "  log_info/warn/error <message>         로그 출력"
    echo ""
    echo "Demo:"
    print_welcome "Agent Demo"
    print_status "OK" "성공 메시지"
    print_status "FAIL" "실패 메시지"
    print_status "INFO" "정보 메시지"
    print_progress 3 10 30 "Processing"
    print_progress 10 10 30 "Processing"
fi
