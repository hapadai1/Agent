#!/bin/bash
# suite_compare.sh - Baseline/Challenger 비교 및 승격 판단
# 사용법: ./suite_compare.sh --date=2026-02-05 --suite=suite-5

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$LIB_DIR")"

# ══════════════════════════════════════════════════════════════
# 인자 파싱
# ══════════════════════════════════════════════════════════════

DATE=$(date +%Y-%m-%d)
SUITE="suite-5"
AUTO_PROMOTE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --date=*)
            DATE="${1#*=}"
            shift
            ;;
        --suite=*)
            SUITE="${1#*=}"
            shift
            ;;
        --auto-promote)
            AUTO_PROMOTE=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# 경로 설정 (TESTING_DIR 환경변수로 테스트 폴더 지정 가능)
TESTING_DIR="${TESTING_DIR:-$PROJECT_DIR}"
RUNS_DIR="${TESTING_DIR}/runs/${DATE}"
REPORTS_DIR="${TESTING_DIR}/reports"
GATES_FILE="${PROJECT_DIR}/config/gates.yaml"
PROMPTS_DIR="${PROJECT_DIR}/prompts"

BASELINE_DIR="${RUNS_DIR}/champion"
CHALLENGER_DIR="${RUNS_DIR}/challenger"
REPORT_FILE="${REPORTS_DIR}/${DATE}_compare_${SUITE}.json"

# ══════════════════════════════════════════════════════════════
# 비교 로직
# ══════════════════════════════════════════════════════════════

compare_results() {
    mkdir -p "$REPORTS_DIR"

    python3 <<'PYEOF'
import json
import yaml
import os
from collections import Counter

# 경로
baseline_dir = os.environ.get('BASELINE_DIR', '')
challenger_dir = os.environ.get('CHALLENGER_DIR', '')
gates_file = os.environ.get('GATES_FILE', '')
report_file = os.environ.get('REPORT_FILE', '')
suite_name = os.environ.get('SUITE', 'suite-5')
date = os.environ.get('DATE', '')

def load_summary(dir_path):
    summary_file = os.path.join(dir_path, 'summary.json')
    if os.path.exists(summary_file):
        with open(summary_file, 'r') as f:
            return json.load(f)
    return None

def load_gates(gates_path):
    if os.path.exists(gates_path):
        with open(gates_path, 'r') as f:
            return yaml.safe_load(f)
    # 기본 게이트
    return {
        'score_gates': {
            'avg_score_improvement': 3,
            'min_absolute_score': 70,
            'max_regression_per_sample': 5
        },
        'defect_gates': {
            'critical_tags': ['MISSING_REQUIRED_ITEM'],
            'critical_tag_max_cases': 0,
            'require_tag_reduction': True
        }
    }

# 데이터 로드
baseline = load_summary(baseline_dir)
challenger = load_summary(challenger_dir)
gates = load_gates(gates_file)

if not baseline:
    print(f"ERROR: Baseline summary not found in {baseline_dir}")
    exit(1)

if not challenger:
    print(f"ERROR: Challenger summary not found in {challenger_dir}")
    exit(1)

# 비교 계산
comparison = {
    'suite': suite_name,
    'date': date,
    'baseline': {
        'writer': baseline.get('writer', 'champion'),
        'avg_score': baseline.get('avg_score', 0),
        'total_tags': baseline.get('total_tags', 0),
        'tag_frequency': baseline.get('tag_frequency', {})
    },
    'challenger': {
        'writer': challenger.get('writer', 'challenger'),
        'avg_score': challenger.get('avg_score', 0),
        'total_tags': challenger.get('total_tags', 0),
        'tag_frequency': challenger.get('tag_frequency', {})
    },
    'improvement': {},
    'gate_checks': {},
    'verdict': ''
}

# 개선도 계산
score_diff = challenger['avg_score'] - baseline['avg_score']
tag_diff = baseline['total_tags'] - challenger['total_tags']

comparison['improvement'] = {
    'score_diff': round(score_diff, 2),
    'tag_reduction': tag_diff
}

# 샘플별 비교
baseline_results = {r['sample_id']: r for r in baseline.get('results', [])}
challenger_results = {r['sample_id']: r for r in challenger.get('results', [])}

sample_comparisons = []
regressions = []

for sample_id in baseline_results:
    b = baseline_results.get(sample_id, {})
    c = challenger_results.get(sample_id, {})

    b_score = b.get('score', 0)
    c_score = c.get('score', 0)
    diff = c_score - b_score

    sc = {
        'sample_id': sample_id,
        'baseline_score': b_score,
        'challenger_score': c_score,
        'diff': diff,
        'baseline_tags': b.get('tags', []),
        'challenger_tags': c.get('tags', [])
    }
    sample_comparisons.append(sc)

    # 점수 하락 체크
    max_regression = gates.get('score_gates', {}).get('max_regression_per_sample', 5)
    if diff < -max_regression:
        regressions.append(sample_id)

comparison['sample_comparisons'] = sample_comparisons

# 게이트 체크
score_gates = gates.get('score_gates', {})
defect_gates = gates.get('defect_gates', {})

gate_results = {}

# 1. 평균 점수 개선
min_improvement = score_gates.get('avg_score_improvement', 3)
gate_results['avg_score_improvement'] = {
    'required': min_improvement,
    'actual': score_diff,
    'passed': score_diff >= min_improvement
}

# 2. 최소 절대 점수
min_absolute = score_gates.get('min_absolute_score', 70)
gate_results['min_absolute_score'] = {
    'required': min_absolute,
    'actual': challenger['avg_score'],
    'passed': challenger['avg_score'] >= min_absolute
}

# 3. 점수 하락
gate_results['no_severe_regression'] = {
    'max_allowed': score_gates.get('max_regression_per_sample', 5),
    'regressions': regressions,
    'passed': len(regressions) == 0
}

# 4. 치명 태그
critical_tags = defect_gates.get('critical_tags', ['MISSING_REQUIRED_ITEM'])
max_critical_cases = defect_gates.get('critical_tag_max_cases', 0)

critical_cases = []
for sc in sample_comparisons:
    for tag in sc['challenger_tags']:
        if tag in critical_tags:
            critical_cases.append(sc['sample_id'])
            break

gate_results['no_critical_tags'] = {
    'critical_tags': critical_tags,
    'max_allowed_cases': max_critical_cases,
    'actual_cases': len(set(critical_cases)),
    'passed': len(set(critical_cases)) <= max_critical_cases
}

# 5. 태그 감소
require_reduction = defect_gates.get('require_tag_reduction', True)
gate_results['tag_reduction'] = {
    'required': require_reduction,
    'reduction': tag_diff,
    'passed': (not require_reduction) or (tag_diff >= 0)
}

comparison['gate_checks'] = gate_results

# 판정
all_passed = all(g['passed'] for g in gate_results.values())

if all_passed:
    comparison['verdict'] = 'PROMOTE'
    comparison['verdict_reason'] = f"모든 게이트 통과: 점수 +{score_diff:.1f}, 태그 -{tag_diff}"
elif score_diff >= 1:
    comparison['verdict'] = 'REVIEW'
    failed_gates = [k for k, v in gate_results.items() if not v['passed']]
    comparison['verdict_reason'] = f"일부 통과, 검토 필요: {failed_gates}"
else:
    comparison['verdict'] = 'REJECT'
    failed_gates = [k for k, v in gate_results.items() if not v['passed']]
    comparison['verdict_reason'] = f"기준 미달: {failed_gates}"

# 저장
with open(report_file, 'w') as f:
    json.dump(comparison, f, indent=2, ensure_ascii=False)

# 출력
print("╔══════════════════════════════════════════════╗")
print("║         Comparison Report                    ║")
print("╚══════════════════════════════════════════════╝")
print()
print(f"Suite:     {suite_name}")
print(f"Date:      {date}")
print()
print("=== Score Comparison ===")
print(f"Baseline:   {comparison['baseline']['avg_score']:.2f}")
print(f"Challenger: {comparison['challenger']['avg_score']:.2f}")
print(f"Improvement: {score_diff:+.2f}")
print()
print("=== Defect Tags ===")
print(f"Baseline:   {comparison['baseline']['total_tags']}")
print(f"Challenger: {comparison['challenger']['total_tags']}")
print(f"Reduction:  {tag_diff:+d}")
print()
print("=== Gate Checks ===")
for gate_name, gate_result in gate_results.items():
    status = "✅" if gate_result['passed'] else "❌"
    print(f"  {status} {gate_name}")
print()
print(f"=== VERDICT: {comparison['verdict']} ===")
print(f"Reason: {comparison['verdict_reason']}")
print()
print(f"Report saved: {report_file}")
PYEOF
}

