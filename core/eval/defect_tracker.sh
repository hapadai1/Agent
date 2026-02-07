#!/bin/bash
# defect_tracker.sh - 결함 태그 추적 (범용화)
# Evaluator JSON 응답 파싱 및 결함 히스토리 관리
# 기존 projects/*/lib/eval/defect_tracker.sh를 범용화

DEFECT_TRACKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ══════════════════════════════════════════════════════════════
# 경로 설정
# ══════════════════════════════════════════════════════════════

_defect_logs_dir() {
    echo "${PROJECT_DIR}/logs"
}

_defect_history_file() {
    echo "${PROJECT_DIR}/logs/defect_history.jsonl"
}

_defect_proposed_tags_file() {
    echo "${PROJECT_DIR}/prompts/tags/proposed_tags.jsonl"
}

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

# JSON 블록 추출
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
" 2>/dev/null
}

# JSON에서 값 추출
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
# 결함 기록
# ══════════════════════════════════════════════════════════════

# 결함 히스토리 기록
defect_log() {
    local section_id="$1"
    local iteration="$2"
    local eval_json="$3"

    if [[ -z "$eval_json" ]]; then
        echo "Warning: Empty evaluation JSON" >&2
        return 1
    fi

    local logs_dir=$(_defect_logs_dir)
    local history_file=$(_defect_history_file)
    mkdir -p "$logs_dir"

    # 값 추출
    local total_score defect_tags proposed_tags scores_by_criteria priority_fix
    total_score=$(get_json_value "$eval_json" "total_score")
    defect_tags=$(get_json_value "$eval_json" "defect_tags")
    proposed_tags=$(get_json_value "$eval_json" "proposed_tags")
    scores_by_criteria=$(get_json_value "$eval_json" "scores_by_criteria")
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
" >> "$history_file"

    echo "Logged defect: ${section_id} iter ${iteration}, score=${total_score}" >&2

    # Proposed 태그 별도 기록
    if [[ -n "$proposed_tags" && "$proposed_tags" != "[]" ]]; then
        _defect_log_proposed_tags "$section_id" "$proposed_tags"
    fi
}

# 제안된 태그 기록
_defect_log_proposed_tags() {
    local section_id="$1"
    local proposed_tags="$2"

    local proposed_file=$(_defect_proposed_tags_file)
    mkdir -p "$(dirname "$proposed_file")"

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
" >> "$proposed_file"
}

# ══════════════════════════════════════════════════════════════
# 통계 분석
# ══════════════════════════════════════════════════════════════

# 최근 K회 결함 통계
defect_analyze_history() {
    local section_id="$1"
    local k="${2:-5}"

    local history_file=$(_defect_history_file)

    if [[ ! -f "$history_file" ]]; then
        echo "{}"
        return
    fi

    python3 -c "
import json
from collections import Counter

entries = []
with open('$history_file', 'r', encoding='utf-8') as f:
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

entries = entries[-$k:]

if not entries:
    print('{}')
    exit(0)

scores = [e.get('score', 0) for e in entries]
all_tags = []
for e in entries:
    all_tags.extend(e.get('tags', []))

tag_counter = Counter(all_tags)

# 연속 발생 태그
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

result = {
    'section': '$section_id',
    'sample_count': len(entries),
    'scores': scores,
    'avg_score': sum(scores) / len(scores) if scores else 0,
    'latest_score': scores[-1] if scores else 0,
    'score_trend': score_trend,
    'tag_frequency': dict(tag_counter),
    'top_tags': [t[0] for t in tag_counter.most_common(3)],
    'consecutive_tags': consecutive_tags
}

print(json.dumps(result, ensure_ascii=False))
" 2>/dev/null
}

# 전체 섹션 통계
defect_analyze_all_sections() {
    local history_file=$(_defect_history_file)

    if [[ ! -f "$history_file" ]]; then
        echo "{}"
        return
    fi

    python3 -c "
import json
from collections import Counter, defaultdict

section_data = defaultdict(list)

with open('$history_file', 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
            section_data[entry.get('section', 'unknown')].append(entry)
        except:
            pass

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
" 2>/dev/null
}

# 태그 빈도
defect_get_tag_frequency() {
    local tag_id="$1"
    local section_id="${2:-}"

    local history_file=$(_defect_history_file)

    if [[ ! -f "$history_file" ]]; then
        echo "0"
        return
    fi

    python3 -c "
import json

count = 0
with open('$history_file', 'r', encoding='utf-8') as f:
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
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 게이트 체크
# ══════════════════════════════════════════════════════════════

# 절대 게이트 통과 여부 확인
defect_check_gate() {
    local eval_json="$1"
    local min_score="${2:-75}"

    python3 -c "
import json

data = json.loads('''$eval_json''')

score = data.get('total_score', 0)
tags = data.get('defect_tags', [])

gates = {
    'min_score': score >= $min_score,
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
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 호환성 레이어
# ══════════════════════════════════════════════════════════════

# 기존 함수명 호환
log_defect() {
    defect_log "$@"
}

analyze_defect_history() {
    defect_analyze_history "$@"
}

check_absolute_gate() {
    defect_check_gate "$@"
}

# 직접 실행 시
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Defect Tracker (Core)"
    echo ""
    echo "함수:"
    echo "  extract_json_from_response <response>     JSON 추출"
    echo "  get_json_value <json> <key>               값 추출"
    echo "  defect_log <section> <iter> <json>        결함 기록"
    echo "  defect_analyze_history <section> [k]      히스토리 분석"
    echo "  defect_analyze_all_sections               전체 통계"
    echo "  defect_get_tag_frequency <tag> [section]  태그 빈도"
    echo "  defect_check_gate <json> [min_score]      게이트 체크"
    echo ""
    echo "환경변수 필요:"
    echo "  PROJECT_DIR - 프로젝트 디렉토리"
fi
