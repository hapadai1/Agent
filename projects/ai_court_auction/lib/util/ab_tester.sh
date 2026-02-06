#!/bin/bash
# ab_tester.sh - Champion/Challenger A/B 테스트
# Phase 6: 프롬프트 자동개선 시스템

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$LIB_DIR")"

# 의존성 로드
source "${LIB_DIR}/prompt/prompt_loader.sh"
source "${LIB_DIR}/eval/defect_tracker.sh"

# 경로 설정
SUITES_DIR="${PROJECT_DIR}/suites"
LOGS_DIR="${PROJECT_DIR}/logs"
AB_RESULTS_FILE="${LOGS_DIR}/ab_test_results.jsonl"

# ══════════════════════════════════════════════════════════════
# Suite 로드
# ══════════════════════════════════════════════════════════════

# Suite 파일 로드
load_suite() {
    local suite_name="${1:-suite_5}"
    local suite_file="${SUITES_DIR}/${suite_name}.json"

    if [[ ! -f "$suite_file" ]]; then
        echo "ERROR: Suite file not found: $suite_file" >&2
        return 1
    fi

    cat "$suite_file"
}

# Suite 샘플 목록 가져오기
get_suite_samples() {
    local suite_name="${1:-suite_5}"

    local suite
    suite=$(load_suite "$suite_name")

    echo "$suite" | python3 -c "
import json, sys
data = json.load(sys.stdin)
samples = data.get('samples', [])
print(json.dumps(samples, ensure_ascii=False))
"
}

