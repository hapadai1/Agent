#!/bin/bash
# step_runner.sh - 단일 Step 실행 (Claude Agent용)
# 사용법: ./step_runner.sh --section=s1_2 --version=1 --step=writer
#
# Claude가 각 step을 실행하고 결과를 확인한 후 다음 행동을 결정합니다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ══════════════════════════════════════════════════════════════
# 프로젝트 설정 로드
# ══════════════════════════════════════════════════════════════
if [[ -f "${PROJECT_DIR}/config/config.sh" ]]; then
    source "${PROJECT_DIR}/config/config.sh"
    load_chatgpt 2>/dev/null || true
else
    echo "ERROR: config.sh not found" >&2
    exit 1
fi

# ══════════════════════════════════════════════════════════════
# 공통 모듈 로드
# ══════════════════════════════════════════════════════════════
source "${PROJECT_DIR}/lib/util/parser.sh"
source "${PROJECT_DIR}/lib/util/research.sh"
source "${PROJECT_DIR}/lib/util/errors.sh"
source "${PROJECT_DIR}/lib/util/state.sh"
source "${PROJECT_DIR}/lib/util/template.sh"

# 상태 디렉토리 초기화
init_state_dir "${PROJECT_DIR}/state"

# 날짜 및 경로 설정
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H%M%S)
RUNS_DIR="${PROJECT_DIR}/runs/${DATE}/challenger"
LOGS_DIR="${PROJECT_DIR}/logs/${DATE}"
SUITES_DIR="${PROJECT_DIR}/suites"
mkdir -p "$RUNS_DIR" "$LOGS_DIR"

# 로그 파일 설정
LOG_FILE="${LOGS_DIR}/step_${TIME}.log"

# ══════════════════════════════════════════════════════════════
# 인자 파싱
# ══════════════════════════════════════════════════════════════
SECTION=""
VERSION=""
STEP=""
RETRY=false
DRY_RUN=false
LOOP_MODE=false
LOOP_MAX="${MAX_VERSION:-5}"
LOOP_TARGET="${TARGET_SCORE:-85}"

show_help() {
    echo ""
    echo "step_runner.sh - Step 실행 (단일 또는 자동 반복)"
    echo ""
    echo "━━━ 단일 실행 모드 ━━━"
    echo "사용법: ./step_runner.sh --section=s1_2 --version=1 --step=prompt"
    echo ""
    echo "필수 옵션:"
    echo "  --section=ID    섹션 ID (예: s1_1, s1_2, s1_3)"
    echo "  --version=N     버전 번호 (1, 2, 3, 4, 5)"
    echo "  --step=STEP     실행할 단계 (prompt, writer, evaluator)"
    echo ""
    echo "━━━ 자동 반복 모드 (--loop) ━━━"
    echo "사용법: ./step_runner.sh --section=s1_2 --loop"
    echo ""
    echo "반복 옵션:"
    echo "  --loop          자동 반복 모드 (prompt→writer→evaluator 사이클)"
    echo "  --max=N         반복 횟수 (기본: ${MAX_VERSION:-5})"
    echo "  --target=N      목표 점수 - 도달 시 조기 종료 (기본: ${TARGET_SCORE:-85})"
    echo "  --start=N       시작 버전 (기본: 1)"
    echo "  --version=N     시작 버전 (--start와 동일)"
    echo ""
    echo "선택 옵션:"
    echo "  --retry         재시도 모드 (새 채팅에서 실행)"
    echo "  --dry-run       ChatGPT 호출 없이 테스트"
    echo "  --help          도움말 표시"
    echo ""
    echo "실행 순서 (모두 Tab${CHATGPT_TAB:-1}에서 새 채팅으로 실행):"
    echo "  1. prompt    → 프롬프트 생성"
    echo "  2. writer    → 내용 작성"
    echo "  3. evaluator → 품질 평가"
    echo ""
    echo "예시 (단일):"
    echo "  ./step_runner.sh --section=s3_1 --version=1 --step=prompt"
    echo "  ./step_runner.sh --section=s3_1 --version=1 --step=writer"
    echo "  ./step_runner.sh --section=s3_1 --version=1 --step=evaluator"
    echo ""
    echo "예시 (반복):"
    echo "  ./step_runner.sh --section=s1_2 --loop                    # v1~v5 (5회)"
    echo "  ./step_runner.sh --section=s1_2 --loop --start=2          # v2~v6 (5회)"
    echo "  ./step_runner.sh --section=s1_2 --loop --start=2 --max=7  # v2~v8 (7회)"
    echo "  ./step_runner.sh --section=s1_2 --loop --target=90        # 90점 도달 시 조기 종료"
    echo "  ./step_runner.sh --section=s1_2 --loop --dry-run          # 테스트 실행"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --section=*)
            SECTION="${1#*=}"
            shift
            ;;
        --version=*)
            VERSION="${1#*=}"
            shift
            ;;
        --step=*)
            STEP="${1#*=}"
            shift
            ;;
        --loop)
            LOOP_MODE=true
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
        --start=*)
            VERSION="${1#*=}"
            shift
            ;;
        --retry)
            RETRY=true
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
if [[ -z "$SECTION" ]]; then
    echo "ERROR: --section은 필수입니다." >&2
    show_help
    exit 1
