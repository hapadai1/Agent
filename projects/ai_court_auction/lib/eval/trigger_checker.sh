#!/bin/bash
# trigger_checker.sh - 프롬프트 개선 트리거 조건 체크
# Phase 3: 프롬프트 자동개선 시스템

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$LIB_DIR")"

# defect_tracker.sh 로드
source "${SCRIPT_DIR}/defect_tracker.sh"

# ══════════════════════════════════════════════════════════════
# 트리거 조건 정의
# ══════════════════════════════════════════════════════════════

# 트리거 조건 상수
TRIGGER_CONSECUTIVE_TAG_COUNT=2        # 동일 태그 N회 연속
TRIGGER_LOW_SCORE_COUNT=2              # 저점수 N회 연속
TRIGGER_LOW_SCORE_THRESHOLD=75         # 저점수 기준
TRIGGER_STAGNATION_COUNT=3             # 정체 N회
TRIGGER_STAGNATION_THRESHOLD=2         # 개선폭 N점 이하면 정체
TRIGGER_PROPOSED_TAG_MIN=3             # 제안 태그 승격 기준 N회
TRIGGER_CRITERIA_THRESHOLD=15          # 세부 항목 최소 점수 (20점 만점 기준)

# ══════════════════════════════════════════════════════════════
# 트리거 체크 함수들
# ══════════════════════════════════════════════════════════════

# 트리거 1: 동일 defect_tag가 2회 연속
check_consecutive_tag_trigger() {
    local section_id="$1"

    local stats
    stats=$(analyze_defect_history "$section_id" 5)

    python3 -c "
import json

stats = json.loads('''$stats''')
consecutive = stats.get('consecutive_tags', [])
sample_count = stats.get('sample_count', 0)

if sample_count < 2:
    print(json.dumps({'triggered': False, 'reason': 'insufficient_data'}))
    exit(0)

if consecutive:
    print(json.dumps({
        'triggered': True,
        'trigger_type': 'CONSECUTIVE_TAG',
        'tags': consecutive,
        'reason': f'동일 태그 연속 발생: {consecutive}'
    }))
else:
    print(json.dumps({'triggered': False, 'reason': 'no_consecutive_tags'}))
"
}

# 트리거 2: 특정 항목 점수가 임계치 이하 2회 연속
check_low_criteria_trigger() {
    local section_id="$1"
    local threshold="${2:-$TRIGGER_CRITERIA_THRESHOLD}"

    if [[ ! -f "$DEFECT_HISTORY_FILE" ]]; then
        echo '{"triggered": false, "reason": "no_history"}'
        return
    fi

    python3 -c "
import json

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

# 최근 2개
entries = entries[-2:]

if len(entries) < 2:
    print(json.dumps({'triggered': False, 'reason': 'insufficient_data'}))
    exit(0)

threshold = $threshold
low_criteria = []

# 연속으로 낮은 항목 찾기
for criteria in ['완성도', '구체성', '논리성', '차별성']:
    scores = [e.get('scores_by_criteria', {}).get(criteria, 20) for e in entries]
    if all(s < threshold for s in scores):
        low_criteria.append({'criteria': criteria, 'scores': scores})

if low_criteria:
    print(json.dumps({
        'triggered': True,
        'trigger_type': 'LOW_CRITERIA',
        'low_criteria': low_criteria,
        'reason': f'세부 항목 연속 저점수: {[c[\"criteria\"] for c in low_criteria]}'
    }))
else:
    print(json.dumps({'triggered': False, 'reason': 'criteria_ok'}))
"
}

# 트리거 3: 총점 3회 정체 (개선폭 미미)
check_stagnation_trigger() {
    local section_id="$1"
    local min_improvement="${2:-$TRIGGER_STAGNATION_THRESHOLD}"

    local stats
    stats=$(analyze_defect_history "$section_id" "$TRIGGER_STAGNATION_COUNT")

    python3 -c "
import json

stats = json.loads('''$stats''')
scores = stats.get('scores', [])
sample_count = stats.get('sample_count', 0)

if sample_count < $TRIGGER_STAGNATION_COUNT:
    print(json.dumps({'triggered': False, 'reason': 'insufficient_data'}))
    exit(0)

# 최근 N회 점수 변화 확인
improvements = [scores[i] - scores[i-1] for i in range(1, len(scores))]
max_improvement = max(improvements) if improvements else 0
total_improvement = scores[-1] - scores[0]

# 모든 개선폭이 threshold 이하면 정체
stagnant = all(abs(imp) <= $min_improvement for imp in improvements)

if stagnant and total_improvement <= $min_improvement:
    print(json.dumps({
        'triggered': True,
        'trigger_type': 'STAGNATION',
        'scores': scores,
        'improvements': improvements,
        'reason': f'점수 정체: 최근 {len(scores)}회 개선폭 {total_improvement}점'
    }))
else:
    print(json.dumps({
        'triggered': False,
        'reason': 'improving',
        'total_improvement': total_improvement
    }))
"
}

