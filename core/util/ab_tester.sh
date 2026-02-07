#!/bin/bash
# ab_tester.sh - Champion/Challenger A/B 테스트 (범용화)
# 기존 projects/*/lib/util/ab_tester.sh를 범용화

AB_TESTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(dirname "$AB_TESTER_DIR")"

# 의존성 로드
source "${CORE_DIR}/prompt/loader.sh"
source "${CORE_DIR}/eval/defect_tracker.sh"

# ══════════════════════════════════════════════════════════════
# 경로 설정
# ══════════════════════════════════════════════════════════════

_ab_suites_dir() {
    echo "${PROJECT_DIR}/suites"
}

_ab_results_file() {
    echo "${PROJECT_DIR}/logs/ab_test_results.jsonl"
}

# ══════════════════════════════════════════════════════════════
# Suite 로드
# ══════════════════════════════════════════════════════════════

# Suite 파일 로드
ab_load_suite() {
    local suite_name="${1:-suite_5}"
    local suites_dir=$(_ab_suites_dir)
    local suite_file="${suites_dir}/${suite_name}.json"

    if [[ ! -f "$suite_file" ]]; then
        echo "ERROR: Suite file not found: $suite_file" >&2
        return 1
    fi

    cat "$suite_file"
}

# Suite 샘플 목록 가져오기
ab_get_suite_samples() {
    local suite_name="${1:-suite_5}"

    local suite
    suite=$(ab_load_suite "$suite_name") || return 1

    echo "$suite" | python3 -c "
import json, sys
data = json.load(sys.stdin)
samples = data.get('samples', [])
print(json.dumps(samples, ensure_ascii=False))
"
}

# 통과 기준 가져오기
ab_get_pass_criteria() {
    local suite_name="${1:-suite_5}"

    local suite
    suite=$(ab_load_suite "$suite_name") || return 1

    echo "$suite" | python3 -c "
import json, sys
data = json.load(sys.stdin)
criteria = data.get('pass_criteria', {})
gates = data.get('absolute_gates', {})
print(json.dumps({'pass_criteria': criteria, 'absolute_gates': gates}, ensure_ascii=False))
"
}

# ══════════════════════════════════════════════════════════════
# 평가 실행
# ══════════════════════════════════════════════════════════════

# 단일 샘플 평가 (Evaluator Frozen 사용)
ab_evaluate_sample() {
    local sample_id="$1"
    local sample_file="$2"
    local section_id="$3"

    local suites_dir=$(_ab_suites_dir)
    local full_path="${suites_dir}/${sample_file}"

    if [[ ! -f "$full_path" ]]; then
        echo "ERROR: Sample file not found: $full_path" >&2
        return 1
    fi

    local content
    content=$(cat "$full_path")

    # Evaluator Frozen으로 평가
    local prompt
    prompt=$(prompt_load_evaluator "$section_id" "$content" "" "true")

    # LLM 호출 (llm_call 사용)
    if type llm_call &>/dev/null; then
        local eval_response
        eval_response=$(llm_call openai --mode=continue "$prompt")
        echo "$eval_response"
    else
        echo "ERROR: LLM not available - llm_call function not found" >&2
        return 1
    fi
}

# Suite 전체 평가
ab_evaluate_suite() {
    local suite_name="${1:-suite_5}"
    local prompt_version="$2"  # 테스트할 프롬프트 버전

    local samples
    samples=$(ab_get_suite_samples "$suite_name") || return 1

    echo "$samples" | python3 -c "
import json, sys

samples = json.load(sys.stdin)
for s in samples:
    print(json.dumps(s, ensure_ascii=False))
" | while read -r sample_json; do
        local sample_id section file
        sample_id=$(echo "$sample_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id', ''))")
        section=$(echo "$sample_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('section', ''))")
        file=$(echo "$sample_json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('file', ''))")

        # 샘플 평가
        local result
        result=$(ab_evaluate_sample "$sample_id" "$file" "$section")
        echo "$result"
    done
}

# ══════════════════════════════════════════════════════════════
# A/B 비교
# ══════════════════════════════════════════════════════════════

# Champion vs Challenger 비교
ab_compare_champion_challenger() {
    local suite_name="${1:-suite_5}"
    local prompt_type="${2:-writer}"

    local champion_version challenger_version

    if [[ "$prompt_type" == "writer" ]]; then
        champion_version=$(get_active_writer_version "champion")
        challenger_version=$(get_active_writer_version "challenger")
    else
        champion_version=$(get_active_evaluator_version "live")
        challenger_version=$(get_active_evaluator_version "challenger")
    fi

    if [[ -z "$challenger_version" || "$challenger_version" == "null" ]]; then
        echo "ERROR: No challenger version to compare" >&2
        return 1
    fi

    echo "=== A/B Test: $champion_version vs $challenger_version ===" >&2

    # Champion 평가
    echo "Evaluating Champion ($champion_version)..." >&2
    local champion_results
    champion_results=$(ab_evaluate_suite "$suite_name" "$champion_version")

    # Challenger 평가
    echo "Evaluating Challenger ($challenger_version)..." >&2
    local challenger_results
    challenger_results=$(ab_evaluate_suite "$suite_name" "$challenger_version")

    # 결과 비교
    _ab_compare_results "$champion_version" "$challenger_version" "$champion_results" "$challenger_results"
}