fi

# 모드별 필수 인자 확인
if [[ "$LOOP_MODE" == "true" ]]; then
    # --loop 모드: --version 기본값 1, --step 불필요
    VERSION="${VERSION:-1}"
else
    # 단일 실행 모드: --version, --step 필수
    if [[ -z "$VERSION" || -z "$STEP" ]]; then
        echo "ERROR: 단일 실행 시 --version, --step은 필수입니다." >&2
        echo "       또는 --loop 옵션을 사용하세요." >&2
        show_help
        exit 1
    fi

    # Step 유효성 확인
    if [[ "$STEP" != "prompt" && "$STEP" != "writer" && "$STEP" != "evaluator" ]]; then
        echo "ERROR: --step은 prompt, writer, evaluator 중 하나여야 합니다." >&2
        exit 1
    fi
fi

# ══════════════════════════════════════════════════════════════
# Step 실행 함수
# ══════════════════════════════════════════════════════════════

run_writer() {
    local sample_file="${SUITES_DIR}/samples/${SECTION}_case01.md"
    local prompt_file="${RUNS_DIR}/${SECTION}_v${VERSION}.prompt.md"

    # 프롬프트 파일 확인 (prompt step에서 생성됨)
    if [[ ! -f "$prompt_file" ]]; then
        print_prerequisites_error "writer" "$prompt_file" "먼저 --step=prompt를 실행하세요"
        save_state "error" "" 0 0
        return 1
    fi

    echo "━━━ Writer 실행: ${SECTION} v${VERSION} ━━━"

    # 메타데이터 추출 (공통 모듈 사용)
    local section_name topic pages body
    section_name=$(parse_front_matter "$sample_file" "section_name")
    body=$(get_body "$sample_file")
    topic=$(extract_topic "$sample_file")
    pages=$(extract_pages "$sample_file")

    # 생성된 프롬프트 로드
    local prompt_template
    prompt_template=$(cat "$prompt_file")
    echo "프롬프트 로드: $prompt_file (${#prompt_template}자)"

    # 리서치 블록 로드 (공통 모듈 사용)
    local research_block
    research_block=$(load_research_block "$SECTION")

    # 변수 치환하여 최종 프롬프트 생성 (안전한 템플릿 사용)
    local writer_prompt
    writer_prompt=$(render_template "$prompt_template" \
        "topic=$topic" \
        "section_name=$section_name" \
        "section_detail=$body" \
        "pages=$pages" \
        "prior_summary_block=")

    # 리서치 블록 직접 추가
    if [[ -n "$research_block" ]]; then
        writer_prompt="$writer_prompt

$research_block"
        echo "리서치 블록 추가됨 (${#research_block}자)"
    fi

    # 출력 파일 경로
    local out_file="${RUNS_DIR}/${SECTION}_v${VERSION}.out.md"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] ChatGPT 호출 스킵"
        save_state "dry_run" "$out_file" 0 0
        return 0
    fi

    # 항상 새 채팅 시작
    echo "🔄 Writer: 새 채팅 시작"
    chatgpt_call --mode=new_chat --tab="$CHATGPT_TAB" --project="$CHATGPT_PROJECT_URL" >/dev/null 2>&1
    sleep 2

    # ChatGPT 호출
    local start_time=$(date +%s)
    echo "ChatGPT 호출 중 (Tab $CHATGPT_TAB, timeout: ${TIMEOUT_WRITER}초)..."

    local writer_response
    writer_response=$(chatgpt_call --tab="$CHATGPT_TAB" --timeout="$TIMEOUT_WRITER" --retry "$writer_prompt")

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # ChatGPT 오류 감지 (공통 모듈 사용)
    if is_chatgpt_error "$writer_response"; then
        echo "⚠️ ChatGPT 오류 감지: $(get_error_message "$writer_response")"
        save_state "failed" "$out_file" 0 "$duration"
        return 1
    fi

    local chars=${#writer_response}

    # 결과 저장
    echo "$writer_response" > "$out_file"

    echo ""
    echo "━━━ Writer 결과 ━━━"
    echo "출력 파일: $out_file"
    echo "응답 길이: ${chars}자"
    echo "소요 시간: ${duration}초"

    # 상태 저장
    save_state "completed" "$out_file" "$chars" "$duration"

    return 0
}