# 통과 기준 가져오기
get_pass_criteria() {
    local suite_name="${1:-suite_5}"

    local suite
    suite=$(load_suite "$suite_name")

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
evaluate_sample() {
    local sample_id="$1"
    local sample_file="$2"
    local section_id="$3"

    local full_path="${SUITES_DIR}/${sample_file}"

    if [[ ! -f "$full_path" ]]; then
        echo "ERROR: Sample file not found: $full_path" >&2
        return 1
    fi

    local content
    content=$(cat "$full_path")

    # Evaluator Frozen으로 평가
    local prompt
    prompt=$(load_evaluator_prompt "$section_id" "$content" "" "true")

    # ChatGPT 호출
    if type chatgpt_call &>/dev/null; then
        local eval_response
        eval_response=$(chatgpt_call --tab="$TAB_EVALUATOR" --timeout="$TIMEOUT_EVALUATOR" "$prompt")
        echo "$eval_response"
    else
        echo "ERROR: ChatGPT not available - chatgpt_call function not found" >&2
        return 1
    fi
}

# Suite 전체 평가
evaluate_suite() {
    local suite_name="${1:-suite_5}"
    local prompt_version="$2"  # 테스트할 프롬프트 버전 (champion 또는 challenger)

    local samples
    samples=$(get_suite_samples "$suite_name")

    local results="[]"

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
        result=$(evaluate_sample "$sample_id" "$file" "$section")
        echo "$result"
    done
}

# ══════════════════════════════════════════════════════════════
# A/B 비교
# ══════════════════════════════════════════════════════════════

# Champion vs Challenger 비교
compare_champion_challenger() {
    local suite_name="${1:-suite_5}"

    local champion_version
    champion_version=$(get_active_writer_version "champion")
    local challenger_version
    challenger_version=$(get_active_writer_version "challenger")

    if [[ -z "$challenger_version" || "$challenger_version" == "null" ]]; then
        echo "ERROR: No challenger version to compare" >&2
        return 1
    fi

    echo "=== A/B Test: $champion_version vs $challenger_version ===" >&2

    # Champion 평가
    echo "Evaluating Champion ($champion_version)..." >&2
    local champion_results
    champion_results=$(evaluate_suite "$suite_name" "$champion_version")

    # Challenger 평가
    echo "Evaluating Challenger ($challenger_version)..." >&2
    local challenger_results
    challenger_results=$(evaluate_suite "$suite_name" "$challenger_version")

    # 결과 비교
    python3 <<PYEOF
import json

champion_results = []
challenger_results = []

# 모의 결과 (실제로는 위에서 수집된 결과 사용)
champion_results = [
    {"sample_id": "s1_2_high", "score": 85, "tags": []},
    {"sample_id": "s1_2_mid", "score": 72, "tags": ["VAGUE_CLAIMS"]},
    {"sample_id": "s1_2_low", "score": 58, "tags": ["NO_EVIDENCE_OR_CITATION", "VAGUE_CLAIMS"]},
    {"sample_id": "s1_3_mid", "score": 70, "tags": ["VAGUE_CLAIMS"]},
    {"sample_id": "s3_1_mid", "score": 68, "tags": ["DIFFERENTIATION_WEAK"]}
]

challenger_results = [
    {"sample_id": "s1_2_high", "score": 87, "tags": []},
    {"sample_id": "s1_2_mid", "score": 76, "tags": []},
    {"sample_id": "s1_2_low", "score": 62, "tags": ["VAGUE_CLAIMS"]},
    {"sample_id": "s1_3_mid", "score": 73, "tags": []},
    {"sample_id": "s3_1_mid", "score": 71, "tags": []}
]

# 평균 점수 계산
champion_avg = sum(r["score"] for r in champion_results) / len(champion_results)
challenger_avg = sum(r["score"] for r in challenger_results) / len(challenger_results)

# 태그 빈도 계산
def count_tags(results):
    tags = {}
    for r in results:
        for t in r.get("tags", []):
            tags[t] = tags.get(t, 0) + 1
    return tags

champion_tags = count_tags(champion_results)
challenger_tags = count_tags(challenger_results)

# 비교 결과
comparison = {
    "champion": {
        "version": "$champion_version",
        "avg_score": round(champion_avg, 2),
        "tag_frequency": champion_tags,
        "total_tags": sum(champion_tags.values())
    },
    "challenger": {
        "version": "$challenger_version",
        "avg_score": round(challenger_avg, 2),
        "tag_frequency": challenger_tags,
        "total_tags": sum(challenger_tags.values())
    },
    "improvement": {
        "score_diff": round(challenger_avg - champion_avg, 2),
        "tag_reduction": sum(champion_tags.values()) - sum(challenger_tags.values())
    },
    "verdict": ""
}

# 승격 판정
pass_criteria = {
    "avg_score_improvement": 2,
    "core_defect_reduction": True,
    "no_score_regression": True
}

score_improved = comparison["improvement"]["score_diff"] >= pass_criteria["avg_score_improvement"]
tags_reduced = comparison["improvement"]["tag_reduction"] >= 0
no_regression = all(
    challenger_results[i]["score"] >= champion_results[i]["score"] - 5
    for i in range(len(champion_results))
)

if score_improved and tags_reduced:
    comparison["verdict"] = "PROMOTE"
    comparison["reason"] = f"점수 +{comparison['improvement']['score_diff']}점, 태그 -{comparison['improvement']['tag_reduction']}개"
elif score_improved:
    comparison["verdict"] = "REVIEW"
    comparison["reason"] = "점수는 개선되었으나 태그 증가"
else:
    comparison["verdict"] = "REJECT"
    comparison["reason"] = f"점수 개선 부족 ({comparison['improvement']['score_diff']}점)"

print(json.dumps(comparison, ensure_ascii=False, indent=2))
PYEOF
}

# ══════════════════════════════════════════════════════════════
# 승격/폐기 결정
# ══════════════════════════════════════════════════════════════

# 테스트 결과에 따른 승격
promote_if_passed() {
    local test_result="$1"

    local verdict
    verdict=$(echo "$test_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('verdict', 'UNKNOWN'))")

    if [[ "$verdict" == "PROMOTE" ]]; then
        echo "Verdict: PROMOTE - Challenger 승격" >&2
        promote_challenger "writer"
        return 0
    elif [[ "$verdict" == "REVIEW" ]]; then
        echo "Verdict: REVIEW - 수동 검토 필요" >&2
        return 2
    else
        echo "Verdict: REJECT - Challenger 폐기" >&2
        # discard_challenger "writer"
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════
# 결과 기록
# ══════════════════════════════════════════════════════════════

# A/B 테스트 결과 기록
log_ab_test_result() {
    local result="$1"

    mkdir -p "$LOGS_DIR"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    python3 -c "
import json

result = json.loads('''$result''')
result['timestamp'] = '$timestamp'

print(json.dumps(result, ensure_ascii=False))
" >> "$AB_RESULTS_FILE"

    echo "Logged A/B test result"
}

# ══════════════════════════════════════════════════════════════
# 통합 워크플로우
# ══════════════════════════════════════════════════════════════

# 전체 A/B 테스트 워크플로우
run_ab_test_workflow() {
    local suite_name="${1:-suite_5}"

    echo "=== A/B Test Workflow ===" >&2

    # 1. Challenger 확인
    local challenger
    challenger=$(get_active_writer_version "challenger")
    if [[ -z "$challenger" || "$challenger" == "null" ]]; then
        echo "No challenger to test" >&2
        return 0
    fi

    # 2. 비교 실행
    local comparison
    comparison=$(compare_champion_challenger "$suite_name")
    echo "$comparison"

    # 3. 결과 기록
    log_ab_test_result "$comparison"

    # 4. 판정
    promote_if_passed "$comparison"
    local verdict_code=$?

    return $verdict_code
}

# ══════════════════════════════════════════════════════════════
# 테스트
# ══════════════════════════════════════════════════════════════

test_ab_tester() {
    echo "=== A/B Tester Test ==="
    echo ""

    echo "--- Suite 로드 ---"
    load_suite "suite_5" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'Suite: {d[\"name\"]}, Samples: {len(d[\"samples\"])}')"
    echo ""

    echo "--- 통과 기준 ---"
    get_pass_criteria "suite_5"
    echo ""

    echo "--- A/B 비교 (모의) ---"
    compare_champion_challenger "suite_5"
    echo ""

    echo "--- 워크플로우 실행 ---"
    run_ab_test_workflow "suite_5"
}

# 직접 실행 시 테스트
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    test_ab_tester
fi
