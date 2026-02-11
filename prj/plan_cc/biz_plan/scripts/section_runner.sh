#!/bin/bash
# section_runner.sh - 전체 섹션 순차 실행
# 사용법: ./section_runner.sh --loop
#         ./section_runner.sh --from=s1_2 --loop

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 프로젝트 설정 로드
if [[ -f "${PROJECT_DIR}/config/settings.sh" ]]; then
    source "${PROJECT_DIR}/config/settings.sh"
fi

# ══════════════════════════════════════════════════════════════
# 섹션 목록 (순서대로)
# ══════════════════════════════════════════════════════════════
get_all_sections() {
    local sections_file="${PROJECT_DIR}/config/sections.yaml"

    if [[ -f "$sections_file" ]]; then
        python3 -c "
import yaml

with open('$sections_file', 'r') as f:
    data = yaml.safe_load(f)

sections = data.get('sections', [])
# needs_human=false인 섹션만, order 순으로 정렬
auto_sections = sorted(
    [s for s in sections if not s.get('needs_human', False) and s.get('id', '').startswith('s')],
    key=lambda x: x.get('order', 999)
)

print(' '.join([s['id'] for s in auto_sections]))
" 2>/dev/null
    else
        # fallback: 기본 섹션 목록
        echo "s1_1 s1_2 s1_3 s2_1 s2_2 s3_1 s3_2 s3_3"
    fi
}

# ══════════════════════════════════════════════════════════════
# 도움말
# ══════════════════════════════════════════════════════════════
show_help() {
    echo ""
    echo "section_runner.sh - 전체 섹션 순차 실행"
    echo ""
    echo "사용법: ./section_runner.sh [옵션]"
    echo ""
    echo "옵션:"
    echo "  --loop          각 섹션에서 버전 반복 (필수)"
    echo "  --from=ID       시작 섹션 지정 (예: --from=s1_2)"
    echo "  --to=ID         종료 섹션 지정 (예: --to=s2_1)"
    echo "  --max=N         섹션당 반복 횟수 (기본: ${MAX_VERSION:-5})"
    echo "  --target=N      목표 점수 (기본: ${TARGET_SCORE:-85})"
    echo "  --dry-run       테스트 실행"
    echo "  --list          섹션 목록만 출력"
    echo "  --help          도움말 표시"
    echo ""
    echo "예시:"
    echo "  ./section_runner.sh --loop                    # 전체 섹션 실행"
    echo "  ./section_runner.sh --from=s1_2 --loop        # s1_2부터 끝까지"
    echo "  ./section_runner.sh --from=s1_2 --to=s2_1 --loop  # s1_2 ~ s2_1"
    echo "  ./section_runner.sh --loop --max=3            # 섹션당 3회 반복"
    echo "  ./section_runner.sh --list                    # 섹션 목록 확인"
    echo ""
    echo "섹션 목록:"
    local sections=$(get_all_sections)
    echo "  $sections"
    echo ""
}

# ══════════════════════════════════════════════════════════════
# 인자 파싱
# ══════════════════════════════════════════════════════════════
LOOP_MODE=false
FROM_SECTION=""
TO_SECTION=""
LOOP_MAX="${MAX_VERSION:-5}"
LOOP_TARGET="${TARGET_SCORE:-85}"
DRY_RUN=""
LIST_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --loop)
            LOOP_MODE=true
            shift
            ;;
        --from=*)
            FROM_SECTION="${1#*=}"
            shift
            ;;
        --to=*)
            TO_SECTION="${1#*=}"
            shift
            ;;
        --max=*)
            LOOP_MAX="${1#*=}"
            shift
            ;;
        --target=*)
            LOOP_TARGET="${1#*=}"
            shift
            ;;
        --dry-run)
            DRY_RUN="--dry-run"
            shift
            ;;
        --list)
            LIST_ONLY=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

