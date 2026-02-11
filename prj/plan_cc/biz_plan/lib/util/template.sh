#!/bin/bash
# template.sh - 안전한 템플릿 치환 모듈
# 사용법: source lib/util/template.sh

# ══════════════════════════════════════════════════════════════
# 변수 파일에서 프롬프트 렌더링 (핵심 함수)
# ══════════════════════════════════════════════════════════════

# config/variables.yaml에서 변수를 읽어 템플릿 치환
# 사용법: prompt=$(render_prompt_from_config "$section_id")
# 예시: prompt=$(render_prompt_from_config "s1_2")
render_prompt_from_config() {
    local section_id="$1"
    local project_dir="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

    local variables_file="${project_dir}/config/variables.yaml"
    local template_file="${project_dir}/prompts/writer/challenger.md"

    if [[ ! -f "$variables_file" ]]; then
        echo "ERROR: variables.yaml not found: $variables_file" >&2
        return 1
    fi

    if [[ ! -f "$template_file" ]]; then
        echo "ERROR: template not found: $template_file" >&2
        return 1
    fi

    SECTION_ID="$section_id" PROJECT_DIR="$project_dir" python3 << 'PYTHON_EOF'
import yaml
import re
import os

section_id = os.environ['SECTION_ID']
project_dir = os.environ['PROJECT_DIR']

# 변수 파일 로드
with open(f'{project_dir}/config/variables.yaml', 'r') as f:
    vars_data = yaml.safe_load(f)

# 템플릿 파일 로드
with open(f'{project_dir}/prompts/writer/challenger.md', 'r') as f:
    template = f.read()

# 공통 변수
topic = vars_data['common'].get('topic', '')
prior_summary_block = vars_data['common'].get('prior_summary_block', '')

# 섹션 변수
section_vars = vars_data['sections'].get(section_id, {})
section_name = section_vars.get('section_name', '')
pages = section_vars.get('pages', '1')
sample_file = section_vars.get('sample_file', '')
research_file = section_vars.get('research_file', '')

# section_detail 로드 (샘플 파일에서)
section_detail = ""
if sample_file:
    try:
        with open(f'{project_dir}/{sample_file}', 'r') as f:
            content = f.read()
        # Front Matter 제거
        section_detail = re.sub(r'^---\s*\n.*?\n---\s*\n', '', content, flags=re.DOTALL).strip()
    except Exception as e:
        section_detail = f"(파일 로드 실패: {e})"

# research_block 로드
research_block = ""
if research_file:
    try:
        with open(f'{project_dir}/{research_file}', 'r') as f:
            research_block = f.read().strip()
    except:
        pass

# 템플릿 치환
prompt = template
prompt = prompt.replace('{topic}', topic)
prompt = prompt.replace('{section_name}', section_name)
prompt = prompt.replace('{pages}', pages)
prompt = prompt.replace('{section_detail}', section_detail)
prompt = prompt.replace('{prior_summary_block}', prior_summary_block)
prompt = prompt.replace('{research_block}', research_block)

print(prompt)
PYTHON_EOF
}

# 섹션 변수만 로드 (개별 값 접근용)
# 사용법: eval "$(load_section_vars s1_2)"
#         echo "$VAR_section_name"
load_section_vars() {
    local section_id="$1"
    local project_dir="${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
    local variables_file="${project_dir}/config/variables.yaml"

    SECTION_ID="$section_id" python3 << 'PYTHON_EOF' "$variables_file"
import yaml
import sys
import os

section_id = os.environ['SECTION_ID']

with open(sys.argv[1], 'r') as f:
    data = yaml.safe_load(f)

# 공통 변수
for key, value in data.get('common', {}).items():
    print(f"VAR_{key}='{value}'")

# 섹션 변수
section = data.get('sections', {}).get(section_id, {})
for key, value in section.items():
    print(f"VAR_{key}='{value}'")
PYTHON_EOF
}

