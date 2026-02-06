#!/bin/bash
# state.sh - JSON 상태 관리 (jq 또는 python3 사용)

# jq 사용 가능 여부 확인
if command -v jq &>/dev/null; then
    _JSON_TOOL="jq"
else
    _JSON_TOOL="python3"
fi

# 상태 값 읽기
# 사용법: state_get ".sections.overview.score"
state_get() {
    local path="$1"
    if [[ "$_JSON_TOOL" == "jq" ]]; then
        jq -r "$path // empty" "$STATE_FILE" 2>/dev/null
    else
        python3 -c "
import json, sys
try:
    with open('$STATE_FILE') as f:
        d = json.load(f)
    path = '$path'.lstrip('.').replace('\"', '').split('.')
    v = d
    for p in path:
        if p:
            v = v[p] if isinstance(v, dict) else v[int(p)]
    print(v if v is not None else '')
except:
    print('')
" 2>/dev/null
    fi
}

# 상태 값 설정
# 사용법: state_set ".sections.overview.score" "85"
state_set() {
    local path="$1"
    local value="$2"
    local tmp="${STATE_FILE}.tmp"

    if [[ "$_JSON_TOOL" == "jq" ]]; then
        # 값 타입 판별
        if [[ "$value" =~ ^-?[0-9]+$ ]]; then
            jq "$path = $value" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
        elif [[ "$value" == "true" || "$value" == "false" || "$value" == "null" ]]; then
            jq "$path = $value" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
        elif [[ "$value" == "["* || "$value" == "{"* ]]; then
            jq "$path = $value" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
        else
            jq "$path = \"$value\"" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
        fi
        # 타임스탬프 갱신
        jq ".updated_at = \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\"" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    else
        python3 -c "
import json
with open('$STATE_FILE') as f:
    d = json.load(f)

path = '$path'.lstrip('.').replace('\"', '').split('.')
val = '$value'

# 타입 변환
if val.lstrip('-').isdigit():
    val = int(val)
elif val in ('true', 'false'):
    val = val == 'true'
elif val == 'null':
    val = None
elif val.startswith('[') or val.startswith('{'):
    val = json.loads(val)

# 경로 탐색 및 설정
obj = d
for p in path[:-1]:
    if p:
        obj = obj[p]
key = path[-1]
if key:
    obj[key] = val

# 타임스탬프 갱신
from datetime import datetime
d['updated_at'] = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')

with open('$STATE_FILE', 'w') as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
"
    fi
}

# 배열에 값 추가
# 사용법: state_append ".research_completed" "\"market_size\""
state_append() {
    local path="$1"
    local value="$2"
    local tmp="${STATE_FILE}.tmp"

    if [[ "$_JSON_TOOL" == "jq" ]]; then
        jq "$path += [$value]" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    else
        python3 -c "
import json
with open('$STATE_FILE') as f:
    d = json.load(f)
path = '$path'.lstrip('.').replace('\"', '').split('.')
val = $value
obj = d
for p in path[:-1]:
    if p: obj = obj[p]
key = path[-1]
if key: obj[key].append(val)
with open('$STATE_FILE', 'w') as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
"
    fi
}

# 상태 파일 초기화
# 사용법: init_state "AI 재고관리 플랫폼"
init_state() {
    local topic="$1"

    cat > "$STATE_FILE" <<STATEEOF
{
  "created_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "updated_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "global_state": "INIT",
  "topic": "${topic}",
  "user_context": {
    "business_type": "",
    "tech_field": "",
    "app_type": "",
    "gov_fund": 0,
    "closure_count": 0,
    "template_uploaded": false,
    "context_sent": false
  },
  "chatgpt": {
    "window": 1,
    "tab": 1,
    "default_timeout": 120,
    "research_timeout": 600
  },
  "sections": {
    "overview":         {"state":"pending","iteration":0,"score":0,"needs_human":false,"needs_research":false,"file":"section_overview.md"},
    "product_summary":  {"state":"pending","iteration":0,"score":0,"needs_human":false,"needs_research":false,"file":"section_product_summary.md"},
    "closure_details":  {"state":"pending","iteration":0,"score":0,"needs_human":true, "needs_research":false,"file":"section_closure_details.md"},
    "s1_1":              {"state":"pending","iteration":0,"score":0,"needs_human":true, "needs_research":false,"file":"section_1_1.md"},
    "s1_2":              {"state":"pending","iteration":0,"score":0,"needs_human":false,"needs_research":false,"file":"section_1_2.md"},
    "s1_3":              {"state":"pending","iteration":0,"score":0,"needs_human":false,"needs_research":true, "file":"section_1_3.md"},
    "s2_1":              {"state":"pending","iteration":0,"score":0,"needs_human":false,"needs_research":false,"file":"section_2_1.md"},
    "s2_2":              {"state":"pending","iteration":0,"score":0,"needs_human":false,"needs_research":false,"file":"section_2_2.md"},
    "s3_1":              {"state":"pending","iteration":0,"score":0,"needs_human":false,"needs_research":true, "file":"section_3_1.md"},
    "s3_2":              {"state":"pending","iteration":0,"score":0,"needs_human":false,"needs_research":true, "file":"section_3_2.md"},
    "s3_3":              {"state":"pending","iteration":0,"score":0,"needs_human":false,"needs_research":false,"file":"section_3_3.md"},
    "s4_1":              {"state":"pending","iteration":0,"score":0,"needs_human":true, "needs_research":false,"file":"section_4_1.md"},
    "s4_2":              {"state":"pending","iteration":0,"score":0,"needs_human":false,"needs_research":false,"file":"section_4_2.md"}
  },
  "overall_score": 0,
  "max_iterations_per_section": 5,
  "target_score": 85,
  "research_completed": []
}
STATEEOF
}

# 상태 파일 로드 확인
load_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo "오류: 상태 파일이 없습니다: $STATE_FILE"
        return 1
    fi

    # 기본 유효성 검사
    if ! state_get ".created_at" &>/dev/null; then
        echo "오류: 상태 파일이 손상되었습니다"
        return 1
    fi

    echo "상태 파일 로드 완료: $STATE_FILE"
    echo "  생성: $(state_get '.created_at')"
    echo "  상태: $(state_get '.global_state')"
    echo "  주제: $(state_get '.topic')"
}