# ══════════════════════════════════════════════════════════════
# 승격 처리
# ══════════════════════════════════════════════════════════════

promote_challenger() {
    echo ""
    echo "=== Promoting Challenger to Champion ==="

    local champion_file="${PROMPTS_DIR}/writer/champion.md"
    local challenger_file="${PROMPTS_DIR}/writer/challenger.md"
    local history_dir="${PROMPTS_DIR}/writer/history"

    if [[ ! -f "$challenger_file" ]]; then
        echo "ERROR: Challenger file not found: $challenger_file" >&2
        return 1
    fi

    # 현재 champion을 history로 백업
    mkdir -p "$history_dir"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${history_dir}/champion_${timestamp}.md"

    if [[ -f "$champion_file" ]]; then
        cp "$champion_file" "$backup_file"
        echo "Backed up: $backup_file"
    fi

    # challenger를 champion으로
    cp "$challenger_file" "$champion_file"
    echo "Promoted: challenger.md → champion.md"

    # challenger 정리 (선택)
    mv "$challenger_file" "${history_dir}/challenger_${timestamp}.md"
    echo "Archived: challenger.md"

    echo ""
    echo "✅ Promotion complete!"
}

# ══════════════════════════════════════════════════════════════
# 메인 실행
# ══════════════════════════════════════════════════════════════

main() {
    # 환경변수로 Python에 전달
    export BASELINE_DIR CHALLENGER_DIR GATES_FILE REPORT_FILE SUITE DATE

    # 디렉토리 확인
    if [[ ! -d "$BASELINE_DIR" ]]; then
        echo "ERROR: Baseline directory not found: $BASELINE_DIR" >&2
        echo "Run suite_runner.sh --writer=champion first" >&2
        exit 1
    fi

    if [[ ! -d "$CHALLENGER_DIR" ]]; then
        echo "ERROR: Challenger directory not found: $CHALLENGER_DIR" >&2
        echo "Run suite_runner.sh --writer=challenger first" >&2
        exit 1
    fi

    # 비교 실행
    compare_results

    # 자동 승격
    if [[ "$AUTO_PROMOTE" == "true" ]]; then
        local verdict
        verdict=$(python3 -c "import json; print(json.load(open('$REPORT_FILE')).get('verdict', ''))")

        if [[ "$verdict" == "PROMOTE" ]]; then
            promote_challenger
        else
            echo ""
            echo "Auto-promote skipped: verdict is $verdict"
        fi
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
