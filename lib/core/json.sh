#!/bin/bash
# json.sh - JSON 처리 공통 모듈
# 사용법: source lib/core/json.sh
#
# 의존성: python3, jq (선택)

# ══════════════════════════════════════════════════════════════
# JSON 추출
# ══════════════════════════════════════════════════════════════

# 텍스트에서 JSON 블록 추출 (```json ... ``` 또는 raw JSON)
# 사용법: json=$(json_extract "$text")
json_extract() {
    local content="$1"

    echo "$content" | python3 -c "
import re
import sys

content = sys.stdin.read()

# \`\`\`json ... \`\`\` 블록에서 추출
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

# ══════════════════════════════════════════════════════════════
# JSON 값 읽기
# ══════════════════════════════════════════════════════════════

# JSON에서 특정 키 값 추출
# 사용법: value=$(json_get "$json" "key")
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

# JSON에서 중첩 키 값 추출 (점 표기법)
# 사용법: value=$(json_get_nested "$json" "error.code")
json_get_nested() {
    local json="$1"
    local key="$2"

    echo "$json" | python3 -c "
import json
import sys

try:
    data = json.load(sys.stdin)
    keys = '$key'.split('.')
    result = data
    for k in keys:
        if isinstance(result, dict):
            result = result.get(k, '')
        else:
            result = ''
            break
    print(result if result is not None else '')
except:
    print('')
" 2>/dev/null
}

# JSON 파일에서 특정 키 값 추출
# 사용법: value=$(json_get_file "/path/to/file.json" "key")
json_get_file() {
    local file="$1"
    local key="$2"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    python3 -c "
import json

try:
    with open('$file', 'r') as f:
        data = json.load(f)
    keys = '$key'.split('.')
    result = data
    for k in keys:
        if isinstance(result, dict):
            result = result.get(k, '')
        else:
            result = ''
            break
    print(result if result is not None else '')
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

# ══════════════════════════════════════════════════════════════
# JSON 검증
# ══════════════════════════════════════════════════════════════

# JSON 유효성 검사
# 사용법: if json_validate "$json"; then echo "valid"; fi
json_validate() {
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

# JSON이고 특정 필드가 있는지 확인
# 사용법: if json_has_field "$json" "ok"; then ...
json_has_field() {
    local json="$1"
    local field="$2"

    python3 -c "
import json
import sys

try:
    data = json.loads(sys.argv[1])
    if '$field' in data:
        sys.exit(0)
    sys.exit(1)
except:
    sys.exit(1)
" "$json" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# JSON 생성
# ══════════════════════════════════════════════════════════════

# key=value 쌍으로 JSON 객체 생성
# 사용법: json=$(json_create "name=test" "score=85" "active=true")
json_create() {
    local args=("$@")

    python3 -c "
import json
import sys

result = {}
for arg in sys.argv[1:]:
    if '=' in arg:
        key, value = arg.split('=', 1)
        # 타입 추론
        if value.lower() == 'true':
            result[key] = True
        elif value.lower() == 'false':
            result[key] = False
        elif value.isdigit():
            result[key] = int(value)
        else:
            try:
                result[key] = float(value)
            except:
                result[key] = value

print(json.dumps(result, ensure_ascii=False))
" "${args[@]}" 2>/dev/null
}

# JSON 문자열 이스케이프
# 사용법: escaped=$(json_escape "$value")
json_escape() {
    local value="$1"
    python3 -c "import json; print(json.dumps('''$value'''))" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# JSON 파일 I/O
# ══════════════════════════════════════════════════════════════

# JSON 파일 읽기 (전체)
# 사용법: json=$(json_read_file "/path/to/file.json")
json_read_file() {
    local file="$1"

    if [[ -f "$file" ]]; then
        cat "$file"
    else
        echo "{}"
    fi
}

# JSON 파일 쓰기 (atomic write)
# 사용법: json_write_file "/path/to/file.json" "$json"
json_write_file() {
    local file="$1"
    local json="$2"
    local tmp="${file}.tmp.$$"

    # 디렉토리 확인
    mkdir -p "$(dirname "$file")"

    # atomic write: 임시 파일에 쓰고 mv
    if echo "$json" > "$tmp" && mv "$tmp" "$file"; then
        return 0
    else
        rm -f "$tmp"
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════
# Envelope 패턴 지원
# ══════════════════════════════════════════════════════════════

# 응답이 Envelope 형식인지 확인 (ok 필드 존재)
# 사용법: if json_is_envelope "$response"; then ...
json_is_envelope() {
    local response="$1"

    python3 -c "
import json
import sys

try:
    obj = json.loads(sys.argv[1])
    if 'ok' in obj and isinstance(obj['ok'], bool):
        sys.exit(0)
    sys.exit(1)
except:
    sys.exit(1)
" "$response" 2>/dev/null
}

# Envelope에서 ok 값 추출
# 사용법: ok=$(json_envelope_ok "$response")  # "true" 또는 "false"
json_envelope_ok() {
    local response="$1"

    python3 -c "
import json
import sys

try:
    obj = json.loads(sys.argv[1])
    print('true' if obj.get('ok', False) else 'false')
except:
    print('false')
" "$response" 2>/dev/null
}

# Envelope에서 result 추출
# 사용법: result=$(json_envelope_result "$response")
json_envelope_result() {
    local response="$1"

    python3 -c "
import json
import sys

try:
    obj = json.loads(sys.argv[1])
    result = obj.get('result', '')
    if isinstance(result, dict):
        print(json.dumps(result, ensure_ascii=False))
    else:
        print(result)
except:
    print('')
" "$response" 2>/dev/null
}

# Envelope 생성 (성공)
# 사용법: envelope=$(json_envelope_ok_create "$result")
json_envelope_ok_create() {
    local result="$1"

    python3 -c "
import json
import sys

result = sys.argv[1] if len(sys.argv) > 1 else ''

# result가 JSON이면 파싱해서 포함
try:
    parsed = json.loads(result)
    envelope = {'ok': True, 'result': parsed}
except:
    envelope = {'ok': True, 'result': result}

print(json.dumps(envelope, ensure_ascii=False))
" "$result" 2>/dev/null
}

# Envelope 생성 (에러)
# 사용법: envelope=$(json_envelope_error_create "TIMEOUT" "요청 시간 초과")
json_envelope_error_create() {
    local code="$1"
    local message="$2"
    local legacy_code="${3:-}"

    python3 -c "
import json

envelope = {
    'ok': False,
    'error': {
        'code': '$code',
        'message': '$message'
    }
}

if '$legacy_code':
    envelope['error']['legacy_code'] = '$legacy_code'

print(json.dumps(envelope, ensure_ascii=False))
" 2>/dev/null
}
