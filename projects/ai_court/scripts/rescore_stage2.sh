#!/bin/bash
# rescore_stage2.sh - Stage 2 (정부 심사 기준) 재채점 스크립트
# 사용법: ./rescore_stage2.sh --date=2026-02-09 [--section=s1_2] [--dry-run]
#
# 기존 .out.md 파일들을 Stage 2 평가자로 재채점합니다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ══════════════════════════════════════════════════════════════
# 프로젝트 설정 로드
# ══════════════════════════════════════════════════════════════
if [[ -f "${PROJECT_DIR}/config/settings.sh" ]]; then
    source "${PROJECT_DIR}/config/settings.sh"
    load_chatgpt 2>/dev/null || true
else
    echo "ERROR: config.sh not found" >&2
    exit 1
fi

# ══════════════════════════════════════════════════════════════
# 공통 모듈 로드
# ══════════════════════════════════════════════════════════════
source "${PROJECT_DIR}/lib/util/parser.sh"
source "${PROJECT_DIR}/lib/util/errors.sh"
source "${PROJECT_DIR}/lib/util/template.sh"

# ══════════════════════════════════════════════════════════════
# 인자 파싱
# ══════════════════════════════════════════════════════════════
TARGET_DATE=""
TARGET_SECTION=""
TARGET_VERSION=""
DRY_RUN=false
SKIP_EXISTING=true

show_help() {
    echo ""
    echo "rescore_stage2.sh - Stage 2 (정부 심사 기준) 재채점"
    echo ""
    echo "사용법: ./rescore_stage2.sh --date=2026-02-09 [옵션]"
    echo ""
    echo "필수 옵션:"
    echo "  --date=YYYY-MM-DD  대상 날짜 (예: 2026-02-09)"
    echo ""
    echo "선택 옵션:"
    echo "  --section=ID       특정 섹션만 처리 (예: s1_2)"
    echo "  --version=N        특정 버전만 처리 (예: 6)"
    echo "  --force            기존 eval_stage2.json 덮어쓰기"
    echo "  --dry-run          ChatGPT 호출 없이 테스트"
    echo "  --help             도움말 표시"
    echo ""
    echo "예시:"
    echo "  ./rescore_stage2.sh --date=2026-02-09                              # 전체 재채점"
    echo "  ./rescore_stage2.sh --date=2026-02-09 --section=s1_2               # s1_2만 재채점"
    echo "  ./rescore_stage2.sh --date=2026-02-09 --section=s1_2 --version=6   # s1_2 v6만 재채점"
    echo "  ./rescore_stage2.sh --date=2026-02-09 --dry-run                    # 테스트"
    echo ""
    echo "출력 파일: {section}_{version}.eval_stage2.json"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --date=*)
            TARGET_DATE="${1#*=}"
            shift
            ;;
        --section=*)
            TARGET_SECTION="${1#*=}"
            shift
            ;;
        --version=*)
            TARGET_VERSION="${1#*=}"
            shift
            ;;
        --force)
            SKIP_EXISTING=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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

# 필수 인자 확인
if [[ -z "$TARGET_DATE" ]]; then
    echo "ERROR: --date는 필수입니다." >&2
    show_help
    exit 1
fi

# ══════════════════════════════════════════════════════════════
# 경로 설정
# ══════════════════════════════════════════════════════════════
RUNS_DIR="${PROJECT_DIR}/runtime/runs/${TARGET_DATE}/challenger"
SUITES_DIR="${PROJECT_DIR}/suites"
EVALUATOR_STAGE2="${PROJECT_DIR}/prompts/evaluator/evaluator_stage2.md"

if [[ ! -d "$RUNS_DIR" ]]; then
    echo "ERROR: 실행 디렉토리 없음: $RUNS_DIR" >&2
    exit 1
fi

