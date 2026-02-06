#!/bin/bash
# notify.sh - 사용자 알림 및 출력 포맷팅

# 색상 코드 (터미널 지원시)
_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[1;33m'
_BLUE='\033[0;34m'
_CYAN='\033[0;36m'
_NC='\033[0m' # No Color

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

# ══════════════════════════════════════════════════════════════
# 상태 메시지 출력
# ══════════════════════════════════════════════════════════════

print_status() {
    local status="$1"
    local message="$2"
    case "$status" in
        "OK")      echo -e "  ${_GREEN}[OK]${_NC} $message" ;;
        "FAIL")    echo -e "  ${_RED}[FAIL]${_NC} $message" ;;
        "WAIT")    echo -e "  ${_YELLOW}[대기]${_NC} $message" ;;
        "WORK")    echo -e "  ${_BLUE}[진행]${_NC} $message" ;;
        "INFO")    echo -e "  ${_CYAN}[정보]${_NC} $message" ;;
        "SCORE")   echo -e "  ${_CYAN}[점수]${_NC} $message" ;;
        *)         echo "  [$status] $message" ;;
    esac
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
    echo "    - 폐업 사유, 개인 경력 등 실제 정보"
    echo ""

    # VSCode에서 파일 열기 시도
    if command -v code &>/dev/null; then
        code "$draft_file" 2>/dev/null
        echo "  (VSCode에서 파일을 열었습니다)"
    fi

    echo ""
    read -r -p "  수정 완료 후 Enter를 눌러주세요... "
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
    local target="$2"
    local iteration="$3"

    print_subsection "평가 결과"
    echo "  점수: $score / 100 (목표: $target)"
    echo "  반복: $iteration회"

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

    print_section "완료"

    echo "  종합 점수: $overall_score / 100"
    echo ""
    echo "  최종 파일: $output_file"
    echo ""

    if [[ $overall_score -ge 85 ]]; then
        print_status "OK" "우수한 사업계획서가 완성되었습니다"
    elif [[ $overall_score -ge 75 ]]; then
        print_status "INFO" "양호한 사업계획서입니다. 세부 검토를 권장합니다"
    else
        print_status "WAIT" "추가 보완이 필요할 수 있습니다"
    fi
}

# ══════════════════════════════════════════════════════════════
# 초기화 관련 출력
# ══════════════════════════════════════════════════════════════

print_welcome() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║     재도전성공패키지 사업계획서 작성 Agent                      ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

print_resume_info() {
    local topic="$1"
    local state="$2"

    print_section "이전 작업 재개"
    echo "  주제: $topic"
    echo "  상태: $state"
}
