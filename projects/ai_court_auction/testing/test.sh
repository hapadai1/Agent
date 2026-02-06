#!/bin/bash
# test.sh - 프롬프트 테스트 실행
# 사용법: ./test.sh [ab|a|b] [옵션]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# 테스트 폴더 설정 (suite_runner.sh, suite_compare.sh에서 사용)
export TESTING_DIR="$SCRIPT_DIR"

# 프로젝트 설정 로드
if [[ -f "${PROJECT_DIR}/config.sh" ]]; then
    source "${PROJECT_DIR}/config.sh"
fi

# ══════════════════════════════════════════════════════════════
# 도움말
# ══════════════════════════════════════════════════════════════

show_help() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           프롬프트 테스트 실행 (A/B Testing)                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "사용법: ./test.sh [모드] [옵션]"
    echo ""
    echo "━━━ 실행 모드 ━━━"
    echo ""
    echo "  1. A/B 테스트 (Champion vs Challenger 비교)"
    echo "     ./test.sh ab [--suite=suite-5] [--auto-promote]"
    echo ""
    echo "  2. A 실행 (고정 프롬프트 - Champion)"
    echo "     ./test.sh a [--suite=suite-5]"
    echo ""
    echo "  3. B 실행 (개선 프롬프트 - Challenger)"
    echo "     ./test.sh b [--suite=suite-5]"
    echo ""
    echo "━━━ 옵션 ━━━"
    echo ""
    echo "  --suite=NAME      테스트 스위트 (기본: suite-5)"
    echo "  --runs=N          각 샘플당 반복 횟수 (기본: 5)"
    echo "  --dry-run         ChatGPT 호출 없이 테스트"
    echo "  --auto-promote    A/B 비교 후 자동 승격 (ab 모드만)"
    echo ""
    echo "━━━ 탭 구성 (Chrome ChatGPT) ━━━"
    echo ""
    echo "  Tab1: 리서치"
    echo "  Tab2: Writer (Champion) - 고정 프롬프트"
    echo "  Tab3: Writer (Challenger) - 개선 프롬프트"
    echo "  Tab4: Evaluator (Frozen) - 평가 (매번 New Chat)"
    echo "  Tab5: Prompt Critic + Builder"
    echo ""
    echo "━━━ 예시 ━━━"
    echo ""
    echo "  # Dry-run으로 테스트 구조 확인"
    echo "  ./test.sh a --dry-run"
    echo ""
    echo "  # Champion만 실행"
    echo "  ./test.sh a"
    echo ""
    echo "  # Challenger만 실행"
    echo "  ./test.sh b"
    echo ""
    echo "  # A/B 비교 테스트 (Champion → Challenger → 비교)"
    echo "  ./test.sh ab"
    echo ""
    echo "  # A/B 비교 후 자동 승격"
    echo "  ./test.sh ab --auto-promote"
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

    echo ""
    echo "━━━ A 실행: Champion (고정 프롬프트) ━━━"
    echo ""

    if [[ "$dry_run" == "--dry-run" ]]; then
        "${PROJECT_DIR}/lib/core/suite_runner.sh" --writer=champion --suite="$suite" $start $runs --dry-run
    else
        "${PROJECT_DIR}/lib/core/suite_runner.sh" --writer=champion --suite="$suite" $start $runs
    fi
}

run_challenger() {
    local suite="${1:-suite-5}"
    local dry_run="${2:-}"
    local start="${3:-}"
    local runs="${4:-}"

    echo ""
    echo "━━━ B 실행: Challenger (개선 프롬프트) ━━━"
    echo ""

    if [[ "$dry_run" == "--dry-run" ]]; then
        "${PROJECT_DIR}/lib/core/suite_runner.sh" --writer=challenger --suite="$suite" $start $runs --dry-run
    else
        "${PROJECT_DIR}/lib/core/suite_runner.sh" --writer=challenger --suite="$suite" $start $runs
    fi
}

