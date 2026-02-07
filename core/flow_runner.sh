#!/bin/bash
# flow_runner.sh - Flow 실행 엔진
# flow.yaml을 파싱하여 워크플로우를 실행합니다.
#
# 사용법:
#   source flow_runner.sh
#   flow_run [--step=STEP_ID] [--var KEY=VALUE]...

FLOW_RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 리서치 로더
if [[ -f "${FLOW_RUNNER_DIR}/research/loader.sh" ]]; then
    source "${FLOW_RUNNER_DIR}/research/loader.sh"
fi

# ══════════════════════════════════════════════════════════════
# Flow YAML 파싱 함수들
# ══════════════════════════════════════════════════════════════

# YAML 값 읽기
# 사용법: flow_get "steps[0].name"
flow_get() {
    local flow_file="${FLOW_FILE:-flow.yaml}"
    local key="$1"

    python3 -c "
import yaml
import sys

with open('$flow_file', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

keys = '$key'.replace('[', '.').replace(']', '').split('.')
result = data
for k in keys:
    if k == '': continue
    if isinstance(result, list):
        result = result[int(k)]
    elif isinstance(result, dict):
        result = result.get(k)
    else:
        result = None
        break

if result is not None:
    if isinstance(result, (dict, list)):
        import json
        print(json.dumps(result, ensure_ascii=False))
    else:
        print(result)
" 2>/dev/null
}

# 탭 정보 가져오기
# 사용법: flow_get_tab "writer"
flow_get_tab() {
    local tab_name="$1"
    flow_get "tabs.${tab_name}.tab"
}

# 탭 모드 가져오기
flow_get_tab_mode() {
    local tab_name="$1"
    local mode
    mode=$(flow_get "tabs.${tab_name}.mode")
    echo "${mode:-normal}"
}

# 스텝 목록 가져오기
flow_get_steps() {
    local flow_file="${FLOW_FILE:-flow.yaml}"

    python3 -c "
import yaml

with open('$flow_file', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

steps = data.get('steps', [])
for step in steps:
    print(step.get('id', ''))
" 2>/dev/null
}

# 스텝 정보 가져오기
flow_get_step() {
    local step_id="$1"
    local field="$2"
    local flow_file="${FLOW_FILE:-flow.yaml}"

    python3 -c "
import yaml
import json

with open('$flow_file', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

steps = data.get('steps', [])
for step in steps:
    if step.get('id') == '$step_id':
        value = step.get('$field')
        if value is not None:
            if isinstance(value, (dict, list)):
                print(json.dumps(value, ensure_ascii=False))
            else:
                print(value)
        break
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 변수 치환
# ══════════════════════════════════════════════════════════════

# 변수 저장소 (연관 배열)
declare -A FLOW_VARS
declare -A FLOW_OUTPUTS

# 변수 설정
flow_set_var() {
    local key="$1"
    local value="$2"
    FLOW_VARS["$key"]="$value"
}

# 변수 가져오기
flow_get_var() {
    local key="$1"
    echo "${FLOW_VARS[$key]:-}"
}

# 출력 저장
flow_set_output() {
    local step_id="$1"
    local value="$2"
    FLOW_OUTPUTS["$step_id"]="$value"
}

# 출력 가져오기
flow_get_output() {
    local step_id="$1"
    echo "${FLOW_OUTPUTS[$step_id]:-}"
}

# 문자열 내 변수 치환
# {variable} 형식과 $step.output 형식 지원
flow_substitute() {
    local text="$1"
    local result="$text"

    # {variable} 형식 치환
    for key in "${!FLOW_VARS[@]}"; do
        result="${result//\{$key\}/${FLOW_VARS[$key]}}"
    done

    # $step.output 형식 치환
    for key in "${!FLOW_OUTPUTS[@]}"; do
        result="${result//\$$key.output/${FLOW_OUTPUTS[$key]}}"
    done

    echo "$result"
}

# ══════════════════════════════════════════════════════════════
# 스텝 실행
# ══════════════════════════════════════════════════════════════

# 단일 스텝 실행
flow_run_step() {
    local step_id="$1"

    # 스텝 정보 가져오기
    local step_name tab_name prompt_file output_file timeout retry
    step_name=$(flow_get_step "$step_id" "name")
    tab_name=$(flow_get_step "$step_id" "tab")
    prompt_file=$(flow_get_step "$step_id" "prompt")
    output_file=$(flow_get_step "$step_id" "output")
    timeout=$(flow_get_step "$step_id" "timeout")
    retry=$(flow_get_step "$step_id" "retry")

    # enabled 체크
    local enabled
    enabled=$(flow_get_step "$step_id" "enabled")
    if [[ "$enabled" == "false" ]]; then
        log_info "Step skipped (disabled): $step_name"
        return 0
    fi

    # 조건 체크
    local condition
    condition=$(flow_get_step "$step_id" "condition")
    if [[ -n "$condition" ]]; then
        if ! flow_check_condition "$condition"; then
            log_info "Step skipped (condition not met): $step_name"
            return 0
        fi
    fi

    log_info "━━━ Step: $step_name ━━━"

    # 탭 번호 및 모드
    local tab_num tab_mode
    tab_num=$(flow_get_tab "$tab_name")
    tab_mode=$(flow_get_tab_mode "$tab_name")

    # 프롬프트 파일 경로 치환
    prompt_file=$(flow_substitute "$prompt_file")

    # 프롬프트 로드
    local prompt_content
    if [[ -f "${PROJECT_DIR}/${prompt_file}" ]]; then
        prompt_content=$(cat "${PROJECT_DIR}/${prompt_file}")
    else
        log_error "Prompt file not found: ${PROJECT_DIR}/${prompt_file}"
        return 1
    fi

    # 프롬프트 변수 치환
    prompt_content=$(flow_substitute "$prompt_content")

    # 리서치 결과 주입 비활성화 (수동으로 research/responses/에 파일 추가 후 {research_block} 사용)
    # local section_id
    # section_id=$(flow_get_var "section_id")
    # if [[ -n "$section_id" ]] && type research_inject_prompt &>/dev/null; then
    #     local research_check
    #     research_check=$(research_check_section "$section_id" "$PROJECT_DIR" 2>/dev/null)
    #     local needs_research
    #     needs_research=$(echo "$research_check" | python3 -c "import json,sys; print(json.load(sys.stdin).get('needs_research', False))" 2>/dev/null)
    #
    #     if [[ "$needs_research" == "True" ]]; then
    #         local has_results
    #         has_results=$(echo "$research_check" | python3 -c "import json,sys; print(json.load(sys.stdin).get('has_results', False))" 2>/dev/null)
    #         local research_type
    #         research_type=$(echo "$research_check" | python3 -c "import json,sys; print(json.load(sys.stdin).get('research_type', ''))" 2>/dev/null)
    #
    #         if [[ "$has_results" == "True" ]]; then
    #             log_info "📊 리서치 결과 주입: ${research_type}"
    #             prompt_content=$(research_inject_prompt "$prompt_content" "$section_id" "$PROJECT_DIR")
    #         else
    #             log_warn "⚠️ 리서치 필요하지만 결과 없음: ${research_type}"
    #             # {research_block}을 안내 메시지로 치환
    #             local notice="[제공 근거]\n리서치 결과가 아직 없습니다. (${research_type})"
    #             prompt_content="${prompt_content//\{research_block\}/$notice}"
    #         fi
    #     else
    #         # 리서치 불필요 → {research_block} 제거
    #         prompt_content="${prompt_content//\{research_block\}/}"
    #     fi
    # fi
    # 단순히 {research_block} 제거
    prompt_content="${prompt_content//\{research_block\}/}"

    # inject 처리 (이전 스텝 출력 주입)
    local inject_json
    inject_json=$(flow_get_step "$step_id" "inject")
    if [[ -n "$inject_json" && "$inject_json" != "null" ]]; then
        prompt_content=$(flow_inject_content "$prompt_content" "$inject_json")
    fi

    # ChatGPT 호출 옵션 구성
    local chatgpt_opts="--tab=$tab_num"
    [[ -n "$timeout" ]] && chatgpt_opts="$chatgpt_opts --timeout=$timeout"
    [[ -n "$retry" && "$retry" -gt 0 ]] && chatgpt_opts="$chatgpt_opts --retry --retry-count=$retry"

    # 모드별 처리
    case "$tab_mode" in
        new_chat)
            chatgpt_opts="$chatgpt_opts --mode=new_chat"
            ;;
        deep_research)
            chatgpt_opts="$chatgpt_opts --mode=research"
            ;;
    esac

    # section_aware 체크
    local section_aware
    section_aware=$(flow_get "tabs.${tab_name}.section_aware")
    if [[ "$section_aware" == "true" ]]; then
        local section_id
        section_id=$(flow_get_var "section_id")
        [[ -n "$section_id" ]] && chatgpt_opts="$chatgpt_opts --section=$section_id"
    fi

    # ChatGPT 호출
    local response
    if type chatgpt_call &>/dev/null; then
        log_debug "chatgpt_call $chatgpt_opts \"...\""
        response=$(chatgpt_call $chatgpt_opts "$prompt_content")
    else
        log_warn "[MOCK] ChatGPT not available"
        response="[MOCK RESPONSE for step: $step_id]"
    fi

    # 출력 저장
    if [[ -n "$output_file" ]]; then
        output_file=$(flow_substitute "$output_file")
        local output_path="${PROJECT_DIR}/${output_file}"
        mkdir -p "$(dirname "$output_path")"
        echo "$response" > "$output_path"
        log_info "Output saved: $output_file"
        flow_set_output "$step_id" "$output_path"
    fi

    # parse 처리
    local parse_format
    parse_format=$(flow_get_step "$step_id" "parse")
    if [[ "$parse_format" == "json" ]]; then
        # JSON에서 score 추출하여 변수로 저장
        local score
        score=$(echo "$response" | python3 -c "
import json, sys, re
content = sys.stdin.read()
match = re.search(r'\`\`\`json\s*([\s\S]*?)\`\`\`', content)
if match:
    try:
        data = json.loads(match.group(1))
        print(data.get('total_score', 0))
    except:
        print(0)
else:
    try:
        data = json.loads(content)
        print(data.get('total_score', 0))
    except:
        print(0)
" 2>/dev/null)
        flow_set_var "${step_id}.score" "$score"
        log_info "Score: $score"
    fi

    return 0
}

# inject 처리
flow_inject_content() {
    local prompt="$1"
    local inject_json="$2"

    python3 -c "
import json
import sys

prompt = '''$prompt'''
inject_list = json.loads('$inject_json')

for item in inject_list:
    source = item.get('source', '')
    label = item.get('label', 'Injected Content')

    # \$step.output 형식 파싱
    if source.startswith('\$') and '.output' in source:
        step_id = source[1:].replace('.output', '')
        # 환경변수에서 출력 경로 가져오기
        # 실제로는 FLOW_OUTPUTS에서 가져와야 하지만 여기서는 간략화
        pass

    # 파일 읽기
    if source and not source.startswith('\$'):
        try:
            with open(source, 'r') as f:
                content = f.read()
            prompt += f'''

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[{label}]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{content}
'''
        except:
            pass

print(prompt)
" 2>/dev/null
}

# 조건 체크
flow_check_condition() {
    local condition="$1"

    # $step.score < 85 형식 파싱
    if [[ "$condition" =~ ^\$([a-zA-Z_]+)\.score\ *\<\ *([0-9]+)$ ]]; then
        local step_id="${BASH_REMATCH[1]}"
        local threshold="${BASH_REMATCH[2]}"
        local score
        score=$(flow_get_var "${step_id}.score")
        [[ -n "$score" && "$score" -lt "$threshold" ]]
        return $?
    fi

    # 기본: true
    return 0
}

# ══════════════════════════════════════════════════════════════
# 메인 실행 함수
# ══════════════════════════════════════════════════════════════

# 전체 Flow 실행
flow_run() {
    local flow_file="${FLOW_FILE:-${PROJECT_DIR}/flow.yaml}"
    export FLOW_FILE="$flow_file"

    if [[ ! -f "$flow_file" ]]; then
        log_error "Flow file not found: $flow_file"
        return 1
    fi

    local flow_name
    flow_name=$(flow_get "name")
    log_info "══════════════════════════════════════════"
    log_info "Flow: $flow_name"
    log_info "══════════════════════════════════════════"

    # 옵션 파싱
    local target_step=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --step=*)
                target_step="${1#*=}"
                shift
                ;;
            --var=*|--set=*)
                local kv="${1#*=}"
                local key="${kv%%=*}"
                local value="${kv#*=}"
                flow_set_var "$key" "$value"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # 스텝 실행
    local steps
    steps=$(flow_get_steps)

    while IFS= read -r step_id; do
        [[ -z "$step_id" ]] && continue

        # 특정 스텝만 실행
        if [[ -n "$target_step" && "$step_id" != "$target_step" ]]; then
            continue
        fi

        if ! flow_run_step "$step_id"; then
            log_error "Step failed: $step_id"
            return 1
        fi
    done <<< "$steps"

    log_info "══════════════════════════════════════════"
    log_info "Flow completed"
    log_info "══════════════════════════════════════════"

    return 0
}

# ══════════════════════════════════════════════════════════════
# 스크립트 직접 실행 시
# ══════════════════════════════════════════════════════════════
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Flow Runner - 사용법:"
    echo ""
    echo "  source flow_runner.sh"
    echo "  flow_run [옵션]"
    echo ""
    echo "옵션:"
    echo "  --step=STEP_ID     특정 스텝만 실행"
    echo "  --var=KEY=VALUE    변수 설정"
    echo ""
    echo "환경변수:"
    echo "  FLOW_FILE          flow.yaml 경로 (기본: \$PROJECT_DIR/flow.yaml)"
    echo "  PROJECT_DIR        프로젝트 디렉토리"
fi
