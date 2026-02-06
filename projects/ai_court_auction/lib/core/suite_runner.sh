#!/bin/bash
# suite_runner.sh - Suite 실행 (Baseline/Challenger 비교용)
# 사용법: ./suite_runner.sh --writer=champion --evaluator=frozen --suite=suite-5

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$LIB_DIR")"

# ══════════════════════════════════════════════════════════════
# 프로젝트 설정 로드
# ══════════════════════════════════════════════════════════════
if [[ -f "${PROJECT_DIR}/config.sh" ]]; then
    source "${PROJECT_DIR}/config.sh"
    # ChatGPT 스크립트 로드
    load_chatgpt 2>/dev/null || true
else
    # Fallback: 기존 방식
    COMMON_DIR="$(dirname "$(dirname "$PROJECT_DIR")")/common"
    source "${COMMON_DIR}/chatgpt.sh" 2>/dev/null
fi

# TAB_PROMPT 호환성 (TAB_CRITIC으로 변경됨)
TAB_PROMPT="${TAB_CRITIC:-5}"

# ══════════════════════════════════════════════════════════════
# 인자 파싱
# ══════════════════════════════════════════════════════════════

WRITER="champion"
EVALUATOR="frozen"
SUITE="suite-5"
DATE=$(date +%Y-%m-%d)
DRY_RUN=false
START_FROM=1
RUNS=5  # 각 샘플당 반복 횟수 (기본 5회)
ENABLE_RESEARCH=false  # 심층 리서치 활성화 (--research 옵션으로 켬)

while [[ $# -gt 0 ]]; do
    case $1 in
        --writer=*)
            WRITER="${1#*=}"
            shift
            ;;
        --evaluator=*)
            EVALUATOR="${1#*=}"
            shift
            ;;
        --suite=*)
            SUITE="${1#*=}"
            shift
            ;;
        --date=*)
            DATE="${1#*=}"
            shift
            ;;
        --start=*)
            START_FROM="${1#*=}"
            shift
            ;;
        --runs=*)
            RUNS="${1#*=}"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --research)
            ENABLE_RESEARCH=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# 경로 설정 (TESTING_DIR 환경변수로 테스트 폴더 지정 가능)
TESTING_DIR="${TESTING_DIR:-$PROJECT_DIR}"
SUITES_DIR="${TESTING_DIR}/suites"
PROMPTS_DIR="${PROJECT_DIR}/prompts"
RUNS_DIR="${TESTING_DIR}/runs/${DATE}"

VARIANT="${WRITER}"  # baseline 또는 challenger 구분
OUTPUT_DIR="${RUNS_DIR}/${VARIANT}"

# ══════════════════════════════════════════════════════════════
# 유틸리티 함수
# ══════════════════════════════════════════════════════════════

# YAML Front Matter 파싱
parse_front_matter() {
    local file="$1"
    local key="$2"

    python3 -c "
import yaml
import re

with open('$file', 'r', encoding='utf-8') as f:
    content = f.read()

# Front Matter 추출
match = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
if match:
    fm = yaml.safe_load(match.group(1))
    keys = '$key'.split('.')
    result = fm
    for k in keys:
        if result and isinstance(result, dict):
            result = result.get(k)
    if result is not None:
        print(result)
" 2>/dev/null
}

# Front Matter 제외한 본문만 추출
get_body() {
    local file="$1"

    python3 -c "
import re

with open('$file', 'r', encoding='utf-8') as f:
    content = f.read()

# Front Matter 제거
body = re.sub(r'^---\s*\n.*?\n---\s*\n', '', content, flags=re.DOTALL)
print(body.strip())
" 2>/dev/null
}