# ══════════════════════════════════════════════════════════════
# 안전한 문자열 치환 (Python 사용)
# ══════════════════════════════════════════════════════════════

# 안전한 템플릿 렌더링 (특수문자 처리)
# 사용법: result=$(render_template "$template" "topic=AI 경매" "pages=1.5")
render_template() {
    local template="$1"
    shift  # 나머지는 key=value 쌍

    # JSON 형태로 변수 전달
    local vars_json="{"
    local first=true

    for kv in "$@"; do
        local key="${kv%%=*}"
        local value="${kv#*=}"

        if [[ "$first" == "true" ]]; then
            first=false
        else
            vars_json+=","
        fi

        # JSON 이스케이프
        value=$(echo "$value" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))")
        vars_json+="\"$key\":$value"
    done

    vars_json+="}"

    echo "$template" | python3 -c "
import sys
import json
import re

template = sys.stdin.read()
vars_json = '''$vars_json'''

try:
    variables = json.loads(vars_json)

    # {key} 형태의 플레이스홀더 치환
    for key, value in variables.items():
        placeholder = '{' + key + '}'
        template = template.replace(placeholder, str(value))

    print(template)
except Exception as e:
    # 실패 시 원본 반환
    print(template)
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# Writer 프롬프트 렌더링
# ══════════════════════════════════════════════════════════════