# 트리거 4: 총점 임계치 미만 2회 연속
check_low_score_trigger() {
    local section_id="$1"
    local threshold="${2:-$TRIGGER_LOW_SCORE_THRESHOLD}"

    local stats
    stats=$(analyze_defect_history "$section_id" "$TRIGGER_LOW_SCORE_COUNT")

    python3 -c "
import json

stats = json.loads('''$stats''')
scores = stats.get('scores', [])
sample_count = stats.get('sample_count', 0)

if sample_count < $TRIGGER_LOW_SCORE_COUNT:
    print(json.dumps({'triggered': False, 'reason': 'insufficient_data'}))
    exit(0)

# 최근 N회 모두 임계치 미만인지
recent_scores = scores[-$TRIGGER_LOW_SCORE_COUNT:]
all_low = all(s < $threshold for s in recent_scores)

if all_low:
    print(json.dumps({
        'triggered': True,
        'trigger_type': 'LOW_SCORE',
        'scores': recent_scores,
        'threshold': $threshold,
        'reason': f'연속 저점수: 최근 {len(recent_scores)}회 모두 {$threshold}점 미만'
    }))
else:
    print(json.dumps({'triggered': False, 'reason': 'score_ok'}))
"
}

# 트리거 5: Proposed 태그 승격 검토 (3회 이상 반복)
check_proposed_tag_promotion() {
    local min_occurrences="${1:-$TRIGGER_PROPOSED_TAG_MIN}"

    if [[ ! -f "$PROPOSED_TAGS_FILE" ]]; then
        echo '{"triggered": false, "reason": "no_proposed_tags"}'
        return
    fi

    python3 -c "
import json
from collections import Counter

tags = []
with open('$PROPOSED_TAGS_FILE', 'r', encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
            if entry.get('status') == 'pending':
                tags.append(entry.get('tag'))
        except:
            pass

counter = Counter(tags)
promote_candidates = [tag for tag, count in counter.items() if count >= $min_occurrences]

if promote_candidates:
    print(json.dumps({
        'triggered': True,
        'trigger_type': 'PROPOSED_TAG_PROMOTION',
        'candidates': promote_candidates,
        'counts': {t: counter[t] for t in promote_candidates},
        'reason': f'승격 후보 태그: {promote_candidates}'
    }))
else:
    print(json.dumps({'triggered': False, 'reason': 'no_promotion_candidates'}))
"
}

# ══════════════════════════════════════════════════════════════
# 통합 트리거 체크
# ══════════════════════════════════════════════════════════════

# 모든 트리거 조건 체크
check_all_triggers() {
    local section_id="$1"

    local triggers=()
    local any_triggered=false

    # 각 트리거 체크
    local consecutive_result
    consecutive_result=$(check_consecutive_tag_trigger "$section_id")
    if [[ $(echo "$consecutive_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('triggered', False))") == "True" ]]; then
        triggers+=("$consecutive_result")
        any_triggered=true
    fi

    local low_criteria_result
    low_criteria_result=$(check_low_criteria_trigger "$section_id")
    if [[ $(echo "$low_criteria_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('triggered', False))") == "True" ]]; then
        triggers+=("$low_criteria_result")
        any_triggered=true
    fi

    local stagnation_result
    stagnation_result=$(check_stagnation_trigger "$section_id")
    if [[ $(echo "$stagnation_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('triggered', False))") == "True" ]]; then
        triggers+=("$stagnation_result")
        any_triggered=true
    fi

    local low_score_result
    low_score_result=$(check_low_score_trigger "$section_id")
    if [[ $(echo "$low_score_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('triggered', False))") == "True" ]]; then
        triggers+=("$low_score_result")
        any_triggered=true
    fi

    # Proposed 태그 승격은 섹션 무관
    local promotion_result
    promotion_result=$(check_proposed_tag_promotion)
    if [[ $(echo "$promotion_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('triggered', False))") == "True" ]]; then
        triggers+=("$promotion_result")
        any_triggered=true
    fi

    # 결과 조합
    python3 -c "
import json

triggers = []
for t in '''${triggers[*]}'''.split():
    if t:
        try:
            triggers.append(json.loads(t))
        except:
            pass

result = {
    'section': '$section_id',
    'any_triggered': $([[ "$any_triggered" == "true" ]] && echo "True" || echo "False"),
    'trigger_count': len([t for t in triggers if t.get('triggered')]),
    'triggers': triggers
}

print(json.dumps(result, ensure_ascii=False, indent=2))
"
}

# Critic 호출 여부 결정
should_trigger_critic() {
    local section_id="$1"

    local result
    result=$(check_all_triggers "$section_id")

    local any_triggered
    any_triggered=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('any_triggered', False))")

    if [[ "$any_triggered" == "True" ]]; then
        echo "true"
        return 0
    else
        echo "false"
        return 1
    fi
}

