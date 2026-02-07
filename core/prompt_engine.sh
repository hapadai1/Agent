#!/bin/bash
# prompt_engine.sh - 프롬프트 로드 및 렌더링 엔진
# 프롬프트 파일을 로드하고 변수를 치환합니다.
#
# 사용법:
#   source prompt_engine.sh
#   prompt_load "prompts/writer/main.md"
#   prompt_render "$content" --var topic="AI 서비스" --var pages="1.5"

PROMPT_ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ══════════════════════════════════════════════════════════════
# 프롬프트 로드
# ══════════════════════════════════════════════════════════════

# 프롬프트 파일 로드
# 사용법: prompt_load "path/to/prompt.md"
prompt_load() {
    local prompt_path="$1"
    local full_path

    # 절대 경로 체크
    if [[ "$prompt_path" == /* ]]; then
        full_path="$prompt_path"
    elif [[ -n "$PROJECT_DIR" ]]; then
        full_path="${PROJECT_DIR}/${prompt_path}"
    else
        full_path="$prompt_path"
    fi

    if [[ ! -f "$full_path" ]]; then
        echo "ERROR: Prompt file not found: $full_path" >&2
        return 1
    fi

    cat "$full_path"
}

# 프롬프트 메타데이터 로드 (YAML front matter)
prompt_load_meta() {
    local prompt_path="$1"
    local full_path

    if [[ "$prompt_path" == /* ]]; then
        full_path="$prompt_path"
    elif [[ -n "$PROJECT_DIR" ]]; then
        full_path="${PROJECT_DIR}/${prompt_path}"
    else
        full_path="$prompt_path"
    fi

    python3 -c "
import yaml
import re

with open('$full_path', 'r', encoding='utf-8') as f:
    content = f.read()

match = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
if match:
    meta = yaml.safe_load(match.group(1))
    import json
    print(json.dumps(meta, ensure_ascii=False))
else:
    print('{}')
" 2>/dev/null
}

# 프롬프트 본문만 로드 (front matter 제외)
prompt_load_body() {
    local prompt_path="$1"
    local full_path

    if [[ "$prompt_path" == /* ]]; then
        full_path="$prompt_path"
    elif [[ -n "$PROJECT_DIR" ]]; then
        full_path="${PROJECT_DIR}/${prompt_path}"
    else
        full_path="$prompt_path"
    fi

    python3 -c "
import re

with open('$full_path', 'r', encoding='utf-8') as f:
    content = f.read()

# Front matter 제거
body = re.sub(r'^---\s*\n.*?\n---\s*\n', '', content, flags=re.DOTALL)
print(body.strip())
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 프롬프트 렌더링 (변수 치환)
# ══════════════════════════════════════════════════════════════

# 프롬프트 렌더링
# 사용법: prompt_render "$content" --var key=value --var key2=value2
prompt_render() {
    local content="$1"
    shift

    # 변수 파싱
    declare -A vars
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --var=*|--set=*)
                local kv="${1#*=}"
                local key="${kv%%=*}"
                local value="${kv#*=}"
                vars["$key"]="$value"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Python으로 변수 치환
    python3 -c "
import sys
import re

content = '''$content'''
vars_str = '''$(for k in "${!vars[@]}"; do echo "$k=${vars[$k]}"; done)'''

# 변수 파싱
vars = {}
for line in vars_str.strip().split('\n'):
    if '=' in line:
        key, value = line.split('=', 1)
        vars[key.strip()] = value.strip()

# {variable} 형식 치환
for key, value in vars.items():
    content = content.replace('{' + key + '}', value)

# 미치환 변수 경고
unmatched = re.findall(r'\{([a-zA-Z_][a-zA-Z0-9_]*)\}', content)
for var in unmatched:
    print(f'WARNING: Unsubstituted variable: {{{var}}}', file=sys.stderr)

print(content)
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 프롬프트 조합
# ══════════════════════════════════════════════════════════════

# 여러 프롬프트/컨텐츠 조합
# 사용법: prompt_combine "base.md" --append "extra.md" --prepend "header.md"
prompt_combine() {
    local base="$1"
    shift

    local result=""
    local prepend_content=""
    local append_content=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prepend=*)
                local file="${1#*=}"
                if [[ -f "$file" ]]; then
                    prepend_content+=$(cat "$file")
                    prepend_content+=$'\n\n'
                fi
                shift
                ;;
            --append=*)
                local file="${1#*=}"
                if [[ -f "$file" ]]; then
                    append_content+=$'\n\n'
                    append_content+=$(cat "$file")
                fi
                shift
                ;;
            --inject=*)
                local content="${1#*=}"
                append_content+=$'\n\n'
                append_content+="$content"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # 조합
    local base_content
    if [[ -f "$base" ]]; then
        base_content=$(cat "$base")
    else
        base_content="$base"
    fi

    echo "${prepend_content}${base_content}${append_content}"
}

# 블록 형태로 컨텐츠 추가
# 사용법: prompt_add_block "$content" "제목" "블록 내용"
prompt_add_block() {
    local content="$1"
    local title="$2"
    local block="$3"

    if [[ -n "$block" ]]; then
        echo "$content"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "[$title]"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "$block"
    else
        echo "$content"
    fi
}

# ══════════════════════════════════════════════════════════════
# 프롬프트 검증
# ══════════════════════════════════════════════════════════════

# 필수 변수 체크
# 사용법: prompt_check_vars "$content" topic section_name
prompt_check_vars() {
    local content="$1"
    shift
    local required=("$@")
    local missing=()

    for var in "${required[@]}"; do
        if [[ "$content" == *"{$var}"* ]]; then
            missing+=("$var")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required variables: ${missing[*]}" >&2
        return 1
    fi

    return 0
}

# ══════════════════════════════════════════════════════════════
# 스크립트 직접 실행 시
# ══════════════════════════════════════════════════════════════
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Prompt Engine - 사용법:"
    echo ""
    echo "  source prompt_engine.sh"
    echo ""
    echo "함수:"
    echo "  prompt_load PATH           프롬프트 파일 로드"
    echo "  prompt_load_body PATH      본문만 로드 (front matter 제외)"
    echo "  prompt_load_meta PATH      메타데이터만 로드"
    echo "  prompt_render CONTENT      변수 치환"
    echo "  prompt_combine BASE        여러 프롬프트 조합"
    echo "  prompt_add_block CONTENT   블록 추가"
fi
