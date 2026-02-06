#!/bin/bash
# defect_tracker.sh - Evaluator JSON 응답 파싱 및 결함 태그 추적
# Phase 2: 프롬프트 자동개선 시스템

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$LIB_DIR")"
LOGS_DIR="${PROJECT_DIR}/logs"
PROMPTS_DIR="${PROJECT_DIR}/prompts"

DEFECT_HISTORY_FILE="${LOGS_DIR}/defect_history.jsonl"
PROPOSED_TAGS_FILE="${PROMPTS_DIR}/tags/proposed_tags.jsonl"

# ══════════════════════════════════════════════════════════════
# JSON 응답 파싱
# ══════════════════════════════════════════════════════════════

# Evaluator 응답에서 JSON 추출
extract_json_from_response() {
    local response="$1"

    python3 -c "
import re
import json

response = '''$response'''

# JSON 블록 추출 (```json ... ``` 또는 { ... })
json_pattern = r'\`\`\`json\s*([\s\S]*?)\`\`\`'
match = re.search(json_pattern, response)

if match:
    json_str = match.group(1).strip()
else:
    # 직접 JSON 객체 찾기
    brace_pattern = r'\{[\s\S]*\}'
    match = re.search(brace_pattern, response)
    if match:
        json_str = match.group(0)
    else:
        print('')
        exit(0)

try:
    data = json.loads(json_str)
    print(json.dumps(data, ensure_ascii=False))
except json.JSONDecodeError:
    print('')
"
}