# 트리거 우선순위 결정 (Writer vs Evaluator 중 어느 쪽을 개선할지)
determine_improvement_priority() {
    local section_id="$1"

    local result
    result=$(check_all_triggers "$section_id")

    python3 -c "
import json

result = json.loads('''$result''')
triggers = result.get('triggers', [])

# 우선순위 로직:
# 1. CONSECUTIVE_TAG, LOW_CRITERIA → Writer 개선 우선
# 2. STAGNATION, LOW_SCORE → Writer 또는 Evaluator 검토
# 3. PROPOSED_TAG_PROMOTION → 태그 승격 (별도 처리)

writer_triggers = []
evaluator_triggers = []
tag_triggers = []

for t in triggers:
    if not t.get('triggered'):
        continue
    trigger_type = t.get('trigger_type', '')
    if trigger_type in ['CONSECUTIVE_TAG', 'LOW_CRITERIA']:
        writer_triggers.append(t)
    elif trigger_type in ['STAGNATION', 'LOW_SCORE']:
        # 기본적으로 Writer, 하지만 Evaluator도 검토 필요 표시
        writer_triggers.append(t)
        evaluator_triggers.append({'note': 'consider_evaluator_review', 'trigger': t})
    elif trigger_type == 'PROPOSED_TAG_PROMOTION':
        tag_triggers.append(t)

priority = {
    'primary': 'writer' if writer_triggers else ('evaluator' if evaluator_triggers else 'none'),
    'writer_triggers': len(writer_triggers),
    'evaluator_review_suggested': len(evaluator_triggers) > 0,
    'tag_promotion_pending': len(tag_triggers) > 0,
    'recommendation': ''
}

if writer_triggers:
    priority['recommendation'] = 'Writer 프롬프트 개선 권장'
elif evaluator_triggers:
    priority['recommendation'] = 'Evaluator 검토 권장'
elif tag_triggers:
    priority['recommendation'] = '태그 승격 검토 권장'
else:
    priority['recommendation'] = '개선 불필요'

print(json.dumps(priority, ensure_ascii=False, indent=2))
"
}

# ══════════════════════════════════════════════════════════════
# 테스트
# ══════════════════════════════════════════════════════════════

test_trigger_checker() {
    echo "=== Trigger Checker Test ==="
    echo ""

    # 테스트 데이터 추가
    local test_json='{"total_score": 72, "scores_by_criteria": {"완성도": 14, "구체성": 13, "논리성": 15, "차별성": 12, "제출완성도": 10, "문서형식": 8}, "defect_tags": ["NO_EVIDENCE_OR_CITATION", "VAGUE_CLAIMS"], "proposed_tags": [], "priority_fix": "출처 추가"}'

    echo "--- 테스트 데이터 추가 ---"
    log_defect "trigger_test" 2 "$test_json"
    log_defect "trigger_test" 3 "$test_json"
    echo ""

    echo "--- 개별 트리거 체크 ---"
    echo "1. 연속 태그 트리거:"
    check_consecutive_tag_trigger "trigger_test"
    echo ""

    echo "2. 저점수 항목 트리거:"
    check_low_criteria_trigger "trigger_test"
    echo ""

    echo "3. 정체 트리거:"
    check_stagnation_trigger "trigger_test"
    echo ""

    echo "4. 저점수 트리거:"
    check_low_score_trigger "trigger_test"
    echo ""

    echo "--- 통합 트리거 체크 ---"
    check_all_triggers "trigger_test"
    echo ""

    echo "--- Critic 호출 여부 ---"
    echo "Should trigger Critic: $(should_trigger_critic "trigger_test")"
    echo ""

    echo "--- 개선 우선순위 ---"
    determine_improvement_priority "trigger_test"
}

# 직접 실행 시 테스트
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_trigger_checker
fi
