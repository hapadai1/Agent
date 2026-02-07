#!/bin/bash
# actions.sh - Claude Agent용 액션 함수
#
# 사용법:
#   source core/agent/actions.sh
#   agent_regenerate "s1_2" "v3" "new_chat"
#   agent_evaluate "runs/.../s1_2_v3.out.md"

# ══════════════════════════════════════════════════════════════
# 경로 설정
# ══════════════════════════════════════════════════════════════

# 프로젝트 루트 찾기
_find_agent_root() {
    local dir="$(pwd)"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.rai" && -d "$dir/core/agent" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    # fallback
    echo "/Users/tony/Desktop/src/My/Agent"
}

AGENT_ROOT="$(_find_agent_root)"
ACTIONS_DIR="${AGENT_ROOT}/core/agent"
AI_PROJECT_DIR="${AGENT_ROOT}/projects/ai_court_auction"

# 의존성 로드 (PROJECT_DIR 보존)
_saved_project_dir="$AI_PROJECT_DIR"
source "${AI_PROJECT_DIR}/config.sh" 2>/dev/null || true
PROJECT_DIR="$_saved_project_dir"

source "${AGENT_ROOT}/common/chatgpt.sh" 2>/dev/null || true
source "${ACTIONS_DIR}/logger.sh" 2>/dev/null || true
source "${ACTIONS_DIR}/monitor.sh" 2>/dev/null || true

# ══════════════════════════════════════════════════════════════
# 리서치 로드
# ══════════════════════════════════════════════════════════════

# 섹션별 리서치 결과 로드
# research/responses/{section}_*.md 패턴 파일 병합
agent_load_research() {
    local section="$1"  # s1_2
    local research_dir="${PROJECT_DIR}/research/responses"

    if [[ ! -d "$research_dir" ]]; then
        echo ""
        return
    fi

    local result=""
    local count=0

    # s1_2_*.md 패턴 파일 찾기
    for file in "${research_dir}/${section}_"*.md; do
        [[ -f "$file" ]] || continue
        ((count++))
        local filename=$(basename "$file")
        result+="
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[리서치 자료: ${filename}]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$(cat "$file")

"
    done

    if [[ $count -gt 0 ]]; then
        echo "[제공 근거 자료 - ${count}건]
${result}"
    else
        echo ""
    fi
}

# ══════════════════════════════════════════════════════════════
# 프롬프트 로드
# ══════════════════════════════════════════════════════════════