# 결과 비교 (내부 함수)
_ab_compare_results() {
    local champion_version="$1"
    local challenger_version="$2"
    local champion_results="$3"
    local challenger_results="$4"

    python3 <<PYEOF
import json

# 결과 파싱 (실제 구현에서는 결과 수집)
champion_results = []
challenger_results = []

# 비교 분석
def analyze_results(results):
    scores = [r.get('score', 0) for r in results]
    all_tags = []
    for r in results:
        all_tags.extend(r.get('tags', []))

    return {
        'avg_score': sum(scores) / len(scores) if scores else 0,
        'total_tags': len(all_tags),
        'tag_frequency': {}
    }

champion_stats = analyze_results(champion_results)
challenger_stats = analyze_results(challenger_results)

comparison = {
    'champion': {
        'version': '$champion_version',
        'avg_score': round(champion_stats['avg_score'], 2),
        'total_tags': champion_stats['total_tags']
    },
    'challenger': {
        'version': '$challenger_version',
        'avg_score': round(challenger_stats['avg_score'], 2),
        'total_tags': challenger_stats['total_tags']
    },
    'improvement': {
        'score_diff': round(challenger_stats['avg_score'] - champion_stats['avg_score'], 2),
        'tag_reduction': champion_stats['total_tags'] - challenger_stats['total_tags']
    },
    'verdict': ''
}

# 승격 판정
score_improved = comparison['improvement']['score_diff'] >= 2
tags_reduced = comparison['improvement']['tag_reduction'] >= 0

if score_improved and tags_reduced:
    comparison['verdict'] = 'PROMOTE'
    comparison['reason'] = f"점수 +{comparison['improvement']['score_diff']}점, 태그 -{comparison['improvement']['tag_reduction']}개"
elif score_improved:
    comparison['verdict'] = 'REVIEW'
    comparison['reason'] = '점수는 개선되었으나 태그 증가'
else:
    comparison['verdict'] = 'REJECT'
    comparison['reason'] = f"점수 개선 부족 ({comparison['improvement']['score_diff']}점)"

print(json.dumps(comparison, ensure_ascii=False, indent=2))
PYEOF
}

# ══════════════════════════════════════════════════════════════
# 승격/폐기 결정
# ══════════════════════════════════════════════════════════════

# 테스트 결과에 따른 승격
ab_promote_if_passed() {
    local test_result="$1"
    local prompt_type="${2:-writer}"

    local verdict
    verdict=$(echo "$test_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('verdict', 'UNKNOWN'))")

    if [[ "$verdict" == "PROMOTE" ]]; then
        echo "Verdict: PROMOTE - Challenger 승격" >&2
        prompt_promote_challenger "$prompt_type"
        return 0
    elif [[ "$verdict" == "REVIEW" ]]; then
        echo "Verdict: REVIEW - 수동 검토 필요" >&2
        return 2
    else
        echo "Verdict: REJECT - Challenger 폐기" >&2
        prompt_discard_challenger "$prompt_type"
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════
# 결과 기록
# ══════════════════════════════════════════════════════════════

# A/B 테스트 결과 기록
ab_log_result() {
    local result="$1"

    local results_file=$(_ab_results_file)
    mkdir -p "$(dirname "$results_file")"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    python3 -c "
import json

result = json.loads('''$result''')
result['timestamp'] = '$timestamp'

print(json.dumps(result, ensure_ascii=False))
" >> "$results_file"

    echo "Logged A/B test result" >&2
}

# 결과 조회
ab_get_results() {
    local limit="${1:-10}"

    local results_file=$(_ab_results_file)

    if [[ ! -f "$results_file" ]]; then
        echo "[]"
        return
    fi

    tail -n "$limit" "$results_file" | python3 -c "
import json, sys

results = []
for line in sys.stdin:
    line = line.strip()
    if line:
        try:
            results.append(json.loads(line))
        except:
            pass

print(json.dumps(results, ensure_ascii=False, indent=2))
"
}

# ══════════════════════════════════════════════════════════════
# 통합 워크플로우
# ══════════════════════════════════════════════════════════════

# 전체 A/B 테스트 워크플로우
ab_run_workflow() {
    local suite_name="${1:-suite_5}"
    local prompt_type="${2:-writer}"

    echo "=== A/B Test Workflow ===" >&2

    # 1. Challenger 확인
    local challenger
    if [[ "$prompt_type" == "writer" ]]; then
        challenger=$(get_active_writer_version "challenger")
    else
        challenger=$(get_active_evaluator_version "challenger")
    fi

    if [[ -z "$challenger" || "$challenger" == "null" ]]; then
        echo "No challenger to test" >&2
        return 0
    fi

    # 2. 비교 실행
    local comparison
    comparison=$(ab_compare_champion_challenger "$suite_name" "$prompt_type")
    echo "$comparison"

    # 3. 결과 기록
    ab_log_result "$comparison"

    # 4. 판정
    ab_promote_if_passed "$comparison" "$prompt_type"
    local verdict_code=$?

    return $verdict_code
}

# ══════════════════════════════════════════════════════════════
# 호환성 레이어
# ══════════════════════════════════════════════════════════════

# 기존 함수명 호환
load_suite() {
    ab_load_suite "$@"
}

get_suite_samples() {
    ab_get_suite_samples "$@"
}

compare_champion_challenger() {
    ab_compare_champion_challenger "$@"
}

run_ab_test_workflow() {
    ab_run_workflow "$@"
}

# 직접 실행 시
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "A/B Tester (Core)"
    echo ""
    echo "함수:"
    echo "  ab_load_suite <name>                  Suite 로드"
    echo "  ab_get_suite_samples <name>           샘플 목록"
    echo "  ab_evaluate_sample <id> <file> <sec>  샘플 평가"
    echo "  ab_compare_champion_challenger <suite> 비교"
    echo "  ab_promote_if_passed <result>         승격 결정"
    echo "  ab_run_workflow <suite>               전체 워크플로우"
    echo ""
    echo "환경변수 필요:"
    echo "  PROJECT_DIR - 프로젝트 디렉토리"
fi