# Suite YAML에서 샘플 목록 추출
get_suite_samples() {
    local suite_file="$1"

    python3 -c "
import yaml

with open('$suite_file', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

samples = data.get('samples', [])
for s in samples:
    print(f\"{s['id']}|{s['file']}\")
" 2>/dev/null
}

# Suite YAML에서 샘플의 research_type 추출
get_sample_research_type() {
    local suite_file="$1"
    local sample_id="$2"

    python3 -c "
import yaml

with open('$suite_file', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

samples = data.get('samples', [])
for s in samples:
    if s.get('id') == '$sample_id':
        rt = s.get('research_type', '')
        if rt:
            print(rt)
        break
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 리서치 관련 함수
# ══════════════════════════════════════════════════════════════

RESEARCH_DIR="${PROJECT_DIR}/research"

# 리서치 결과 파일 경로 반환
get_research_file() {
    local research_type="$1"
    echo "${RESEARCH_DIR}/${research_type}.md"
}

# 리서치 결과가 존재하는지 확인
has_research_result() {
    local research_type="$1"
    local research_file
    research_file=$(get_research_file "$research_type")

    if [[ -f "$research_file" ]]; then
        # 파일이 있고 내용이 최소 100자 이상이면 유효한 리서치로 간주
        local size
        size=$(wc -c < "$research_file" | tr -d ' ')
        [[ "$size" -gt 100 ]]
    else
        return 1
    fi
}

# 리서치 결과 로드
load_research_result() {
    local research_type="$1"
    local research_file
    research_file=$(get_research_file "$research_type")

    if [[ -f "$research_file" ]]; then
        cat "$research_file"
    fi
}

# 리서치 프롬프트 생성
generate_research_prompt() {
    local research_type="$1"
    local topic="$2"

    case "$research_type" in
        market_size)
            echo "한국 부동산 경매 시장 규모, 성장률, 주요 통계를 심층 분석해주세요.
다음 항목을 반드시 포함:
- 연간 경매 진행 건수 및 매각대금 총액 (최근 3년)
- 경매 참여자 수 및 증감 추이
- 낙찰률 및 낙찰가율 통계
- AI/프롭테크 시장 성장률 (CAGR)
- 개인 투자자 vs 법인 투자자 비율

모든 수치에 출처(기관명, 연도, URL)를 명시해주세요.
주제: $topic"
            ;;
        competitive)
            echo "한국 부동산 경매 시장의 경쟁 환경과 기존 서비스를 분석해주세요.
다음 항목을 반드시 포함:
- 주요 경매정보 서비스 (지지옥션, 굿옥션, 법원경매정보 등) 비교
- 각 서비스의 장단점과 시장 점유율
- AI 기반 부동산 서비스 현황
- 경매 컨설팅/전문가 서비스 시장 규모
- 미충족 니즈 (Pain Point)

모든 정보에 출처를 명시해주세요.
주제: $topic"
            ;;
        customer_needs)
            echo "한국 부동산 경매 참여자의 니즈와 Pain Point를 분석해주세요.
다음 항목을 반드시 포함:
- 경매 참여자 유형별 특성 (초보/경험자, 개인/법인)
- 경매 진행 시 주요 어려움과 실패 원인
- 정보 탐색 행동 및 의사결정 과정
- 기존 서비스에 대한 불만 사항
- 희망하는 서비스/기능

관련 설문조사나 통계 자료의 출처를 명시해주세요.
주제: $topic"
            ;;
        *)
            echo "$topic 관련 시장 현황, 경쟁 환경, 고객 니즈를 심층 분석해주세요.
모든 수치와 정보에 출처(기관명, 연도, URL)를 명시해주세요."
            ;;
    esac
}