# 프롬프트 파일 + 섹션 정보 조합
agent_load_prompt() {
    local writer="$1"       # challenger / champion
    local section="$2"      # s1_2
    local sample_file="$3"  # 샘플 파일 경로 (옵션)

    local prompt_file="${PROJECT_DIR}/prompts/writer/${writer}.md"

    if [[ ! -f "$prompt_file" ]]; then
        echo "ERROR: Prompt file not found: $prompt_file" >&2
        return 1
    fi

    # 프롬프트 템플릿 읽기
    local template
    template=$(cat "$prompt_file")

    # 샘플 파일에서 변수 추출 (있으면)
    local topic="AI 기반 법원 경매 물건 분석 및 투자 추천 솔루션"
    local section_name="1-2. 창업아이템 배경 및 필요성"
    local section_detail=""
    local pages="2"

    if [[ -n "$sample_file" && -f "$sample_file" ]]; then
        # YAML front matter에서 추출
        section_name=$(python3 -c "
import yaml, re
with open('$sample_file', 'r') as f:
    content = f.read()
match = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
if match:
    fm = yaml.safe_load(match.group(1))
    print(fm.get('section_name', ''))
" 2>/dev/null)

        # 본문에서 세부 지침 추출
        section_detail=$(python3 -c "
import re
with open('$sample_file', 'r') as f:
    content = f.read()
# Front matter 제거 후 본문 추출
body = re.sub(r'^---\s*\n.*?\n---\s*\n', '', content, flags=re.DOTALL)
print(body.strip())
" 2>/dev/null)
    fi

    # 리서치 결과 로드
    local research_content
    research_content=$(agent_load_research "$section")

    # 변수 치환
    local prompt="$template"
    prompt="${prompt//\{topic\}/$topic}"
    prompt="${prompt//\{section_name\}/$section_name}"
    prompt="${prompt//\{section_detail\}/$section_detail}"
    prompt="${prompt//\{pages\}/$pages}"
    prompt="${prompt//\{prior_summary_block\}/}"
    prompt="${prompt//\{research_block\}/$research_content}"

    echo "$prompt"
}

# ══════════════════════════════════════════════════════════════
# 재생성
# ══════════════════════════════════════════════════════════════

agent_regenerate() {
    local section="$1"      # s1_2
    local version="$2"      # v3
    local mode="${3:-new_chat}"  # new_chat / same_chat
    local writer="${4:-challenger}"

    local tab
    if [[ "$writer" == "challenger" ]]; then
        tab="${TAB_WRITER_CHALLENGER:-3}"
    else
        tab="${TAB_WRITER_CHAMPION:-2}"
    fi

    local win="${CHATGPT_WINDOW:-1}"
    local timeout="${TIMEOUT_WRITER:-180}"
    local date=$(date +%Y-%m-%d)
    local output_dir="${PROJECT_DIR}/testing/runs/${date}/${writer}"
    local output_file="${output_dir}/${section}_${version}.out.md"
    local sample_file="${PROJECT_DIR}/testing/suites/samples/${section}_case01.md"

    mkdir -p "$output_dir"

    echo "[Agent] 재생성 시작: section=$section, version=$version, mode=$mode, tab=$tab"

    # ═══ Step 1: Tab 상태 확인 ═══
    echo "[Agent] Step 1: Tab 상태 확인..."
    local tab_status
    tab_status=$(agent_check_tab "$tab" "$win")
    echo "[Agent] Tab 상태: $tab_status"

    if [[ "$tab_status" == TAB_NOT_FOUND* ]] || [[ "$tab_status" == WINDOW_NOT_FOUND* ]]; then
        echo "[Agent] ERROR: Tab을 찾을 수 없음"
        log_action "claude" "regenerate_fail" "\"reason\":\"tab_not_found\""
        return 1
    fi

    if [[ "$tab_status" == NOT_CHATGPT* ]]; then
        echo "[Agent] WARNING: Tab이 ChatGPT가 아님"
    fi

    # ═══ Step 2: GPT 상태 확인 ═══
    echo "[Agent] Step 2: GPT 상태 확인..."
    local gpt_status
    gpt_status=$(agent_check_gpt_status "$tab" "$win")
    echo "[Agent] GPT 상태: $gpt_status"

    if [[ "$gpt_status" == "STREAMING" ]]; then
        echo "[Agent] WARNING: GPT가 이미 응답 중. 완료 대기..."
        agent_wait_for_response "$tab" 60 "$win"
    fi

    # ═══ Step 3: 프롬프트 로드 ═══
    echo "[Agent] Step 3: 프롬프트 로드..."
    local prompt
    prompt=$(agent_load_prompt "$writer" "$section" "$sample_file")

    if [[ -z "$prompt" ]]; then
        echo "[Agent] ERROR: 프롬프트 로드 실패"
        return 1
    fi
    echo "[Agent] 프롬프트 로드 완료 (${#prompt} chars)"

    # 프롬프트 저장
    local prompt_file="${output_dir}/${section}_${version}.prompt.md"
    echo "$prompt" > "$prompt_file"
    echo "[Agent] 프롬프트 저장: $prompt_file"

    # 로그 기록
    log_action "claude" "regenerate_start" \
        "\"section\":\"$section\"" \
        "\"version\":\"$version\"" \
        "\"mode\":\"$mode\"" \
        "\"tab\":$tab"

    # ═══ Step 4: ChatGPT 호출 ═══
    echo "[Agent] Step 4: ChatGPT 호출..."

    # 프로젝트 URL (plan 프로젝트 내에서 새 채팅)
    local project_url="${WRITER_PROJECT_URL:-$PLAN_PROJECT_URL}"

    local response
    if [[ "$mode" == "new_chat" ]]; then
        response=$(chatgpt_call --mode=new_chat --tab="$tab" --timeout="$timeout" --project="$project_url" "$prompt")
    else
        response=$(chatgpt_call --mode=continue --tab="$tab" --timeout="$timeout" "$prompt")
    fi

    local exit_code=$?

    # ═══ Step 5: 결과 확인 + 자동 복구 ═══
    echo "[Agent] Step 5: 결과 확인..."

    # [비활성화] 자동 복구 로직 - chatgpt_call의 send-button 감지로 대체됨
    # if [[ -z "$response" ]] || [[ "$response" == *"no response"* ]] || [[ ${#response} -lt 200 ]]; then
    #     echo "[Agent] ⚠️ chatgpt_call 결과 부족. 자동 복구 시도..."
    #     local diag
    #     diag=$(agent_diagnose_failure "$tab" "$win")
    #     echo "[Agent] 진단 결과: $diag"
    #     local recovered_response
    #     recovered_response=$(agent_auto_recover "$tab" "$win" 3)
    #     if [[ -n "$recovered_response" && ${#recovered_response} -gt 200 ]]; then
    #         echo "[Agent] ✅ 자동 복구 성공!"
    #         response="$recovered_response"
    #     else
    #         echo "[Agent] ❌ 자동 복구 실패. 수동 확인 필요"
    #         log_action "claude" "regenerate_fail" "\"reason\":\"auto_recover_failed\",\"diagnosis\":\"$diag\""
    #     fi
    # fi

    # 결과 저장
    echo "$response" > "$output_file"
    local char_count=${#response}

    echo "[Agent] 결과 저장: $output_file ($char_count chars)"

    # 로그 기록
    log_generate "$output_file" "$char_count"

    # ═══ Step 6: 결과 판정 ═══
    if [[ $char_count -lt 500 ]]; then
        echo "[Agent] WARNING: 결과가 너무 짧음 ($char_count chars)"
        log_action "claude" "regenerate_short" "\"chars\":$char_count"
        return 1
    fi

    echo "[Agent] 재생성 완료"
    echo "$output_file"
}

# ══════════════════════════════════════════════════════════════
# 평가
# ══════════════════════════════════════════════════════════════

agent_evaluate() {
    local output_file="$1"

    if [[ ! -f "$output_file" ]]; then
        echo "[Agent] ERROR: Output file not found: $output_file" >&2
        return 1
    fi

    local tab="${TAB_EVALUATOR:-4}"
    local timeout="${TIMEOUT_EVALUATOR:-120}"

    # 평가 결과 파일 경로
    local eval_file="${output_file%.out.md}.eval.json"

    # 평가 프롬프트 로드
    local eval_prompt_file="${PROJECT_DIR}/prompts/evaluator/frozen.md"
    if [[ ! -f "$eval_prompt_file" ]]; then
        echo "[Agent] ERROR: Evaluator prompt not found" >&2
        return 1
    fi

    local eval_template
    eval_template=$(cat "$eval_prompt_file")

    # 생성된 내용 읽기
    local content
    content=$(cat "$output_file")

    # 평가 프롬프트 조합
    local eval_prompt="${eval_template}

[평가 대상 문서]
${content}"

    echo "[Agent] 평가 시작: $output_file"

    # 로그 기록
    log_action "claude" "evaluate_start" "\"file\":\"$output_file\""

    local win="${CHATGPT_WINDOW:-1}"

    # 프로젝트 URL (plan 프로젝트 내에서 새 채팅)
    local project_url="${EVALUATOR_PROJECT_URL:-$PLAN_PROJECT_URL}"

    local response
    response=$(chatgpt_call --mode=new_chat --tab="$tab" --timeout="$timeout" --project="$project_url" "$eval_prompt")

    local exit_code=$?

    # [비활성화] 자동 복구 로직 - chatgpt_call의 send-button 감지로 대체됨
    # if [[ -z "$response" ]] || [[ "$response" == *"no response"* ]] || [[ ${#response} -lt 50 ]]; then
    #     echo "[Agent] ⚠️ 평가 응답 부족. 자동 복구 시도..."
    #     local diag
    #     diag=$(agent_diagnose_failure "$tab" "$win")
    #     echo "[Agent] 진단: $diag"
    #     local recovered
    #     recovered=$(agent_auto_recover "$tab" "$win" 3)
    #     if [[ -n "$recovered" && ${#recovered} -gt 50 ]]; then
    #         echo "[Agent] ✅ 복구 성공!"
    #         response="$recovered"
    #     fi
    # fi

    # 결과 저장
    echo "$response" > "$eval_file"

    # 점수 파싱 시도
    local score=0
    local defect_count=0
    if echo "$response" | jq empty 2>/dev/null; then
        score=$(echo "$response" | jq -r '.total_score // .score // 0' 2>/dev/null)
        defect_count=$(echo "$response" | jq -r '.defect_tags | length' 2>/dev/null)
    fi

    echo "[Agent] 평가 결과 저장: $eval_file (score=$score, defects=$defect_count)"

    # 로그 기록
    log_evaluate "$eval_file" "$score" "$defect_count"

    if [[ $exit_code -ne 0 ]]; then
        echo "[Agent] WARNING: 평가 호출 실패"
        return 1
    fi

    echo "[Agent] 평가 완료"
    echo "$eval_file"
}

# ══════════════════════════════════════════════════════════════
# Hard Gate 판정
# ══════════════════════════════════════════════════════════════

agent_check_generate() {
    local file="$1"
    "${ACTIONS_DIR}/hard_gate.sh" --type=generate --file="$file"
}

agent_check_eval() {
    local file="$1"
    "${ACTIONS_DIR}/hard_gate.sh" --type=eval --file="$file"
}

# ══════════════════════════════════════════════════════════════
# 점수 파싱
# ══════════════════════════════════════════════════════════════

agent_parse_score() {
    local eval_file="$1"

    if [[ ! -f "$eval_file" ]]; then
        echo "0"
        return
    fi

    # JSON에서 total_score 추출 (여러 형식 지원)
    local score
    score=$(python3 -c "
import json
import re
import sys

try:
    with open('$eval_file', 'r') as f:
        content = f.read()

    # JSON 블록 찾기 (```json ... ``` 또는 순수 JSON)
    json_match = re.search(r'\`\`\`json\s*([\s\S]*?)\`\`\`', content)
    if json_match:
        data = json.loads(json_match.group(1))
    else:
        # { 로 시작하는 JSON 찾기
        json_match = re.search(r'(\{[\s\S]*\})', content)
        if json_match:
            data = json.loads(json_match.group(1))
        else:
            print(0)
            sys.exit(0)

    print(data.get('total_score', data.get('score', 0)))
except Exception as e:
    print(0)
" 2>/dev/null)

    echo "${score:-0}"
}

# ══════════════════════════════════════════════════════════════
# 섹션 루프 (챕터별 5회 반복)
# ══════════════════════════════════════════════════════════════

agent_section_loop() {
    local section="$1"           # s1_2
    local max_iter="${2:-5}"     # 기본 5회
    local target_score="${3:-95}" # 기본 95점
    local writer="${4:-challenger}"

    local date=$(date +%Y-%m-%d)
    local output_dir="${PROJECT_DIR}/testing/runs/${date}/${writer}"
    mkdir -p "$output_dir"

    local best_score=0
    local best_version=""
    local best_file=""

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  섹션 루프 시작: $section"
    echo "║  최대 반복: ${max_iter}회, 목표 점수: ${target_score}점"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    for v in $(seq 1 $max_iter); do
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  $section v$v / $max_iter (현재 최고: ${best_score}점)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        # 1. 생성 (v1은 new_chat, v2~는 continue)
        local gen_mode="continue"
        if [[ $v -eq 1 ]]; then
            gen_mode="new_chat"
        fi
        echo "[Loop] Step 1: 생성 (mode=$gen_mode)..."
        local output_file
        output_file=$(agent_regenerate "$section" "v$v" "$gen_mode" "$writer")

        if [[ -z "$output_file" || ! -f "$output_file" ]]; then
            echo "[Loop] ⚠️ 생성 실패. 다음 반복으로..."
            continue
        fi

        # 2. Hard gate 검사
        echo "[Loop] Step 2: Hard gate 검사..."
        local gate_result
        gate_result=$(agent_check_generate "$output_file" 2>/dev/null)
        local gate_decision
        gate_decision=$(echo "$gate_result" | jq -r '.decision // "UNKNOWN"' 2>/dev/null)

        if [[ "$gate_decision" != "PASS" ]]; then
            echo "[Loop] ⚠️ Hard gate 실패: $gate_decision"
            echo "[Loop] 이유: $(echo "$gate_result" | jq -r '.reasons[]?' 2>/dev/null)"
            continue
        fi
        echo "[Loop] ✅ Hard gate PASS"

        # 3. 평가
        echo "[Loop] Step 3: 평가..."
        local eval_file
        eval_file=$(agent_evaluate "$output_file")

        if [[ -z "$eval_file" || ! -f "$eval_file" ]]; then
            echo "[Loop] ⚠️ 평가 실패. 다음 반복으로..."
            continue
        fi

        # 4. 점수 파싱
        local score
        score=$(agent_parse_score "$eval_file")
        echo "[Loop] 점수: ${score}점"

        # 5. 최고 점수 갱신
        if [[ $score -gt $best_score ]]; then
            best_score=$score
            best_version="v$v"
            best_file="$output_file"
            echo "[Loop] 🎯 최고 점수 갱신: v$v = ${score}점"
        fi

        # 6. 목표 달성 시 조기 종료
        if [[ $score -ge $target_score ]]; then
            echo ""
            echo "╔══════════════════════════════════════════════════════════════╗"
            echo "║  ✅ 목표 달성! ${score}점 >= ${target_score}점"
            echo "║  최종 버전: $best_version"
            echo "╚══════════════════════════════════════════════════════════════╝"
            echo "$best_file"
            return 0
        fi

        echo "[Loop] 목표 미달 (${score} < ${target_score}). 다음 반복..."
    done

    # 5회 완료 후 최고 점수 버전으로 확정
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  ⏹️  ${max_iter}회 완료. 목표 미달."
    echo "║  최고 버전: $best_version (${best_score}점)"
    echo "╚══════════════════════════════════════════════════════════════╝"

    echo "$best_file"
    return 0
}

# ══════════════════════════════════════════════════════════════
# 섹션 목록 가져오기
# ══════════════════════════════════════════════════════════════

agent_get_sections() {
    local sections_file="${PROJECT_DIR}/sections.yaml"

    if [[ ! -f "$sections_file" ]]; then
        echo "s1_1 s1_2 s1_3 s2_1 s2_2"  # fallback
        return
    fi

    python3 -c "
import yaml

with open('$sections_file', 'r') as f:
    data = yaml.safe_load(f)

sections = data.get('sections', [])
ids = [s.get('id', '') for s in sections if s.get('id') and not s.get('needs_human', False)]
print(' '.join(ids))
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 전체 섹션 실행
# ══════════════════════════════════════════════════════════════

agent_run_all_sections() {
    local max_iter="${1:-5}"
    local target_score="${2:-95}"
    local writer="${3:-challenger}"
    local start_section="${4:-}"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           전체 섹션 실행 시작"
    echo "║  반복: ${max_iter}회, 목표: ${target_score}점, Writer: ${writer}"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    local sections
    sections=$(agent_get_sections)

    local started=false
    if [[ -z "$start_section" ]]; then
        started=true
    fi

    local total=0
    local completed=0

    for section in $sections; do
        ((total++))

        # 시작 섹션 체크
        if [[ "$started" != "true" ]]; then
            if [[ "$section" == "$start_section" ]]; then
                started=true
            else
                echo "[All] 스킵: $section (시작 섹션: $start_section)"
                continue
            fi
        fi

        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        echo "  섹션 $completed/$total: $section"
        echo "═══════════════════════════════════════════════════════════════"

        local best_file
        best_file=$(agent_section_loop "$section" "$max_iter" "$target_score" "$writer")

        if [[ -n "$best_file" ]]; then
            ((completed++))
            echo "[All] ✅ $section 완료: $best_file"
        else
            echo "[All] ⚠️ $section 실패"
        fi
    done

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           전체 섹션 실행 완료"
    echo "║  완료: $completed / $total"
    echo "╚══════════════════════════════════════════════════════════════╝"
}

# ══════════════════════════════════════════════════════════════
# 초기화
# ══════════════════════════════════════════════════════════════

echo "[Agent] actions.sh 로드됨"