# Writer 프롬프트 파일 로드 및 변수 치환
# 사용법: prompt=$(render_writer_prompt "$template_file" "$section_name" "$section_detail" "$topic" "$pages" "$research_block" "$feedback")
render_writer_prompt() {
    local template_file="$1"
    local section_name="$2"
    local section_detail="$3"
    local topic="$4"
    local pages="$5"
    local research_block="${6:-}"
    local previous_feedback="${7:-}"

    if [[ ! -f "$template_file" ]]; then
        echo "ERROR: Writer prompt not found: $template_file" >&2
        return 1
    fi

    # Python으로 안전하게 치환 (변수는 환경변수로 전달)
    local result
    result=$(
        TMPL_SECTION_NAME="$section_name" \
        TMPL_SECTION_DETAIL="$section_detail" \
        TMPL_TOPIC="$topic" \
        TMPL_PAGES="$pages" \
        TMPL_RESEARCH="$research_block" \
        python3 -c "
import os
import sys

# 템플릿 파일 읽기
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    template = f.read()

# 환경변수에서 안전하게 값 읽기
section_name = os.environ.get('TMPL_SECTION_NAME', '')
section_detail = os.environ.get('TMPL_SECTION_DETAIL', '')
topic = os.environ.get('TMPL_TOPIC', '')
pages = os.environ.get('TMPL_PAGES', '')
research_block = os.environ.get('TMPL_RESEARCH', '')

# 플레이스홀더 치환
template = template.replace('{topic}', topic)
template = template.replace('{section_name}', section_name)
template = template.replace('{section_detail}', section_detail)
template = template.replace('{pages}', pages)
template = template.replace('{prior_summary_block}', '')

# 리서치 블록 치환
if research_block:
    template = template.replace('{research_block}', research_block)
else:
    template = template.replace('{research_block}', '')

print(template)
" "$template_file" 2>/dev/null)

    # 이전 피드백 추가
    if [[ -n "$previous_feedback" ]]; then
        result="$result

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[이전 차수 평가 피드백] ★ 반드시 반영 ★
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$previous_feedback

위 피드백의 문제점을 반드시 개선하여 작성하세요."
    fi

    echo "$result"
}

# ══════════════════════════════════════════════════════════════
# Evaluator 프롬프트 렌더링
# ══════════════════════════════════════════════════════════════

# Evaluator 프롬프트 파일 로드 및 변수 치환
# 사용법: prompt=$(render_evaluator_prompt "$template_file" "$section_name" "$content")
render_evaluator_prompt() {
    local template_file="$1"
    local section_name="$2"
    local content="$3"

    if [[ ! -f "$template_file" ]]; then
        echo "ERROR: Evaluator prompt not found: $template_file" >&2
        return 1
    fi

    # Python으로 안전하게 치환 (변수는 환경변수로, content는 stdin으로)
    TMPL_SECTION_NAME="$section_name" python3 -c "
import os
import sys

# 템플릿 파일 읽기
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    template = f.read()

# 환경변수에서 안전하게 값 읽기
section_name = os.environ.get('TMPL_SECTION_NAME', '')

# content는 stdin으로 받음 (큰 텍스트 처리)
content = sys.stdin.read()

template = template.replace('{section_name}', section_name)
template = template.replace('{section_content}', content)

print(template)
" "$template_file" <<< "$content" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 간단한 문자열 치환 (bash 내장, 작은 텍스트용)
# ══════════════════════════════════════════════════════════════

# 단일 플레이스홀더 치환 (특수문자 이스케이프 포함)
# 사용법: result=$(replace_placeholder "$template" "topic" "AI 경매")
replace_placeholder() {
    local template="$1"
    local key="$2"
    local value="$3"

    # Python으로 안전하게 치환 (환경변수 + stdin)
    TMPL_KEY="$key" TMPL_VALUE="$value" python3 -c "
import os
import sys

template = sys.stdin.read()
key = os.environ.get('TMPL_KEY', '')
value = os.environ.get('TMPL_VALUE', '')

placeholder = '{' + key + '}'
result = template.replace(placeholder, value)
print(result)
" <<< "$template" 2>/dev/null
}

# 복수 플레이스홀더 치환 (dict 형태)
# 사용법: result=$(replace_placeholders "$template" '{"topic": "AI", "pages": "1.5"}')
replace_placeholders() {
    local template="$1"
    local vars_json="$2"

    # Python으로 안전하게 치환 (JSON은 환경변수, template은 stdin)
    TMPL_VARS="$vars_json" python3 -c "
import sys
import json
import os

template = sys.stdin.read()
vars_json = os.environ.get('TMPL_VARS', '{}')

try:
    variables = json.loads(vars_json)

    for key, value in variables.items():
        placeholder = '{' + key + '}'
        template = template.replace(placeholder, str(value))

    print(template)
except:
    print(template)
" <<< "$template" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 프롬프트 빌더 헬퍼
# ══════════════════════════════════════════════════════════════

# 프롬프트에 블록 추가
# 사용법: prompt=$(append_block "$prompt" "리서치 자료" "$content")
append_block() {
    local prompt="$1"
    local title="$2"
    local content="$3"

    if [[ -z "$content" ]]; then
        echo "$prompt"
        return
    fi

    echo "$prompt

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[$title]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$content"
}

# 프롬프트에 필수 정보 블록 추가
# 사용법: prompt=$(append_required_info "$prompt" "$topic" "$section_name" "$pages")
append_required_info() {
    local prompt="$1"
    local topic="$2"
    local section_name="$3"
    local pages="$4"

    echo "$prompt

═══════════════════════════════════════════════════════════════
[필수 정보] ★ 반드시 반영 ★
═══════════════════════════════════════════════════════════════
- 주제: ${topic}
- 섹션명: ${section_name}
- 분량: A4 ${pages}장"
}

# ══════════════════════════════════════════════════════════════
# 이스케이프 유틸리티
# ══════════════════════════════════════════════════════════════

# JSON 문자열 이스케이프
# 사용법: escaped=$(escape_json "$value")
escape_json() {
    local value="$1"
    # stdin으로 전달하여 특수문자 안전하게 처리
    python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))" <<< "$value" 2>/dev/null
}

# 쉘 문자열 이스케이프 (작은따옴표용)
# 사용법: escaped=$(escape_shell "$value")
escape_shell() {
    local value="$1"
    echo "${value//\'/\'\"\'\"\'}"
}