run_evaluator() {
    local writer_output="${RUNS_DIR}/${SECTION}_v${VERSION}.out.md"

    if [[ ! -f "$writer_output" ]]; then
        print_prerequisites_error "evaluator" "$writer_output" "먼저 --step=writer를 실행하세요"
        save_state "error" "" 0 0
        return 1
    fi

    echo "━━━ Evaluator 실행: ${SECTION} v${VERSION} ━━━"

    # Writer 출력 읽기
    local writer_response
    writer_response=$(cat "$writer_output")
    local writer_len=${#writer_response}

    echo "Writer 출력: ${writer_len}자"

    # 샘플에서 section_name 추출 (공통 모듈 사용)
    local sample_file="${SUITES_DIR}/samples/${SECTION}_case01.md"
    local section_name
    section_name=$(parse_front_matter "$sample_file" "section_name")

    # Evaluator 프롬프트 생성 (안전한 템플릿 사용)
    local evaluator_file="${PROJECT_DIR}/prompts/evaluator/evaluator.md"
    local evaluator_prompt
    evaluator_prompt=$(render_evaluator_prompt "$evaluator_file" "$section_name" "$writer_response")

    # 출력 파일 경로
    local eval_file="${RUNS_DIR}/${SECTION}_v${VERSION}.eval.json"
    local eval_prompt_file="${RUNS_DIR}/${SECTION}_v${VERSION}.eval_prompt.md"

    # 프롬프트 저장
    echo "$evaluator_prompt" > "$eval_prompt_file"
    echo "프롬프트 저장: $eval_prompt_file (${#evaluator_prompt}자)"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] ChatGPT 호출 스킵"
        save_state "dry_run" "$eval_file" 0 0
        return 0
    fi

    # 새 채팅 시작
    echo "🔄 Evaluator: 새 채팅 시작"
    chatgpt_call --mode=new_chat --tab="$CHATGPT_TAB" --project="$CHATGPT_PROJECT_URL" >/dev/null 2>&1
    sleep 2

    # ChatGPT 호출
    local start_time=$(date +%s)
    echo "ChatGPT 호출 중 (Tab $CHATGPT_TAB, timeout: ${TIMEOUT_EVALUATOR}초)..."

    local eval_response
    eval_response=$(chatgpt_call --tab="$CHATGPT_TAB" --timeout="$TIMEOUT_EVALUATOR" --retry "$evaluator_prompt")

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # ChatGPT 오류 감지 (공통 모듈 사용)
    if is_chatgpt_error "$eval_response"; then
        echo "⚠️ ChatGPT 오류 감지: $(get_error_message "$eval_response")"
        save_state "failed" "$eval_file" 0 "$duration"
        return 1
    fi

    # JSON 추출 (공통 모듈 사용)
    local json_only
    json_only=$(extract_json "$eval_response")

    local chars=${#json_only}

    # JSON 검증: 최소 50자 이상이어야 유효한 JSON
    if [[ $chars -lt 50 ]]; then
        echo "⚠️ JSON 추출 실패 (${chars}자 < 50자) - 재시도 필요"
        echo "   원본 응답 길이: ${#eval_response}자"
        save_state "failed" "$eval_file" "$chars" "$duration"
        return 1
    fi

    # 결과 저장
    echo "$json_only" > "$eval_file"

    # 점수 추출 (공통 모듈 사용)
    local score
    score=$(json_get "$json_only" "total_score")

    echo ""
    echo "━━━ Evaluator 결과 ━━━"
    echo "출력 파일: $eval_file"
    echo "JSON 길이: ${chars}자"
    echo "평가 점수: ${score}점"
    echo "소요 시간: ${duration}초"

    # 상태 저장
    save_state "completed" "$eval_file" "$chars" "$duration"

    return 0
}

run_prompt() {
    local sample_file="${SUITES_DIR}/samples/${SECTION}_case01.md"

    if [[ ! -f "$sample_file" ]]; then
        print_prerequisites_error "prompt" "$sample_file" "샘플 파일이 필요합니다"
        save_state "error" "" 0 0
        return 1
    fi

    # 출력 파일 경로
    local prompt_file="${RUNS_DIR}/${SECTION}_v${VERSION}.prompt.md"

    # 메타데이터 추출 (공통 모듈 사용)
    local section_name topic pages body
    section_name=$(parse_front_matter "$sample_file" "section_name")
    body=$(get_body "$sample_file")
    topic=$(extract_topic "$sample_file")
    pages=$(extract_pages "$sample_file")

    # 기본 템플릿 로드
    local base_template
    base_template=$(cat "${PROJECT_DIR}/prompts/writer/challenger.md")

    local tab6_prompt=""

    if [[ $VERSION -eq 1 ]]; then
        echo "━━━ Prompt 생성: ${SECTION} v${VERSION} (초기) ━━━"

        # v1: 기본 템플릿 + 섹션 정보로 프롬프트 생성
        tab6_prompt="당신은 사업계획서 작성 프롬프트 전문가입니다.
아래 기본 템플릿과 섹션 정보를 바탕으로, 해당 섹션에 최적화된 프롬프트를 생성해주세요.

═══════════════════════════════════════════════════════════════
[기본 프롬프트 템플릿]
═══════════════════════════════════════════════════════════════
$base_template

═══════════════════════════════════════════════════════════════
[섹션 정보]
═══════════════════════════════════════════════════════════════
- 섹션명: ${section_name}
- 주제: ${topic}
- 분량: A4 ${pages}장

섹션 상세:
$body

═══════════════════════════════════════════════════════════════
[요청사항] ★ 중요 ★
═══════════════════════════════════════════════════════════════
1. 위 섹션에 최적화된 프롬프트를 생성하세요
2. 해당 섹션의 특성에 맞는 구체적인 지침을 추가하세요
3. 프롬프트 전문만 출력하세요 (설명 없이)
4. 프롬프트 시작은 \"당신은\" 또는 역할 설명으로 시작하세요
5. ★★ 다음 정보를 프롬프트 본문에 반드시 그대로 포함하세요 ★★
   - 주제: ${topic}
   - 섹션명: ${section_name}
   - 분량: A4 ${pages}장
6. 플레이스홀더({topic}, {section_name} 등) 사용 금지 - 위 실제 값을 직접 기입

생성된 프롬프트:"
    else
        # v2+: 이전 평가 기반 개선
        local prev_version=$((VERSION - 1))
        local prev_out_file="${RUNS_DIR}/${SECTION}_v${prev_version}.out.md"
        local prev_eval_file="${RUNS_DIR}/${SECTION}_v${prev_version}.eval.json"

        if [[ ! -f "$prev_out_file" || ! -f "$prev_eval_file" ]]; then
            echo "ERROR: 이전 버전 파일 없음" >&2
            echo "  - 출력: $prev_out_file"
            echo "  - 평가: $prev_eval_file"
            save_state "error" "" 0 0
            return 1
        fi

        echo "━━━ Prompt 개선: ${SECTION} v${VERSION} (v${prev_version} 기반) ━━━"

        # 이전 결과 로드
        local previous_output
        previous_output=$(head -80 "$prev_out_file")
        local previous_eval_json
        previous_eval_json=$(cat "$prev_eval_file")

        # 이전 프롬프트 로드
        local prev_prompt_file="${RUNS_DIR}/${SECTION}_v${prev_version}.prompt.md"
        local current_prompt=""
        if [[ -f "$prev_prompt_file" ]]; then
            current_prompt=$(cat "$prev_prompt_file")
        else
            current_prompt=$(cat "${PROJECT_DIR}/prompts/writer/challenger.md")
        fi

        # 평가 정보 추출 (공통 모듈 사용)
        local eval_score eval_tags eval_weaknesses eval_priority_fix
        eval_score=$(json_get "$previous_eval_json" "total_score")
        eval_tags=$(json_get_array "$previous_eval_json" "defect_tags")
        eval_priority_fix=$(json_get "$previous_eval_json" "priority_fix")

        eval_weaknesses=$(echo "$previous_eval_json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
ws = d.get('weaknesses', [])
for w in ws[:3]:
    print(f\"- 문제: {w.get('issue', '')}\\n  해결: {w.get('fix', '')}\")
" 2>/dev/null)

        tab6_prompt="당신은 사업계획서 프롬프트 개선 전문가입니다.
아래 정보를 분석하여 개선된 새 프롬프트를 생성해주세요.

═══════════════════════════════════════════════════════════════
[1. 이전 프롬프트 (v${prev_version})]
═══════════════════════════════════════════════════════════════
$current_prompt

═══════════════════════════════════════════════════════════════
[2. 이전 프롬프트로 생성된 결과물 (일부)]
═══════════════════════════════════════════════════════════════
$previous_output

═══════════════════════════════════════════════════════════════
[3. 평가 결과]
═══════════════════════════════════════════════════════════════
- 점수: ${eval_score}점
- 결함 태그: ${eval_tags}
- 주요 약점:
${eval_weaknesses}
- 최우선 개선사항: ${eval_priority_fix}

═══════════════════════════════════════════════════════════════
[요청사항] ★ 중요 ★
═══════════════════════════════════════════════════════════════
1. 위 평가 결과의 문제점을 해결할 수 있도록 프롬프트를 개선하세요
2. 결함 태그(${eval_tags})가 발생하지 않도록 명시적 규칙을 추가하세요
3. 개선된 프롬프트 전문만 출력하세요 (설명 없이)
4. 프롬프트 시작은 \"당신은\" 또는 역할 설명으로 시작하세요
5. ★★ 다음 정보를 프롬프트 본문에 반드시 그대로 포함하세요 ★★
   - 주제: ${topic}
   - 섹션명: ${section_name}
   - 분량: A4 ${pages}장
6. 플레이스홀더({topic}, {section_name} 등) 사용 금지 - 위 실제 값을 직접 기입

개선된 프롬프트:"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] ChatGPT 호출 스킵"
        # dry-run 시 기본 템플릿 저장
        echo "$base_template" > "$prompt_file"
        echo "프롬프트 저장: $prompt_file (기본 템플릿)"
        save_state "dry_run" "$prompt_file" 0 0
        return 0
    fi

    # 항상 새 채팅 시작
    echo "🔄 Prompt Generator: 새 채팅 시작"
    chatgpt_call --mode=new_chat --tab="$CHATGPT_TAB" --project="$CHATGPT_PROJECT_URL" >/dev/null 2>&1
    sleep 2

    # ChatGPT 호출
    local start_time=$(date +%s)
    echo "ChatGPT 호출 중 (Tab $CHATGPT_TAB, timeout: ${TIMEOUT_CRITIC}초)..."

    local generated_prompt
    generated_prompt=$(chatgpt_call --tab="$CHATGPT_TAB" --timeout="$TIMEOUT_CRITIC" --retry "$tab6_prompt")

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # ChatGPT 오류 감지 (공통 모듈 사용)
    if is_chatgpt_error "$generated_prompt"; then
        echo "⚠️ ChatGPT 오류 감지: $(get_error_message "$generated_prompt")"
        save_state "failed" "$prompt_file" 0 "$duration"
        return 1
    fi

    local chars=${#generated_prompt}

    echo ""
    echo "━━━ Prompt 결과 ━━━"
    echo "응답 길이: ${chars}자"
    echo "소요 시간: ${duration}초"

    # 품질 검사 (공통 모듈 사용)
    if ! check_response_length "$generated_prompt" 100; then
        echo "⚠️  응답이 너무 짧음 (${chars}자 < 100자)"
        save_state "failed" "$prompt_file" "$chars" "$duration"
        return 1
    fi

    # 프롬프트 파일 저장
    echo "$generated_prompt" > "$prompt_file"

    # 메타데이터 강제 삽입 (GPT가 누락해도 보장)
    prompt_with_info=$(append_required_info "$generated_prompt" "$topic" "$section_name" "$pages")
    echo "$prompt_with_info" > "$prompt_file"
    echo "프롬프트 저장: $prompt_file (메타데이터 포함)"

    # 상태 저장
    save_state "completed" "$prompt_file" "$chars" "$duration"

    return 0
}

# ══════════════════════════════════════════════════════════════
# 반복 실행 함수 (--loop 모드)
# ══════════════════════════════════════════════════════════════

get_eval_score() {
    local eval_file="$1"
    if [[ -f "$eval_file" ]]; then
        python3 -c "import json; print(json.load(open('$eval_file')).get('total_score', 0))" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

run_loop() {
    local start_version="${VERSION:-1}"
    local loop_count="$LOOP_MAX"
    local max_version=$((start_version + loop_count - 1))
    local target_score="$LOOP_TARGET"
    local current_version="$start_version"
    local current_score=0
    local loop_start_time=$(date +%s)

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  🔄 자동 반복 모드 (Loop Mode)                               ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  섹션:      $SECTION"
    echo "║  시작 버전: v${start_version}"
    echo "║  반복 횟수: ${loop_count}회 (v${start_version} ~ v${max_version})"
    echo "║  목표 점수: ${target_score}점"
    echo "║  시작 시간: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    while [[ $current_version -le $max_version ]]; do
        echo ""
        echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
        echo "┃  📝 버전 v${current_version} / v${max_version} 시작                              ┃"
        echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"

        # VERSION 변수 업데이트 (각 step에서 사용)
        VERSION="$current_version"

        # Step 1: Prompt 생성
        echo ""
        echo "━━━ [v${current_version}] Step 1/3: Prompt 생성 ━━━"
        if ! run_prompt; then
            echo "❌ Prompt 생성 실패 (v${current_version})"
            ((current_version++))
            continue
        fi

        # Step 2: Writer 실행
        echo ""
        echo "━━━ [v${current_version}] Step 2/3: Writer 실행 ━━━"
        if ! run_writer; then
            echo "❌ Writer 실행 실패 (v${current_version})"
            ((current_version++))
            continue
        fi

        # Step 3: Evaluator 실행
        echo ""
        echo "━━━ [v${current_version}] Step 3/3: Evaluator 실행 ━━━"
        if ! run_evaluator; then
            echo "❌ Evaluator 실행 실패 (v${current_version})"
            ((current_version++))
            continue
        fi

        # 점수 확인
        local eval_file="${RUNS_DIR}/${SECTION}_v${current_version}.eval.json"
        current_score=$(get_eval_score "$eval_file")

        echo ""
        echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
        echo "┃  ✅ 버전 v${current_version} 완료: ${current_score}점                            ┃"
        echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"

        # 목표 점수 달성 확인
        if [[ $current_score -ge $target_score ]]; then
            echo ""
            echo "🎯 목표 점수 달성! (${current_score}점 >= ${target_score}점)"
            break
        fi

        # 다음 버전으로
        ((current_version++))

        if [[ $current_version -le $max_version ]]; then
            echo ""
            echo "📊 점수 미달 (${current_score}점 < ${target_score}점) → v${current_version} 진행"
        fi
    done

    # 최종 결과
    local loop_end_time=$(date +%s)
    local loop_duration=$((loop_end_time - loop_start_time))
    local loop_minutes=$((loop_duration / 60))
    local loop_seconds=$((loop_duration % 60))

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  🏁 반복 완료                                                ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  섹션:      $SECTION"
    echo "║  최종 버전: v${VERSION}"
    echo "║  최종 점수: ${current_score}점"
    echo "║  목표 점수: ${target_score}점"
    if [[ $current_score -ge $target_score ]]; then
        echo "║  결과:      ✅ 목표 달성"
    else
        echo "║  결과:      ⚠️  최대 버전 도달"
    fi
    echo "║  소요 시간: ${loop_minutes}분 ${loop_seconds}초"
    echo "║  종료 시간: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "╚══════════════════════════════════════════════════════════════╝"

    # 최종 상태 저장
    if [[ $current_score -ge $target_score ]]; then
        return 0
    else
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════
# 메인 실행
# ══════════════════════════════════════════════════════════════

# 로그 시작
exec > >(tee -a "$LOG_FILE") 2>&1

# --loop 모드와 단일 실행 모드 분기
if [[ "$LOOP_MODE" == "true" ]]; then
    # 반복 실행 모드
    run_loop
    exit_code=$?
else
    # 단일 실행 모드
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  Step Runner - Claude Agent                                  ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  시작 시간: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "║  로그 파일: $(basename "$LOG_FILE")"
    echo "║  Section: $SECTION"
    echo "║  Version: v$VERSION"
    echo "║  Step:    $STEP"
    echo "║  Retry:   $RETRY"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    case "$STEP" in
        prompt)
            run_prompt
            ;;
        writer)
            run_writer
            ;;
        evaluator)
            run_evaluator
            ;;
    esac

    exit_code=$?

    echo ""
    echo "━━━ 상태 파일 ━━━"
    cat "$(get_state_file)"
fi

echo ""
echo "━━━ 완료: $(date '+%Y-%m-%d %H:%M:%S') ━━━"
echo "로그 저장: $LOG_FILE"

exit $exit_code
