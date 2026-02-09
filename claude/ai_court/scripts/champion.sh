#!/bin/bash
# champion.sh - Champion (고정 프롬프트) 테스트 실행
# 사용법: ./champion.sh [옵션]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 프로젝트 설정 로드
if [[ -f "${PROJECT_DIR}/config/config.sh" ]]; then
    source "${PROJECT_DIR}/config/config.sh"
fi

# ══════════════════════════════════════════════════════════════
# 도움말
# ══════════════════════════════════════════════════════════════

show_help() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           Champion 테스트 실행                               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "사용법: ./champion.sh [옵션]"
    echo ""
    echo "━━━ 옵션 ━━━"
    echo ""
    echo "  --suite=NAME      특정 스위트 실행 (예: suite-s1_2)"
    echo "  --from=SECTION    해당 섹션부터 끝까지 실행 (예: --from=s1_2)"
    echo "  --from=SECTION:V  해당 섹션의 버전 V부터 실행 (예: --from=s1_2:3)"
    echo "  --runs=N          각 샘플당 반복 횟수 (기본: 5)"
    echo "  --research        리서치 실행 포함 (Tab1)"
    echo "  --dry-run         ChatGPT 호출 없이 테스트"
    echo ""
    echo "━━━ 예시 ━━━"
    echo ""
    echo "  ./champion.sh                    # 기본 suite-5 실행"
    echo "  ./champion.sh --suite=suite-s1_2 # 특정 스위트"
    echo "  ./champion.sh --from=s1_2        # s1_2부터 끝까지"
    echo "  ./champion.sh --dry-run          # 테스트 모드"
    echo ""
}

# ══════════════════════════════════════════════════════════════
# 실행 함수
# ══════════════════════════════════════════════════════════════

run_champion() {
    local suite="${1:-suite-5}"
    local dry_run="${2:-}"
    local start="${3:-}"
    local runs="${4:-}"
    local research="${5:-}"

    echo ""
    echo "━━━ Champion (고정 프롬프트) 실행 ━━━"
    echo ""

    local DATE=$(date +%Y-%m-%d)
    local RUN_DIR="${SCRIPT_DIR}/runs/${DATE}/champion"
    local LOG_DIR="${SCRIPT_DIR}/logs/${DATE}"
    mkdir -p "$RUN_DIR" "$LOG_DIR"
    local LOG_FILE="${LOG_DIR}/champion_$(date +%H%M%S).log"

    echo "📝 로그 파일: $LOG_FILE"

    if [[ "$dry_run" == "--dry-run" ]]; then
        "${PROJECT_DIR}/lib/core/suite_runner.sh" --writer=champion --suite="$suite" $start $runs $research --dry-run 2>&1 | tee -a "$LOG_FILE"
    else
        "${PROJECT_DIR}/lib/core/suite_runner.sh" --writer=champion --suite="$suite" $start $runs $research 2>&1 | tee -a "$LOG_FILE"
    fi
}

# ══════════════════════════════════════════════════════════════
# 섹션 순차 실행
# ══════════════════════════════════════════════════════════════

get_sections_from() {
    local from_section="$1"
    local sections_file="${PROJECT_DIR}/config/sections.yaml"

    if [[ ! -f "$sections_file" ]]; then
        echo "s1_1 s1_2 s1_3 s2_1 s2_2 s3_1 s3_2 s3_3"
        return
    fi

    python3 -c "
import yaml

with open('$sections_file', 'r') as f:
    data = yaml.safe_load(f)

sections = data.get('sections', [])
auto_sections = sorted(
    [s for s in sections if not s.get('needs_human', False) and s.get('id', '').startswith('s')],
    key=lambda x: x.get('order', 999)
)

ids = [s['id'] for s in auto_sections]

try:
    start_idx = ids.index('$from_section')
    print(' '.join(ids[start_idx:]))
except ValueError:
    print(' '.join(ids))
" 2>/dev/null
}

run_from_section() {
    local from_section="$1"
    local dry_run="$2"
    local runs="$3"
    local research="$4"
    local start_version="$5"

    local version_info=""
    local start_version_opt=""
    if [[ -n "$start_version" ]]; then
        version_info=":v${start_version}"
        start_version_opt="--start-version=${start_version}"
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  --from=${from_section}${version_info}: 해당 섹션부터 끝까지 실행"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    local sections
    sections=$(get_sections_from "$from_section")

    echo "실행할 섹션: $sections"
    [[ -n "$start_version" ]] && echo "시작 버전: v${start_version}"
    echo ""

    local is_first_section=true
    for section_id in $sections; do
        local suite_name="suite-${section_id}"
        local suite_file="${SCRIPT_DIR}/suites/${suite_name}.yaml"

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  섹션: $section_id (suite: $suite_name)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        if [[ ! -f "$suite_file" ]]; then
            echo "⚠️  Suite 파일 없음: $suite_file (스킵)"
            continue
        fi

        local current_start_opt=""
        if [[ "$is_first_section" == true ]] && [[ -n "$start_version_opt" ]]; then
            current_start_opt="$start_version_opt"
        fi

        run_champion "$suite_name" "$dry_run" "$current_start_opt" "$runs" "$research"
        is_first_section=false
    done

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  --from=${from_section}${version_info} 완료"
    echo "╚══════════════════════════════════════════════════════════════╝"
}

# ══════════════════════════════════════════════════════════════
# 인자 파싱
# ══════════════════════════════════════════════════════════════

SUITE="suite-5"
DRY_RUN=""
START_FROM=""
FROM_SECTION=""
FROM_VERSION=""
RUNS="--runs=5"
RESEARCH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --suite=*)
            SUITE="${1#*=}"
            shift
            ;;
        --from=*)
            from_value="${1#*=}"
            if [[ "$from_value" == *:* ]]; then
                FROM_SECTION="${from_value%%:*}"
                version_part="${from_value#*:}"
                FROM_VERSION="${version_part#v}"
            else
                FROM_SECTION="$from_value"
                FROM_VERSION=""
            fi
            shift
            ;;
        --start=*)
            START_FROM="--start=${1#*=}"
            shift
            ;;
        --runs=*)
            RUNS="--runs=${1#*=}"
            shift
            ;;
        --dry-run)
            DRY_RUN="--dry-run"
            shift
            ;;
        --research)
            RESEARCH="--research"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "알 수 없는 옵션: $1"
            show_help
            exit 1
            ;;
    esac
done

# ══════════════════════════════════════════════════════════════
# 메인
# ══════════════════════════════════════════════════════════════

if [[ -n "$FROM_SECTION" ]]; then
    run_from_section "$FROM_SECTION" "$DRY_RUN" "$RUNS" "$RESEARCH" "$FROM_VERSION"
else
    run_champion "$SUITE" "$DRY_RUN" "$START_FROM" "$RUNS" "$RESEARCH"
fi