# 파싱된 JSON에서 값 추출
get_json_value() {
    local json_str="$1"
    local key="$2"

    python3 -c "
import json
data = json.loads('''$json_str''')
keys = '$key'.split('.')
result = data
for k in keys:
    if result is None:
        break
    if isinstance(result, dict):
        result = result.get(k)
    elif isinstance(result, list) and k.isdigit():
        result = result[int(k)]
    else:
        result = None

if result is not None:
    if isinstance(result, (dict, list)):
        print(json.dumps(result, ensure_ascii=False))
    else:
        print(result)
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 결함 기록 (Logging)
# ══════════════════════════════════════════════════════════════

# 결함 히스토리 기록
log_defect() {
    local section_id="$1"
    local iteration="$2"
    local eval_json="$3"

    # JSON이 비어있으면 스킵
    if [[ -z "$eval_json" ]]; then
        echo "Warning: Empty evaluation JSON, skipping log" >&2
        return 1
    fi

    # 로그 디렉토리 확인
    mkdir -p "$LOGS_DIR"

    # 값 추출
    local total_score
    total_score=$(get_json_value "$eval_json" "total_score")
    local defect_tags
    defect_tags=$(get_json_value "$eval_json" "defect_tags")
    local proposed_tags
    proposed_tags=$(get_json_value "$eval_json" "proposed_tags")
    local scores_by_criteria
    scores_by_criteria=$(get_json_value "$eval_json" "scores_by_criteria")
    local priority_fix
    priority_fix=$(get_json_value "$eval_json" "priority_fix")

    # JSONL 엔트리 생성
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    python3 -c "
import json

entry = {
    'ts': '$timestamp',
    'section': '$section_id',
    'iteration': $iteration,
    'score': ${total_score:-0},
    'scores_by_criteria': ${scores_by_criteria:-'{}'},
    'tags': ${defect_tags:-'[]'},
    'proposed_tags': ${proposed_tags:-'[]'},
    'priority_fix': '''$priority_fix'''
}

print(json.dumps(entry, ensure_ascii=False))
" >> "$DEFECT_HISTORY_FILE"

    echo "Logged defect for ${section_id} iteration ${iteration}: score=${total_score}, tags=${defect_tags}"

    # Proposed 태그가 있으면 별도 기록
    if [[ -n "$proposed_tags" && "$proposed_tags" != "[]" ]]; then
        log_proposed_tags "$section_id" "$proposed_tags"
    fi
}

# 제안된 태그 기록
log_proposed_tags() {
    local section_id="$1"
    local proposed_tags="$2"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    python3 -c "
import json

tags = $proposed_tags
for tag in tags:
    entry = {
        'ts': '$timestamp',
        'section': '$section_id',
        'tag': tag,
        'status': 'pending'
    }
    print(json.dumps(entry, ensure_ascii=False))
" >> "$PROPOSED_TAGS_FILE"
}

# ══════════════════════════════════════════════════════════════
# 통계 분석
# ══════════════════════════════════════════════════════════════

# 최근 K회 결함 통계 분석
analyze_defect_history() {
    local section_id="$1"
    local k="${2:-5}"

    if [[ ! -f "$DEFECT_HISTORY_FILE" ]]; then
        echo "{}"
        return
    fi

    python3 -c "
import json
from collections import Counter

entries = []
with open('$DEFECT_HISTORY_FILE', 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
            if entry.get('section') == '$section_id':
                entries.append(entry)
        except:
            pass

# 최근 K개만
entries = entries[-$k:]

if not entries:
    print('{}')
    exit(0)

# 통계 계산
scores = [e.get('score', 0) for e in entries]
all_tags = []
for e in entries:
    all_tags.extend(e.get('tags', []))

tag_counter = Counter(all_tags)

# 연속 발생 태그 찾기
consecutive_tags = []
if len(entries) >= 2:
    last_tags = set(entries[-1].get('tags', []))
    prev_tags = set(entries[-2].get('tags', []))
    consecutive_tags = list(last_tags & prev_tags)

# 점수 추이
score_trend = 'stable'
if len(scores) >= 2:
    if scores[-1] > scores[-2]:
        score_trend = 'improving'
    elif scores[-1] < scores[-2]:
        score_trend = 'declining'

# 개선폭
improvement = scores[-1] - scores[0] if len(scores) >= 2 else 0

result = {
    'section': '$section_id',
    'sample_count': len(entries),
    'scores': scores,
    'avg_score': sum(scores) / len(scores) if scores else 0,
    'latest_score': scores[-1] if scores else 0,
    'score_trend': score_trend,
    'improvement': improvement,
    'tag_frequency': dict(tag_counter),
    'top_tags': [t[0] for t in tag_counter.most_common(3)],
    'consecutive_tags': consecutive_tags,
    'latest_iteration': entries[-1].get('iteration', 0) if entries else 0
}

print(json.dumps(result, ensure_ascii=False))
"
}

# 전체 섹션 통계
analyze_all_sections() {
    if [[ ! -f "$DEFECT_HISTORY_FILE" ]]; then
        echo "{}"
        return
    fi

    python3 -c "
import json
from collections import Counter, defaultdict

section_data = defaultdict(list)

with open('$DEFECT_HISTORY_FILE', 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
            section_data[entry.get('section', 'unknown')].append(entry)
        except:
            pass

# 섹션별 요약
summary = {}
all_tags = Counter()

for section, entries in section_data.items():
    scores = [e.get('score', 0) for e in entries]
    tags = []
    for e in entries:
        tags.extend(e.get('tags', []))
        all_tags.update(e.get('tags', []))

    summary[section] = {
        'iterations': len(entries),
        'avg_score': sum(scores) / len(scores) if scores else 0,
        'latest_score': scores[-1] if scores else 0,
        'top_tag': Counter(tags).most_common(1)[0][0] if tags else None
    }

result = {
    'sections': summary,
    'global_top_tags': dict(all_tags.most_common(5)),
    'total_iterations': sum(len(v) for v in section_data.values())
}

print(json.dumps(result, ensure_ascii=False, indent=2))
"
}

# 특정 태그의 발생 빈도 확인
get_tag_frequency() {
    local tag_id="$1"
    local section_id="${2:-}"

    if [[ ! -f "$DEFECT_HISTORY_FILE" ]]; then
        echo "0"
        return
    fi

    python3 -c "
import json

count = 0
with open('$DEFECT_HISTORY_FILE', 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
            section = entry.get('section', '')
            tags = entry.get('tags', [])

            if '$section_id' and section != '$section_id':
                continue

            if '$tag_id' in tags:
                count += 1
        except:
            pass

print(count)
"
}

# 연속 발생 태그 감지
detect_consecutive_tags() {
    local section_id="$1"
    local min_consecutive="${2:-2}"

    local stats
    stats=$(analyze_defect_history "$section_id" 5)

    python3 -c "
import json

stats = json.loads('''$stats''')
consecutive = stats.get('consecutive_tags', [])

if len(consecutive) >= 1:
    print(' '.join(consecutive))
else:
    print('')
"
}

# ══════════════════════════════════════════════════════════════
# 절대 게이트 체크 (승격 조건)
# ══════════════════════════════════════════════════════════════

# 절대 게이트 통과 여부 확인
check_absolute_gate() {
    local eval_json="$1"

    # 게이트 조건:
    # 1. total_score >= 75
    # 2. 구체성 >= 15
    # 3. 완성도 >= 16
    # 4. MISSING_REQUIRED_ITEM 없음

    python3 -c "
import json

data = json.loads('''$eval_json''')

score = data.get('total_score', 0)
criteria = data.get('scores_by_criteria', {})
tags = data.get('defect_tags', [])

gates = {
    'min_score': score >= 75,
    'min_specificity': criteria.get('구체성', 0) >= 15,
    'min_completeness': criteria.get('완성도', 0) >= 16,
    'no_critical_tag': 'MISSING_REQUIRED_ITEM' not in tags
}

passed = all(gates.values())
failed_gates = [k for k, v in gates.items() if not v]

result = {
    'passed': passed,
    'gates': gates,
    'failed_gates': failed_gates,
    'score': score
}

print(json.dumps(result, ensure_ascii=False))
"
}

# ══════════════════════════════════════════════════════════════
# 기존 scoring.sh와의 호환성 레이어
# ══════════════════════════════════════════════════════════════

# 기존 parse_score() 대체 (JSON 응답에서 점수 추출)
parse_score_v2() {
    local response="$1"

    local json_str
    json_str=$(extract_json_from_response "$response")

    if [[ -n "$json_str" ]]; then
        get_json_value "$json_str" "total_score"
    else
        # Fallback: 기존 방식으로 파싱 시도
        echo "$response" | grep -oE 'SCORE:\s*([0-9]+)' | grep -oE '[0-9]+' | head -1
    fi
}

# 전체 평가 결과 파싱 (새 버전)
parse_evaluation_v2() {
    local response="$1"

    local json_str
    json_str=$(extract_json_from_response "$response")

    if [[ -n "$json_str" ]]; then
        echo "$json_str"
    else
        # JSON 파싱 실패 시 빈 객체
        echo "{}"
    fi
}

# ══════════════════════════════════════════════════════════════
# 테스트
# ══════════════════════════════════════════════════════════════

test_defect_tracker() {
    echo "=== Defect Tracker Test ==="
    echo ""

    # 테스트용 JSON 응답
    local test_response='```json
{
  "total_score": 78,
  "scores_by_criteria": {
    "완성도": 16,
    "구체성": 14,
    "논리성": 16,
    "차별성": 14,
    "제출완성도": 10,
    "문서형식": 8
  },
  "defect_tags": ["NO_EVIDENCE_OR_CITATION", "VAGUE_CLAIMS"],
  "proposed_tags": [],
  "evidence_anchors": [
    {"location": "2번째 문단", "issue": "시장 규모 출처 없음"}
  ],
  "strengths": ["논리적 구조가 좋음"],
  "weaknesses": [{"issue": "출처 없음", "fix": "출처 추가"}],
  "format_issues": [],
  "priority_fix": "시장 규모 출처 추가",
  "prompt_patch_suggestions": []
}
```'

    echo "--- JSON 추출 테스트 ---"
    local extracted
    extracted=$(extract_json_from_response "$test_response")
    echo "Extracted JSON (first 200 chars): ${extracted:0:200}..."
    echo ""

    echo "--- 값 추출 테스트 ---"
    echo "Total Score: $(get_json_value "$extracted" "total_score")"
    echo "Defect Tags: $(get_json_value "$extracted" "defect_tags")"
    echo "Priority Fix: $(get_json_value "$extracted" "priority_fix")"
    echo ""

    echo "--- 점수 파싱 테스트 ---"
    echo "Score (v2): $(parse_score_v2 "$test_response")"
    echo ""

    echo "--- 게이트 체크 테스트 ---"
    check_absolute_gate "$extracted"
    echo ""

    echo "--- 결함 기록 테스트 ---"
    log_defect "test_section" 1 "$extracted"
    echo ""

    echo "--- 분석 테스트 ---"
    analyze_defect_history "test_section" 5
}

# 직접 실행 시 테스트
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_defect_tracker
fi