if [[ ! -f "$EVALUATOR_STAGE2" ]]; then
    echo "ERROR: Stage 2 평가자 프롬프트 없음: $EVALUATOR_STAGE2" >&2
    exit 1
fi

# ══════════════════════════════════════════════════════════════
# 재채점 함수
# ══════════════════════════════════════════════════════════════

rescore_file() {
    local out_file="$1"
    local filename=$(basename "$out_file")

    # 파일명 파싱: s1_2_v1.out.md → section=s1_2, version=v1
    local section version
    section=$(echo "$filename" | sed -E 's/^(s[0-9]+_[0-9]+)_v[0-9]+\.out\.md$/\1/')
    version=$(echo "$filename" | sed -E 's/^s[0-9]+_[0-9]+_(v[0-9]+)\.out\.md$/\1/')

    # 출력 파일 경로
    local eval_stage2_file="${RUNS_DIR}/${section}_${version}.eval_stage2.json"

    # 기존 파일 스킵 체크
    if [[ "$SKIP_EXISTING" == "true" && -f "$eval_stage2_file" ]]; then
        echo "  ⏭️  스킵 (기존 파일 있음): $filename"
        return 0
    fi

    echo ""
    echo "━━━ Stage 2 재채점: ${section} ${version} ━━━"

    # Writer 출력 읽기
    local content
    content=$(cat "$out_file")
    local content_len=${#content}

    if [[ $content_len -lt 100 ]]; then
        echo "  ⚠️ 콘텐츠 너무 짧음 (${content_len}자 < 100자) - 스킵"
        return 1
    fi

    echo "  콘텐츠: ${content_len}자"

    # 샘플에서 section_name 추출
    local sample_file="${SUITES_DIR}/samples/${section}_case01.md"
    local section_name=""
    if [[ -f "$sample_file" ]]; then
        section_name=$(parse_front_matter "$sample_file" "section_name")
    else
        section_name="$section"
    fi

    # Stage 2 평가자 프롬프트 생성
    local evaluator_prompt
    evaluator_prompt=$(render_evaluator_prompt "$EVALUATOR_STAGE2" "$section_name" "$content")

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] ChatGPT 호출 스킵"
        echo "  프롬프트 길이: ${#evaluator_prompt}자"
        return 0
    fi

    # 새 채팅 시작
    echo "  🔄 새 채팅 시작"
    chatgpt_call --mode=new_chat --tab="$CHATGPT_TAB" --project="$CHATGPT_PROJECT_URL" >/dev/null 2>&1
    sleep 2

    # ChatGPT 호출
    local start_time=$(date +%s)
    echo "  ChatGPT 호출 중 (Tab $CHATGPT_TAB, timeout: ${TIMEOUT_EVALUATOR:-600}초)..."

    local eval_response
    eval_response=$(chatgpt_call --tab="$CHATGPT_TAB" --timeout="${TIMEOUT_EVALUATOR:-600}" --retry "$evaluator_prompt")

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # ChatGPT 오류 감지
    if is_chatgpt_error "$eval_response"; then
        echo "  ⚠️ ChatGPT 오류: $(get_error_message "$eval_response")"
        return 1
    fi

    # JSON 추출
    local json_only
    json_only=$(extract_json "$eval_response")

    local chars=${#json_only}

    # JSON 검증
    if [[ $chars -lt 100 ]]; then
        echo "  ⚠️ JSON 추출 실패 (${chars}자 < 100자)"
        return 1
    fi

    # 결과 저장
    echo "$json_only" > "$eval_stage2_file"

    # 점수 추출
    local score normalized_score readiness
    score=$(json_get "$json_only" "total_score")
    normalized_score=$(json_get "$json_only" "normalized_score")
    readiness=$(json_get "$json_only" "government_readiness")

    echo ""
    echo "  ✅ Stage 2 평가 완료"
    echo "     파일: $(basename "$eval_stage2_file")"
    echo "     총점: ${score}점"
    echo "     환산: ${normalized_score}점"
    echo "     심사: ${readiness}"
    echo "     시간: ${duration}초"

    return 0
}

# ══════════════════════════════════════════════════════════════
# 메인 실행
# ══════════════════════════════════════════════════════════════

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  🏛️  Stage 2 재채점 (정부 심사 기준)                         ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  대상 날짜: ${TARGET_DATE}"
echo "║  대상 섹션: ${TARGET_SECTION:-전체}"
echo "║  대상 버전: ${TARGET_VERSION:-전체}"
echo "║  디렉토리:  ${RUNS_DIR}"
echo "║  평가자:    evaluator_stage2.md"
echo "║  시작 시간: $(date '+%Y-%m-%d %H:%M:%S')"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 대상 파일 찾기
if [[ -n "$TARGET_SECTION" && -n "$TARGET_VERSION" ]]; then
    files=$(find "$RUNS_DIR" -name "${TARGET_SECTION}_v${TARGET_VERSION}.out.md" | sort)
elif [[ -n "$TARGET_SECTION" ]]; then
    files=$(find "$RUNS_DIR" -name "${TARGET_SECTION}_v*.out.md" | sort)
elif [[ -n "$TARGET_VERSION" ]]; then
    files=$(find "$RUNS_DIR" -name "*_v${TARGET_VERSION}.out.md" | sort)
else
    files=$(find "$RUNS_DIR" -name "*.out.md" | sort)
fi

file_count=$(echo "$files" | grep -c "\.out\.md" || echo "0")

if [[ "$file_count" -eq 0 ]]; then
    echo "대상 파일 없음"
    exit 0
fi

echo "대상 파일: ${file_count}개"
echo ""

# 통계
success_count=0
skip_count=0
fail_count=0

for file in $files; do
    if [[ -f "$file" ]]; then
        if rescore_file "$file"; then
            if [[ "$SKIP_EXISTING" == "true" && -f "${file%.out.md}.eval_stage2.json" ]]; then
                ((skip_count++))
            else
                ((success_count++))
            fi
        else
            ((fail_count++))
        fi
    fi
done

# 결과 요약
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  🏁 Stage 2 재채점 완료                                      ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  총 파일:   ${file_count}개"
echo "║  성공:      ${success_count}개"
echo "║  스킵:      ${skip_count}개"
echo "║  실패:      ${fail_count}개"
echo "║  종료 시간: $(date '+%Y-%m-%d %H:%M:%S')"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# 결과 파일 목록
echo "━━━ 생성된 Stage 2 평가 파일 ━━━"
find "$RUNS_DIR" -name "*.eval_stage2.json" -newer "$0" 2>/dev/null | sort | while read f; do
    score=$(python3 -c "import json; d=json.load(open('$f')); print(d.get('normalized_score', d.get('total_score', 0)))" 2>/dev/null || echo "?")
    echo "  $(basename "$f"): ${score}점"
done

echo ""
echo "━━━ 점수 비교 (Stage 1 vs Stage 2) ━━━"
for out_file in $(find "$RUNS_DIR" -name "*.out.md" | sort); do
    base="${out_file%.out.md}"
    s1_file="${base}.eval.json"
    s2_file="${base}.eval_stage2.json"

    if [[ -f "$s1_file" && -f "$s2_file" ]]; then
        s1_score=$(python3 -c "import json; print(json.load(open('$s1_file')).get('total_score', 0))" 2>/dev/null || echo "?")
        s2_score=$(python3 -c "import json; d=json.load(open('$s2_file')); print(d.get('normalized_score', d.get('total_score', 0)))" 2>/dev/null || echo "?")
        readiness=$(python3 -c "import json; print(json.load(open('$s2_file')).get('government_readiness', '?'))" 2>/dev/null || echo "?")
        echo "  $(basename "$base"): Stage1=${s1_score}점 → Stage2=${s2_score}점 (${readiness})"
    fi
done

exit 0