run_critic_and_build() {
    local suite="${1:-suite-5}"
    local dry_run="${2:-}"

    echo ""
    echo "━━━ Critic 분석 및 Challenger 프롬프트 생성 (Tab5) ━━━"
    echo ""

    if [[ "$dry_run" == "--dry-run" ]]; then
        echo "[DRY-RUN] Critic 스킵"
        return 0
    fi

    # ChatGPT 로드 (config.sh에서 이미 로드된 경우 스킵)
    if ! type chatgpt_call &>/dev/null; then
        if ! load_chatgpt 2>/dev/null; then
            # Fallback: 직접 로드
            local COMMON_DIR
            COMMON_DIR="$(dirname "$(dirname "$PROJECT_DIR")")/common"
            source "${COMMON_DIR}/chatgpt.sh" || return 1
        fi
    fi

    # Champion 결과 디렉토리
    local DATE
    DATE=$(date +%Y-%m-%d)
    local CHAMPION_DIR="${SCRIPT_DIR}/runs/${DATE}/champion"

    if [[ ! -d "$CHAMPION_DIR" ]]; then
        echo "ERROR: Champion 결과 디렉토리 없음: $CHAMPION_DIR" >&2
        return 1
    fi

    # 가장 최근 결과 파일 찾기 (점수가 0이 아닌 것 중에서)
    local latest_out=""
    local latest_eval=""
    local latest_score=0

    for eval_file in "$CHAMPION_DIR"/*.eval.json; do
        [[ -f "$eval_file" ]] || continue
        local score
        score=$(python3 -c "import json; print(json.load(open('$eval_file')).get('total_score', 0))" 2>/dev/null || echo "0")
        if [[ "$score" -gt "$latest_score" ]]; then
            latest_score="$score"
            latest_eval="$eval_file"
            latest_out="${eval_file%.eval.json}.out.md"
        fi
    done

    if [[ -z "$latest_eval" || ! -f "$latest_out" ]]; then
        echo "ERROR: 유효한 Champion 결과 파일 없음" >&2
        return 1
    fi

    echo "분석 대상: $(basename "$latest_out") (점수: $latest_score)"

    # 1. 요청값: 섹션 샘플에서 추출
    local sample_id
    sample_id=$(basename "$latest_out" | sed 's/_v[0-9]*\.out\.md//')
    local sample_file="${SCRIPT_DIR}/suites/samples/${sample_id}.md"
    local request_content=""
    if [[ -f "$sample_file" ]]; then
        request_content=$(cat "$sample_file")
    else
        request_content="(샘플 파일 없음: $sample_id)"
    fi

    # 2. 결과값: Writer 출력 (앞부분만, 너무 길면 잘림)
    local result_content
    result_content=$(head -100 "$latest_out")
    local result_lines
    result_lines=$(wc -l < "$latest_out")
    if [[ "$result_lines" -gt 100 ]]; then
        result_content="$result_content
... (총 ${result_lines}줄 중 100줄만 표시)"
    fi

    # 3. 평가값: 전체 JSON
    local eval_content
    eval_content=$(cat "$latest_eval")

    # 현재 Champion 프롬프트 로드
    local champion_prompt
    champion_prompt=$(cat "${PROJECT_DIR}/prompts/writer/champion.md")

    # Critic 프롬프트 생성 (요청값 + 결과값 + 평가값 포함)
    local critic_prompt="당신은 정부지원사업 사업계획서 프롬프트 개선 전문가입니다.

아래는 Writer 프롬프트로 생성한 결과와 평가입니다. 이를 분석하여 프롬프트를 개선해주세요.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[1. 현재 Writer 프롬프트]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$champion_prompt

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[2. 요청값 - Writer에게 보낸 섹션 정보]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$request_content

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[3. 결과값 - Writer가 생성한 사업계획서]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$result_content

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[4. 평가값 - Evaluator 평가 결과]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$eval_content

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[개선 요청]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
위 평가 결과의 defect_tags와 weaknesses를 분석하여 프롬프트를 개선해주세요.

개선 원칙:
1. 기존 구조는 유지하되, 결함을 방지하는 규칙 추가
2. NO_EVIDENCE_OR_CITATION → 모든 수치에 출처(기관명, 연도) 필수
3. DIFFERENTIATION_WEAK → 경쟁사 대비 차별점 2-3개 필수 명시
4. MISSING_REQUIRED_ITEM → USER_INPUT_NEEDED 대신 가상의 합리적 예시로 본문 완성
5. FORMAT_NONCOMPLIANCE → 표는 반드시 마크다운 형식
6. VAGUE_CLAIMS → 추상적 표현 대신 정량 지표 사용

[출력 형식]
개선된 전체 프롬프트만 출력하세요. (설명 없이 바로 사용 가능한 형태)"

    echo ""
    log_info "Tab5로 Critic 호출 중... (chatgpt_call 사용)"

    # Tab5 호출 (통합 chatgpt_call 사용)
    local response
    response=$(chatgpt_call --tab="${TAB_CRITIC:-5}" --timeout="${TIMEOUT_CRITIC:-90}" --retry "$critic_prompt")

    if [[ -z "$response" ]]; then
        echo "ERROR: Critic 응답 없음 (재시도 후에도 실패)" >&2
        return 1
    fi

    echo "Critic 응답 수신 완료"

    # Challenger 버전 디렉토리 생성
    local challenger_dir="${SCRIPT_DIR}/challenger_versions"
    mkdir -p "$challenger_dir"

    # 다음 버전 번호 계산
    local next_version=1
    for f in "$challenger_dir"/v*.md; do
        [[ -f "$f" ]] || continue
        local v
        v=$(basename "$f" | sed 's/v\([0-9]*\)\.md/\1/')
        if [[ "$v" -ge "$next_version" ]]; then
            next_version=$((v + 1))
        fi
    done

    # 버전 파일 저장
    local version_file="${challenger_dir}/v${next_version}.md"
    echo "$response" > "$version_file"
    echo "📁 버전 저장: prompts/challenger/v${next_version}.md"

    # challenger.md 업데이트 (최신 버전 = 활성 프롬프트)
    local challenger_file="${PROJECT_DIR}/prompts/writer/challenger.md"
    echo "$response" > "$challenger_file"

    echo ""
    echo "✅ Challenger 프롬프트 업데이트 완료"
    echo "   - 현재 버전: v${next_version}"
    echo "   - 버전 파일: prompts/challenger/v${next_version}.md"
    echo "   - 활성 파일: prompts/writer/challenger.md"
    echo ""

    # 로그 저장 (요청값, 결과값, 평가값 포함) - challenger 폴더에 함께 저장
    local log_file="${challenger_dir}/v${next_version}.log"
    cat > "$log_file" <<EOF
=== Critic 실행 로그 (v${next_version}) ===
날짜: $(date)
분석 대상: $(basename "$latest_out")
원본 점수: $latest_score

=== 요청값 (섹션 정보) ===
$request_content

=== 결과값 (Writer 출력) ===
$result_content

=== 평가값 (Evaluator 결과) ===
$eval_content

=== 생성된 Challenger 프롬프트 (v${next_version}) ===
$response
EOF
    echo "📝 로그 저장: prompts/challenger/v${next_version}.log"
}

run_ab_test() {
    local suite="${1:-suite-5}"
    local auto_promote="${2:-}"
    local dry_run="${3:-}"
    local start="${4:-}"
    local runs="${5:-}"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              A/B 테스트 시작                                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    # Step 1: Champion 실행
    echo "═══ Step 1/4: Champion (A) 실행 ═══"
    run_champion "$suite" "$dry_run" "$start" "$runs"

    # Step 2: Critic 분석 및 Challenger 프롬프트 생성
    echo ""
    echo "═══ Step 2/4: Critic 분석 (Tab5) ═══"
    run_critic_and_build "$suite" "$dry_run"

    echo ""
    echo "═══ Step 3/4: Challenger (B) 실행 ═══"
    run_challenger "$suite" "$dry_run" "$start" "$runs"

    echo ""
    echo "═══ Step 4/4: 결과 비교 ═══"
    echo ""

    if [[ "$dry_run" == "--dry-run" ]]; then
        echo "[DRY-RUN] 비교 스킵"
    elif [[ "$auto_promote" == "--auto-promote" ]]; then
        "${PROJECT_DIR}/lib/core/suite_compare.sh" --suite="$suite" --auto-promote
    else
        "${PROJECT_DIR}/lib/core/suite_compare.sh" --suite="$suite"
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              A/B 테스트 완료                                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
}

# ══════════════════════════════════════════════════════════════
# 인자 파싱
# ══════════════════════════════════════════════════════════════

MODE="${1:-help}"
SUITE="suite-5"
DRY_RUN=""
AUTO_PROMOTE=""
START_FROM=""
RUNS="--runs=5"  # 기본 5회 반복

shift || true

while [[ $# -gt 0 ]]; do
    case $1 in
        --suite=*)
            SUITE="${1#*=}"
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
        --auto-promote)
            AUTO_PROMOTE="--auto-promote"
            shift
            ;;
        *)
            echo "알 수 없는 옵션: $1"
            exit 1
            ;;
    esac
done

# ══════════════════════════════════════════════════════════════
# 메인
# ══════════════════════════════════════════════════════════════

case "$MODE" in
    ab|AB|1)
        run_ab_test "$SUITE" "$AUTO_PROMOTE" "$DRY_RUN" "$START_FROM" "$RUNS"
        ;;
    a|A|champion|2)
        run_champion "$SUITE" "$DRY_RUN" "$START_FROM" "$RUNS"
        ;;
    b|B|challenger|3)
        run_challenger "$SUITE" "$DRY_RUN" "$START_FROM" "$RUNS"
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        echo "알 수 없는 모드: $MODE"
        show_help
        exit 1
        ;;
esac
