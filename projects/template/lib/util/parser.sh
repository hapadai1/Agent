#!/bin/bash
# parser.sh - YAML/마크다운 파싱 공통 모듈
# 사용법: source lib/util/parser.sh

# ══════════════════════════════════════════════════════════════
# YAML Front Matter 파싱
# ══════════════════════════════════════════════════════════════

# YAML Front Matter에서 특정 키 값 추출
# 사용법: value=$(parse_front_matter "$file" "section_name")
#        value=$(parse_front_matter "$file" "nested.key")
parse_front_matter() {
    local file="$1"
    local key="$2"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

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
# 사용법: body=$(get_body "$file")
get_body() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    python3 -c "
import re

with open('$file', 'r', encoding='utf-8') as f:
    content = f.read()

# Front Matter 제거
body = re.sub(r'^---\s*\n.*?\n---\s*\n', '', content, flags=re.DOTALL)
print(body.strip())
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# Suite YAML 파싱
# ══════════════════════════════════════════════════════════════

# Suite YAML에서 샘플 목록 추출
# 사용법: samples=$(get_suite_samples "$suite_file")
#        while IFS='|' read -r sample_id sample_file; do ... done <<< "$samples"
get_suite_samples() {
    local suite_file="$1"

    if [[ ! -f "$suite_file" ]]; then
        echo ""
        return 1
    fi

    python3 -c "
import yaml

with open('$suite_file', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)

samples = data.get('samples', [])
for s in samples:
    print(f\"{s['id']}|{s['file']}\")
" 2>/dev/null
}


# ══════════════════════════════════════════════════════════════
# JSON 추출 및 파싱
# ══════════════════════════════════════════════════════════════

# 텍스트에서 JSON 블록 추출 (```json ... ``` 또는 raw JSON)
# 사용법: json=$(extract_json "$text")
extract_json() {
    local content="$1"

    echo "$content" | python3 -c "
import re
import sys

content = sys.stdin.read()

# ```json ... ``` 블록에서 추출
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
" 2>/dev/null
}

# JSON에서 특정 키 값 추출
# 사용법: score=$(json_get "$json" "total_score")
json_get() {
    local json="$1"
    local key="$2"

    echo "$json" | python3 -c "
import json
import sys

try:
    data = json.load(sys.stdin)
    print(data.get('$key', ''))
except:
    print('')
" 2>/dev/null
}

# JSON에서 배열을 콤마로 구분된 문자열로 추출
# 사용법: tags=$(json_get_array "$json" "defect_tags")
json_get_array() {
    local json="$1"
    local key="$2"

    echo "$json" | python3 -c "
import json
import sys

try:
    data = json.load(sys.stdin)
    arr = data.get('$key', [])
    print(', '.join(str(x) for x in arr))
except:
    print('')
" 2>/dev/null
}

# JSON 유효성 검사
# 사용법: if validate_json "$json"; then echo "valid"; fi
validate_json() {
    local json="$1"

    echo "$json" | python3 -c "
import json
import sys

try:
    json.load(sys.stdin)
    sys.exit(0)
except:
    sys.exit(1)
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 샘플 파일 메타데이터 추출
# ══════════════════════════════════════════════════════════════

# 샘플 파일에서 주제 추출 (## 주제 다음 줄)
# 사용법: topic=$(extract_topic "$sample_file")
extract_topic() {
    local file="$1"
    local body
    body=$(get_body "$file")
    echo "$body" | grep -A1 "^## 주제" | tail -1
}

# 샘플 파일에서 분량 추출 (A4 X장)
# 사용법: pages=$(extract_pages "$sample_file")
extract_pages() {
    local file="$1"
    local body
    body=$(get_body "$file")
    local pages
    pages=$(echo "$body" | grep -oE "A4 [0-9.]+" | head -1 | grep -oE "[0-9.]+")
    echo "${pages:-1.5}"
}

# 샘플 파일에서 전체 메타데이터 추출 (연관 배열로 반환)
# 사용법: eval "$(extract_sample_metadata "$sample_file")"
#        echo "$META_section_name $META_topic $META_pages"
extract_sample_metadata() {
    local file="$1"

    local section_name topic pages body section_id
    section_name=$(parse_front_matter "$file" "section_name")
    section_id=$(parse_front_matter "$file" "section")
    body=$(get_body "$file")
    topic=$(echo "$body" | grep -A1 "^## 주제" | tail -1)
    pages=$(echo "$body" | grep -oE "A4 [0-9.]+" | head -1 | grep -oE "[0-9.]+")
    pages="${pages:-1.5}"

    # 쉘 변수로 출력 (eval로 사용)
    cat <<EOF
META_section_name='${section_name//\'/\'\"\'\"\'}'
META_section_id='${section_id//\'/\'\"\'\"\'}'
META_topic='${topic//\'/\'\"\'\"\'}'
META_pages='${pages}'
META_body='$(echo "$body" | sed "s/'/'\\\\''/g")'
EOF
}
