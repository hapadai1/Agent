#!/bin/bash
# template.sh - 안전한 템플릿 치환 모듈
# 사용법: source lib/util/template.sh

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

    local template
    template=$(cat "$template_file")

    # Python으로 안전하게 치환
    local result
    result=$(python3 -c "
import sys

template = '''$template'''
section_name = '''$section_name'''
section_detail = '''$section_detail'''
topic = '''$topic'''
pages = '''$pages'''
research_block = '''$research_block'''
previous_feedback = '''$previous_feedback'''

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
" 2>/dev/null)

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

    local template
    template=$(cat "$template_file")

    # Python으로 안전하게 치환
    python3 -c "
template = '''$template'''
section_name = '''$section_name'''

# content는 stdin으로 받음 (큰 텍스트 처리)
import sys
content = sys.stdin.read()

template = template.replace('{section_name}', section_name)
template = template.replace('{section_content}', content)

print(template)
" <<< "$content" 2>/dev/null
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

    # Python으로 안전하게 치환
    python3 -c "
template = '''$template'''
key = '$key'
value = '''$value'''

placeholder = '{' + key + '}'
result = template.replace(placeholder, value)
print(result)
" 2>/dev/null
}

# 복수 플레이스홀더 치환 (dict 형태)
# 사용법: result=$(replace_placeholders "$template" '{"topic": "AI", "pages": "1.5"}')
replace_placeholders() {
    local template="$1"
    local vars_json="$2"

    echo "$template" | python3 -c "
import sys
import json

template = sys.stdin.read()
vars_json = '''$vars_json'''

try:
    variables = json.loads(vars_json)

    for key, value in variables.items():
        placeholder = '{' + key + '}'
        template = template.replace(placeholder, str(value))

    print(template)
except:
    print(template)
" 2>/dev/null
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
    python3 -c "import json; print(json.dumps('''$value'''))" 2>/dev/null
}

# 쉘 문자열 이스케이프 (작은따옴표용)
# 사용법: escaped=$(escape_shell "$value")
escape_shell() {
    local value="$1"
    echo "${value//\'/\'\"\'\"\'}"
}