# ══════════════════════════════════════════════════════════════
# 섹션 목록 필터링
# ══════════════════════════════════════════════════════════════
get_filtered_sections() {
    local all_sections=$(get_all_sections)
    local sections_array=($all_sections)
    local start_idx=0
    local end_idx=${#sections_array[@]}

    # --from 처리
    if [[ -n "$FROM_SECTION" ]]; then
        for i in "${!sections_array[@]}"; do
            if [[ "${sections_array[$i]}" == "$FROM_SECTION" ]]; then
                start_idx=$i
                break
            fi
        done
    fi

    # --to 처리
    if [[ -n "$TO_SECTION" ]]; then
        for i in "${!sections_array[@]}"; do
            if [[ "${sections_array[$i]}" == "$TO_SECTION" ]]; then
                end_idx=$((i + 1))
                break
            fi
        done
    fi

    # 필터링된 섹션 출력
    echo "${sections_array[@]:$start_idx:$((end_idx - start_idx))}"
}

# ══════════════════════════════════════════════════════════════
# 메인 실행
# ══════════════════════════════════════════════════════════════

# 섹션 목록만 출력
if [[ "$LIST_ONLY" == "true" ]]; then
    echo ""
    echo "전체 섹션 목록:"
    echo "  $(get_all_sections)"
    echo ""
    if [[ -n "$FROM_SECTION" || -n "$TO_SECTION" ]]; then
        echo "필터링된 섹션:"
        echo "  $(get_filtered_sections)"
        echo ""
    fi
    exit 0
fi

# --loop 필수 확인
if [[ "$LOOP_MODE" != "true" ]]; then
    echo "ERROR: --loop 옵션이 필요합니다." >&2
    show_help
    exit 1
fi

# 실행할 섹션 목록
SECTIONS=$(get_filtered_sections)
SECTIONS_ARRAY=($SECTIONS)
TOTAL_SECTIONS=${#SECTIONS_ARRAY[@]}

# 로그 설정
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H%M%S)
LOGS_DIR="${PROJECT_DIR}/testing/logs/${DATE}"
mkdir -p "$LOGS_DIR"
MAIN_LOG="${LOGS_DIR}/section_runner_${TIME}.log"

# 로그 시작
exec > >(tee -a "$MAIN_LOG") 2>&1

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  🚀 Section Runner - 전체 섹션 순차 실행                     ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  시작 시간: $(date '+%Y-%m-%d %H:%M:%S')"
echo "║  실행 섹션: ${TOTAL_SECTIONS}개"
echo "║  섹션 목록: ${SECTIONS}"
echo "║  반복 횟수: ${LOOP_MAX}회/섹션"
echo "║  목표 점수: ${LOOP_TARGET}점"
if [[ -n "$DRY_RUN" ]]; then
echo "║  모드:      DRY-RUN (테스트)"
fi
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 결과 추적
declare -A SECTION_RESULTS
declare -A SECTION_SCORES
RUNNER_START_TIME=$(date +%s)

# 각 섹션 실행
current_idx=0
for section in ${SECTIONS_ARRAY[@]}; do
    ((current_idx++))

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  📂 섹션 ${current_idx}/${TOTAL_SECTIONS}: ${section}"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    # step_runner.sh 호출
    "${SCRIPT_DIR}/step_runner.sh" \
        --section="$section" \
        --loop \
        --max="$LOOP_MAX" \
        --target="$LOOP_TARGET" \
        $DRY_RUN

    exit_code=$?

    # 결과 저장
    if [[ $exit_code -eq 0 ]]; then
        SECTION_RESULTS[$section]="✅ 성공"
    else
        SECTION_RESULTS[$section]="⚠️ 미달"
    fi

    # 최종 점수 확인
    local latest_eval=$(ls -t "${LOG_DIR}/challenger/${section}_v"*.eval.json 2>/dev/null | head -1)
    if [[ -f "$latest_eval" ]]; then
        local score=$(python3 -c "import json; print(json.load(open('$latest_eval')).get('total_score', 0))" 2>/dev/null || echo "0")
        SECTION_SCORES[$section]="$score"
    else
        SECTION_SCORES[$section]="-"
    fi

    echo ""
    echo "━━━ 섹션 ${section} 완료: ${SECTION_RESULTS[$section]} (${SECTION_SCORES[$section]}점) ━━━"
    echo ""
done

# 최종 결과 요약
RUNNER_END_TIME=$(date +%s)
RUNNER_DURATION=$((RUNNER_END_TIME - RUNNER_START_TIME))
RUNNER_MINUTES=$((RUNNER_DURATION / 60))
RUNNER_SECONDS=$((RUNNER_DURATION % 60))

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  🏁 전체 실행 완료                                           ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  종료 시간: $(date '+%Y-%m-%d %H:%M:%S')"
echo "║  소요 시간: ${RUNNER_MINUTES}분 ${RUNNER_SECONDS}초"
echo "║  실행 섹션: ${TOTAL_SECTIONS}개"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  섹션별 결과:                                                ║"
for section in ${SECTIONS_ARRAY[@]}; do
    printf "║    %-8s: %-10s (%s점)\n" "$section" "${SECTION_RESULTS[$section]}" "${SECTION_SCORES[$section]}"
done
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "로그 저장: $MAIN_LOG"