# 리서치 실행 (Tab1 심층 리서치)
run_research() {
    local research_type="$1"
    local topic="$2"

    # 이미 결과가 있으면 스킵
    if has_research_result "$research_type"; then
        log_info "Research already exists: $research_type"
        return 0
    fi

    # 리서치 디렉토리 생성
    mkdir -p "$RESEARCH_DIR"

    local research_prompt
    research_prompt=$(generate_research_prompt "$research_type" "$topic")

    local research_file
    research_file=$(get_research_file "$research_type")

    log_info "Starting deep research: $research_type (Tab $TAB_RESEARCH)"

    if type chatgpt_call &>/dev/null; then
        local research_timeout
        research_timeout=$(get_timeout_for "research")

        # 심층 리서치 실행 (Tab1)
        local response
        response=$(chatgpt_call --mode=research --tab="$TAB_RESEARCH" --timeout="$research_timeout" "$research_prompt")

        if [[ -n "$response" && ${#response} -gt 100 ]]; then
            echo "$response" > "$research_file"
            log_info "Research saved: $research_file (${#response} chars)"
            return 0
        else
            log_warn "Research response too short or empty"
            return 1
        fi
    else
        log_error "ChatGPT not available - chatgpt_call function not found"
        return 1
    fi
}

# 리서치 블록 포맷팅
format_research_block() {
    local research_type="$1"
    local research_content
    research_content=$(load_research_result "$research_type")

    if [[ -n "$research_content" ]]; then
        echo "
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[심층 리서치 결과] ★ 본문에 반영 필수 ★
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$research_content
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
}

# Writer 프롬프트 로드 및 변수 치환
load_writer_prompt() {
    local writer_file="${PROMPTS_DIR}/writer/${WRITER}.md"
    local section_name="$1"
    local section_detail="$2"
    local topic="$3"
    local pages="$4"
    local previous_feedback="$5"  # 이전 차수 평가 피드백 (선택)
    local research_block="$6"     # 리서치 결과 블록 (선택)

    if [[ ! -f "$writer_file" ]]; then
        echo "ERROR: Writer prompt not found: $writer_file" >&2
        return 1
    fi

    local template
    template=$(cat "$writer_file")

    # 변수 치환
    template="${template//\{topic\}/$topic}"
    template="${template//\{section_name\}/$section_name}"
    template="${template//\{section_detail\}/$section_detail}"
    template="${template//\{pages\}/$pages}"
    template="${template//\{prior_summary_block\}/}"
    # 리서치 블록 치환 (있으면 삽입, 없으면 빈 문자열)
    if [[ -n "$research_block" ]]; then
        template="${template//\{research_block\}/$research_block}"
    else
        template="${template//\{research_block\}/}"
    fi

    # 이전 차수 피드백이 있으면 추가
    if [[ -n "$previous_feedback" ]]; then
        template="$template

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[이전 차수 평가 피드백] ★ 반드시 반영 ★
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$previous_feedback

위 피드백의 문제점을 반드시 개선하여 작성하세요."
    fi

    echo "$template"
}

# Evaluator 프롬프트 로드 및 변수 치환
load_evaluator_prompt() {
    local evaluator_file="${PROMPTS_DIR}/evaluator/${EVALUATOR}.md"
    local section_name="$1"
    local content="$2"

    if [[ ! -f "$evaluator_file" ]]; then
        echo "ERROR: Evaluator prompt not found: $evaluator_file" >&2
        return 1
    fi

    local template
    template=$(cat "$evaluator_file")

    # 변수 치환
    template="${template//\{section_name\}/$section_name}"
    template="${template//\{section_content\}/$content}"

    echo "$template"
}

# ══════════════════════════════════════════════════════════════
# Challenger 프롬프트 개선 (Tab5 사용)
# ══════════════════════════════════════════════════════════════

# Tab5를 통해 새로운 Challenger 프롬프트 생성
improve_challenger_prompt() {
    local run_num="$1"
    local previous_output="$2"
    local previous_eval_json="$3"
    local section_id="$4"  # 섹션 ID (챕터 변경 감지용)

    local challenger_prompt_file="${PROMPTS_DIR}/writer/challenger.md"
    local version_dir="${PROMPTS_DIR}/challenger"
    local version_file="${version_dir}/v${run_num}.md"
    local log_file="${version_dir}/v${run_num}.log"

    mkdir -p "$version_dir"

    # 현재 프롬프트 로드
    local current_prompt=""
    if [[ -f "$challenger_prompt_file" ]]; then
        current_prompt=$(cat "$challenger_prompt_file")
    fi

    # 평가 정보 추출
    local eval_score eval_tags eval_weaknesses eval_priority_fix
    eval_score=$(echo "$previous_eval_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('total_score', 0))" 2>/dev/null)
    eval_tags=$(echo "$previous_eval_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(', '.join(d.get('defect_tags', [])))" 2>/dev/null)
    eval_weaknesses=$(echo "$previous_eval_json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
ws = d.get('weaknesses', [])
for w in ws[:3]:
    print(f\"- 문제: {w.get('issue', '')}\\n  해결: {w.get('fix', '')}\")
" 2>/dev/null)
    eval_priority_fix=$(echo "$previous_eval_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('priority_fix', ''))" 2>/dev/null)

    # Tab5에 보낼 프롬프트 개선 요청 생성
    local critic_prompt
    critic_prompt=$(cat <<CRITIC_EOF
당신은 사업계획서 프롬프트 개선 전문가입니다.
아래 정보를 분석하여 개선된 새 프롬프트를 생성해주세요.

═══════════════════════════════════════════════════════════════
[1. 이전 프롬프트 (v$((run_num - 1)))]
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
4. 프롬프트 시작은 "당신은" 또는 역할 설명으로 시작하세요
5. 기존 프롬프트의 구조({topic}, {section_name}, {section_detail}, {pages} 변수)는 유지하세요

개선된 프롬프트:
CRITIC_EOF
)

    # Tab5 호출 (재시도 기능 사용)
    local improved_prompt
    if [[ -f "$CHATGPT_SCRIPT" ]]; then
        source "$CHATGPT_SCRIPT"
        local win="${CHATGPT_WINDOW}"
        local tab="${TAB_PROMPT}"

        log_info "Calling Tab5 (Prompt Critic, Section $section_id) with retry..."
        improved_prompt=$(chatgpt_call --tab="$tab" --timeout="$TIMEOUT_CRITIC" --retry --section="$section_id" "$critic_prompt")
    else
        log_error "ChatGPT not available - Tab5 cannot be called"
        return 1
    fi

    # 빈 응답 체크
    if [[ -z "$improved_prompt" || ${#improved_prompt} -lt 100 ]]; then
        echo "    WARNING: Tab5 응답이 너무 짧음, 기존 프롬프트 유지" >&2
        return 1
    fi

    # 버전 파일 저장
    cat > "$version_file" <<VERSION_EOF
# Challenger Prompt - v${run_num}
# Generated: $(date +"%Y-%m-%d %H:%M:%S")
# Based on: v$((run_num - 1)) evaluation (score: ${eval_score})
# Defects addressed: ${eval_tags}

$improved_prompt
VERSION_EOF

    echo "    Saved: $version_file" >&2

    # 로그 저장
    cat > "$log_file" <<LOG_EOF
# Challenger v${run_num} Generation Log
# Generated: $(date +"%Y-%m-%d %H:%M:%S")

## Input
- Previous version: v$((run_num - 1))
- Previous score: ${eval_score}
- Defect tags: ${eval_tags}

## Evaluation Summary
${eval_weaknesses}

Priority fix: ${eval_priority_fix}

## Prompt Request (sent to Tab5)
$critic_prompt
LOG_EOF

    echo "    Saved: $log_file" >&2

    # challenger.md 업데이트
    echo "$improved_prompt" > "$challenger_prompt_file"
    echo "    Updated: $challenger_prompt_file" >&2

    return 0
}

# ══════════════════════════════════════════════════════════════
# 메인 실행 로직
# ══════════════════════════════════════════════════════════════

run_sample() {
    local sample_id="$1"
    local sample_file="$2"
    local previous_feedback="$3"  # 이전 차수 평가 피드백 (선택)

    local full_path="${SUITES_DIR}/${sample_file}"

    if [[ ! -f "$full_path" ]]; then
        echo "ERROR: Sample file not found: $full_path" >&2
        return 1
    fi

    echo "  Processing: $sample_id" >&2

    # Front Matter에서 메타데이터 추출
    local section_name topic
    section_name=$(parse_front_matter "$full_path" "section_name")
    local section_id
    section_id=$(parse_front_matter "$full_path" "section")

    # research_type 추출 (샘플 파일의 Front Matter에서)
    local research_type
    research_type=$(parse_front_matter "$full_path" "research_type")

    # Body에서 입력 조건 추출
    local body
    body=$(get_body "$full_path")

    # 주제 추출 (## 주제 다음 줄)
    topic=$(echo "$body" | grep -A1 "^## 주제" | tail -1)

    # 분량 추출
    local pages
    pages=$(echo "$body" | grep -oE "A4 [0-9.]+" | head -1 | grep -oE "[0-9.]+")
    pages="${pages:-1.5}"

    # 리서치 실행 및 블록 생성 (--research 옵션 필요)
    local research_block=""
    if [[ "$ENABLE_RESEARCH" == "true" && -n "$research_type" ]]; then
        log_info "Research required: $research_type"

        # 리서치 실행 (이미 있으면 스킵)
        run_research "$research_type" "$topic"

        # 리서치 결과 블록 생성
        research_block=$(format_research_block "$research_type")

        if [[ -n "$research_block" ]]; then
            log_info "Research block loaded (${#research_block} chars)"
        fi
    elif [[ -n "$research_type" ]]; then
        log_info "Research skipped (use --research to enable): $research_type"
    fi

    # Writer 프롬프트 생성 (이전 피드백 + 리서치 블록 포함)
    local writer_prompt
    writer_prompt=$(load_writer_prompt "$section_name" "$body" "$topic" "$pages" "$previous_feedback" "$research_block")

    # 출력 파일 경로
    local out_file="${OUTPUT_DIR}/${sample_id}.out.md"
    local eval_file="${OUTPUT_DIR}/${sample_id}.eval.json"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] Would generate: $out_file" >&2
        echo "  [DRY-RUN] Writer prompt length: ${#writer_prompt}" >&2
        return 0
    fi

    # ChatGPT로 Writer 실행 (통합 chatgpt_call 사용)
    local writer_response
    local writer_tab
    writer_tab=$(get_writer_tab "$WRITER")
    local writer_timeout
    writer_timeout=$(get_timeout_for "writer")

    if type chatgpt_call &>/dev/null; then
        log_info "Calling Writer (Tab $writer_tab, Section $section_id) with retry..."
        writer_response=$(chatgpt_call --tab="$writer_tab" --timeout="$writer_timeout" --retry --section="$section_id" "$writer_prompt")
    else
        log_error "ChatGPT not available - chatgpt_call function not found"
        return 1
    fi

    # Writer 응답 저장
    echo "$writer_response" > "$out_file"
    echo "  Saved: $out_file" >&2

    # Evaluator 프롬프트 생성
    local evaluator_prompt
    evaluator_prompt=$(load_evaluator_prompt "$section_name" "$writer_response")

    # ChatGPT로 Evaluator 실행 (통합 chatgpt_call 사용)
    local eval_response
    local eval_tab="$TAB_EVALUATOR"
    local eval_timeout
    eval_timeout=$(get_timeout_for "evaluator")
    local base_project_url=""

    if type chatgpt_call &>/dev/null; then
        # Evaluator 새 컨텍스트 시작 (공정한 평가를 위해)
        if [[ "$EVALUATOR_NEW_CHAT" == "true" ]]; then
            log_info "Starting new chat for Evaluator (Tab $eval_tab)..."

            # 프로젝트 URL 감지 (설정되지 않은 경우 현재 Tab URL에서 추출)
            local project_url="$EVALUATOR_PROJECT_URL"
            if [[ -z "$project_url" ]]; then
                project_url=$(osascript -e "tell application \"Google Chrome\" to URL of tab $eval_tab of window $CHATGPT_WINDOW" 2>/dev/null)
            fi

            # 프로젝트 URL인지 확인 (project 또는 g/g-p 패턴)
            if [[ "$project_url" == *"/project/"* ]] || [[ "$project_url" == *"/g/g-p"* ]]; then
                # 프로젝트 기본 URL 추출 (채팅 ID 제거)
                base_project_url=$(echo "$project_url" | sed 's|/c/[^/]*$||')
                log_debug "Project detected: $base_project_url"
                # 새 채팅 시작 (chatgpt_call --mode=new_chat 사용)
                chatgpt_call --mode=new_chat --tab="$eval_tab" --project="$base_project_url" >/dev/null 2>&1
            else
                chatgpt_call --mode=new_chat --tab="$eval_tab" >/dev/null 2>&1
            fi
            sleep 1
        fi

        log_info "Calling Evaluator (Frozen, Tab $eval_tab) with retry..."
        eval_response=$(chatgpt_call --tab="$eval_tab" --timeout="$eval_timeout" --retry --project="$base_project_url" "$evaluator_prompt")
    else
        log_error "ChatGPT not available - chatgpt_call function not found"
        return 1
    fi

    # JSON 추출 및 저장
    local json_only
    json_only=$(echo "$eval_response" | python3 -c "
import re
import sys
content = sys.stdin.read()
match = re.search(r'\`\`\`json\s*([\s\S]*?)\`\`\`', content)
if match:
    print(match.group(1).strip())
else:
    # 직접 JSON 찾기
    match = re.search(r'\{[\s\S]*\}', content)
    if match:
        print(match.group(0))
    else:
        print('{}')
" 2>/dev/null)

    echo "$json_only" > "$eval_file"
    echo "  Saved: $eval_file" >&2

    # 점수 출력
    local score
    score=$(echo "$json_only" | python3 -c "import json,sys; print(json.load(sys.stdin).get('total_score', 0))" 2>/dev/null)
    echo "  Score: $score" >&2
}

run_suite() {
    local suite_file="${SUITES_DIR}/${SUITE}.yaml"

    if [[ ! -f "$suite_file" ]]; then
        echo "ERROR: Suite file not found: $suite_file" >&2
        exit 1
    fi

    echo "╔══════════════════════════════════════════════╗"
    echo "║         Suite Runner                         ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    echo "Suite:     $SUITE"
    echo "Writer:    $WRITER"
    echo "Evaluator: $EVALUATOR"
    echo "Date:      $DATE"
    echo "Output:    $OUTPUT_DIR"
    echo "Start:     $START_FROM"
    echo "Runs:      $RUNS (각 샘플당 반복 횟수)"
    echo ""

    # 출력 디렉토리 생성
    mkdir -p "$OUTPUT_DIR"

    # 샘플 목록 가져오기
    local samples
    samples=$(get_suite_samples "$suite_file")

    local total=0
    local success=0

    echo "Processing samples (${RUNS}회 반복)..."
    echo ""

    local current=0
    while IFS='|' read -r sample_id sample_file; do
        if [[ -n "$sample_id" ]]; then
            ((current++))
            if [[ $current -lt $START_FROM ]]; then
                echo "  Skipping: $sample_id (sample $current < start $START_FROM)"
                echo ""
                continue
            fi

            # 각 샘플을 RUNS번 반복 실행 (v1, v2, v3...)
            local previous_feedback=""
            local previous_output=""
            local previous_eval_json=""

            # 샘플 파일에서 section_id 추출 (챕터 변경 감지용)
            local full_path="${SUITES_DIR}/${sample_file}"
            local section_id
            section_id=$(parse_front_matter "$full_path" "section")

            for run_num in $(seq 1 $RUNS); do
                ((total++))
                local run_sample_id="${sample_id}_v${run_num}"
                echo "  [v$run_num/$RUNS] Processing: $sample_id (section: $section_id)"

                # Challenger 모드: v2부터 Tab5로 프롬프트 개선
                if [[ "$WRITER" == "challenger" && $run_num -gt 1 && -n "$previous_output" ]]; then
                    echo "    → Tab5: 프롬프트 v${run_num} 생성 중..." >&2
                    improve_challenger_prompt "$run_num" "$previous_output" "$previous_eval_json" "$section_id"
                fi

                # 이전 피드백을 포함하여 실행
                if run_sample "$run_sample_id" "$sample_file" "$previous_feedback"; then
                    ((success++))
                fi

                # 다음 차수를 위해 결과 저장
                local out_file="${OUTPUT_DIR}/${run_sample_id}.out.md"
                local eval_file="${OUTPUT_DIR}/${run_sample_id}.eval.json"

                if [[ -f "$out_file" ]]; then
                    previous_output=$(head -80 "$out_file")
                fi

                if [[ -f "$eval_file" ]]; then
                    previous_eval_json=$(cat "$eval_file")

                    # 피드백 추출
                    previous_feedback=$(python3 -c "
import json
try:
    with open('$eval_file', 'r') as f:
        data = json.load(f)

    score = data.get('total_score', 0)
    tags = data.get('defect_tags', [])
    weaknesses = data.get('weaknesses', [])
    priority_fix = data.get('priority_fix', '')

    feedback = f'이전 점수: {score}점\n'

    if tags:
        feedback += f'결함 태그: {\", \".join(tags)}\n'

    if weaknesses:
        feedback += '주요 약점:\n'
        for w in weaknesses[:3]:
            issue = w.get('issue', '')[:150]
            fix = w.get('fix', '')[:150]
            feedback += f'- 문제: {issue}\n  해결: {fix}\n'

    if priority_fix:
        feedback += f'최우선 개선: {priority_fix[:200]}'

    print(feedback)
except Exception as e:
    print('')
" 2>/dev/null)
                fi
            done
            echo ""
        fi
    done <<< "$samples"

    echo "════════════════════════════════════════"
    echo "Completed: $success / $total runs (${RUNS} runs × samples)"
    echo "Results saved to: $OUTPUT_DIR"

    # 요약 JSON 생성
    generate_summary
}

generate_summary() {
    local summary_file="${OUTPUT_DIR}/summary.json"

    python3 -c "
import json
import os
import re
from glob import glob
from collections import defaultdict

output_dir = '$OUTPUT_DIR'
runs = $RUNS
eval_files = glob(os.path.join(output_dir, '*.eval.json'))

# 샘플별로 버전 결과를 그룹화
sample_versions = defaultdict(list)
all_tags = []

for ef in eval_files:
    filename = os.path.basename(ef).replace('.eval.json', '')
    # s1_2_v1 -> s1_2
    match = re.match(r'(.+)_v(\d+)', filename)
    if match:
        sample_id = match.group(1)
        version_num = int(match.group(2))
    else:
        sample_id = filename
        version_num = 1

    try:
        with open(ef, 'r') as f:
            data = json.load(f)
        score = data.get('total_score', 0)
        tags = data.get('defect_tags', [])
        all_tags.extend(tags)
        sample_versions[sample_id].append({
            'version': version_num,
            'score': score,
            'tags': tags
        })
    except:
        sample_versions[sample_id].append({
            'version': version_num,
            'score': 0,
            'tags': [],
            'error': 'parse_failed'
        })

# 샘플별 평균 계산
results = []
total_avg_score = 0

for sample_id, version_list in sorted(sample_versions.items()):
    scores = [v['score'] for v in version_list]
    avg_score = sum(scores) / len(scores) if scores else 0
    min_score = min(scores) if scores else 0
    max_score = max(scores) if scores else 0
    variance = sum((s - avg_score) ** 2 for s in scores) / len(scores) if scores else 0

    total_avg_score += avg_score
    results.append({
        'sample_id': sample_id,
        'versions': len(version_list),
        'avg_score': round(avg_score, 2),
        'min_score': min_score,
        'max_score': max_score,
        'variance': round(variance, 2),
        'all_versions': version_list
    })

overall_avg = total_avg_score / len(results) if results else 0

# 태그 빈도 계산
from collections import Counter
tag_freq = dict(Counter(all_tags))

summary = {
    'suite': '$SUITE',
    'writer': '$WRITER',
    'evaluator': '$EVALUATOR',
    'date': '$DATE',
    'runs_per_sample': runs,
    'sample_count': len(results),
    'avg_score': round(overall_avg, 2),
    'total_tags': len(all_tags),
    'tag_frequency': tag_freq,
    'results': results
}

with open('$summary_file', 'w') as f:
    json.dump(summary, f, indent=2, ensure_ascii=False)

print(f'Summary saved: $summary_file')
print(f'Average score: {avg_score:.2f}')
print(f'Total defect tags: {len(all_tags)}')
"
}

# ══════════════════════════════════════════════════════════════
# 실행
# ══════════════════════════════════════════════════════════════

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_suite
fi
