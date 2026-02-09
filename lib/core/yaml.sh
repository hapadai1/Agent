#!/bin/bash
# yaml.sh - YAML 처리 공통 모듈
# 사용법: source lib/core/yaml.sh
#
# 의존성: python3 (PyYAML)

# ══════════════════════════════════════════════════════════════
# YAML 파일 읽기
# ══════════════════════════════════════════════════════════════

# YAML 파일에서 특정 키 값 추출
# 사용법: value=$(yaml_get "$file" "meta.version")
yaml_get() {
    local file="$1"
    local key="$2"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    python3 -c "
import yaml

try:
    with open('$file', 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f)

    keys = '$key'.split('.')
    result = data
    for k in keys:
        if result and isinstance(result, dict):
            result = result.get(k)
        elif result and isinstance(result, list) and k.isdigit():
            idx = int(k)
            result = result[idx] if idx < len(result) else None
        else:
            result = None
            break

    if result is not None:
        if isinstance(result, (dict, list)):
            import json
            print(json.dumps(result, ensure_ascii=False))
        else:
            print(result)
except Exception as e:
    pass
" 2>/dev/null
}

# YAML 파일 전체를 JSON으로 변환
# 사용법: json=$(yaml_to_json "$file")
yaml_to_json() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "{}"
        return 1
    fi

    python3 -c "
import yaml
import json

try:
    with open('$file', 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f)
    print(json.dumps(data, ensure_ascii=False))
except:
    print('{}')
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# YAML Front Matter 파싱
# ══════════════════════════════════════════════════════════════

# YAML Front Matter에서 특정 키 값 추출
# 사용법: value=$(yaml_front_matter "$file" "section_name")
yaml_front_matter() {
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
# 사용법: body=$(yaml_get_body "$file")
yaml_get_body() {
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
# YAML 배열 처리
# ══════════════════════════════════════════════════════════════

# YAML 파일에서 배열 키 목록 추출
# 사용법: while read -r item; do ... done < <(yaml_list "$file" "sections")
yaml_list() {
    local file="$1"
    local key="$2"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    python3 -c "
import yaml
import json

try:
    with open('$file', 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f)

    keys = '$key'.split('.')
    result = data
    for k in keys:
        if result and isinstance(result, dict):
            result = result.get(k)

    if isinstance(result, list):
        for item in result:
            if isinstance(item, dict):
                print(json.dumps(item, ensure_ascii=False))
            else:
                print(item)
except:
    pass
" 2>/dev/null
}

# YAML 배열 길이 반환
# 사용법: count=$(yaml_list_count "$file" "sections")
yaml_list_count() {
    local file="$1"
    local key="$2"

    if [[ ! -f "$file" ]]; then
        echo "0"
        return 1
    fi

    python3 -c "
import yaml

try:
    with open('$file', 'r', encoding='utf-8') as f:
        data = yaml.safe_load(f)

    keys = '$key'.split('.')
    result = data
    for k in keys:
        if result and isinstance(result, dict):
            result = result.get(k)

    if isinstance(result, list):
        print(len(result))
    else:
        print(0)
except:
    print(0)
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# Suite YAML 파싱 (프로젝트 특화)
# ══════════════════════════════════════════════════════════════

# Suite YAML에서 샘플 목록 추출
# 사용법: while IFS='|' read -r sample_id sample_file; do ... done < <(yaml_suite_samples "$suite_file")
yaml_suite_samples() {
    local suite_file="$1"

    if [[ ! -f "$suite_file" ]]; then
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
# YAML 검증
# ══════════════════════════════════════════════════════════════

# YAML 파일 유효성 검사
# 사용법: if yaml_validate "$file"; then echo "valid"; fi
yaml_validate() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    python3 -c "
import yaml
import sys

try:
    with open('$file', 'r', encoding='utf-8') as f:
        yaml.safe_load(f)
    sys.exit(0)
except:
    sys.exit(1)
" 2>/dev/null
}

# YAML 파일에 특정 키가 있는지 확인
# 사용법: if yaml_has_key "$file" "meta.version"; then ...
yaml_has_key() {
    local file="$1"
    local key="$2"

    local value
    value=$(yaml_get "$file" "$key")
    [[ -n "$value" ]]
}
