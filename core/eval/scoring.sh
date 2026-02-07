#!/bin/bash
# scoring.sh - 점수 파싱 및 완료 판단 (범용화)
# 기존 projects/*/lib/eval/scoring.sh를 범용화

SCORING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ══════════════════════════════════════════════════════════════
# 점수 파싱
# ══════════════════════════════════════════════════════════════

# ChatGPT 응답에서 점수 추출
parse_score() {
    local response="$1"
    local score=""

    # 패턴 1: JSON 형식 (total_score)
    score=$(echo "$response" | python3 -c "
import sys, json, re

content = sys.stdin.read()
match = re.search(r'\`\`\`json\s*([\s\S]*?)\`\`\`', content)
if match:
    try:
        data = json.loads(match.group(1))
        print(data.get('total_score', ''))
        exit(0)
    except:
        pass

# 직접 JSON 찾기
match = re.search(r'\{[\s\S]*\}', content)
if match:
    try:
        data = json.loads(match.group(0))
        print(data.get('total_score', ''))
        exit(0)
    except:
        pass
" 2>/dev/null)

    # 패턴 2: SCORE: 78/100 또는 SCORE: 78
    if [[ -z "$score" ]]; then
        score=$(echo "$response" | grep -oE 'SCORE:\s*[0-9]+' | grep -oE '[0-9]+' | head -1)
    fi

    # 패턴 3: 78/100
    if [[ -z "$score" ]]; then
        score=$(echo "$response" | grep -oE '[0-9]+/100' | grep -oE '^[0-9]+' | head -1)
    fi

    # 패턴 4: 총점: 78 또는 78점
    if [[ -z "$score" ]]; then
        score=$(echo "$response" | grep -oE '(총점|점수)[:\s]*[0-9]+' | grep -oE '[0-9]+' | head -1)
    fi

    echo "${score:-0}"
}

# 세부 점수 파싱 (JSON)
parse_breakdown() {
    local response="$1"

    python3 -c "
import sys, json, re

content = '''$response'''

match = re.search(r'\`\`\`json\s*([\s\S]*?)\`\`\`', content)
if match:
    try:
        data = json.loads(match.group(1))
        scores = data.get('scores_by_criteria', {})
        if scores:
            print(json.dumps(scores, ensure_ascii=False))
            exit(0)
    except:
        pass

print('{}')
" 2>/dev/null
}

# 피드백 텍스트 추출
parse_feedback() {
    local response="$1"

    python3 -c "
import sys, json, re

content = '''$response'''

match = re.search(r'\`\`\`json\s*([\s\S]*?)\`\`\`', content)
if match:
    try:
        data = json.loads(match.group(1))
        weaknesses = data.get('weaknesses', [])
        priority_fix = data.get('priority_fix', '')

        output = []
        if weaknesses:
            output.append('WEAKNESSES:')
            for w in weaknesses[:3]:
                if isinstance(w, dict):
                    output.append(f\"- {w.get('issue', '')}: {w.get('fix', '')}\")
                else:
                    output.append(f\"- {w}\")

        if priority_fix:
            output.append(f'PRIORITY_FIX: {priority_fix}')

        print('\n'.join(output))
        exit(0)
    except:
        pass

# Fallback
weaknesses = re.search(r'WEAKNESSES:(.*?)(?=PRIORITY_FIX:|$)', content, re.DOTALL)
priority = re.search(r'PRIORITY_FIX:(.*)', content)

output = []
if weaknesses:
    output.append('WEAKNESSES:' + weaknesses.group(1)[:200])
if priority:
    output.append('PRIORITY_FIX:' + priority.group(1)[:100])

print('\n'.join(output))
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 점수 기록
# ══════════════════════════════════════════════════════════════

# 점수 이력 파일에 기록
log_score() {
    local section_id="$1"
    local iteration="$2"
    local score="$3"
    local breakdown="${4:-}"

    # OUTPUT_DIR이 없으면 PROJECT_DIR 사용
    local scores_dir="${OUTPUT_DIR:-${PROJECT_DIR}}/scores"
    mkdir -p "$scores_dir" 2>/dev/null

    local score_file="${scores_dir}/section_${section_id}_scores.log"

    echo "$(date '+%Y-%m-%d %H:%M:%S') | iteration=$iteration | score=$score | $breakdown" >> "$score_file"
}

# 이전 점수 가져오기
get_previous_score() {
    local section_id="$1"

    local scores_dir="${OUTPUT_DIR:-${PROJECT_DIR}}/scores"
    local score_file="${scores_dir}/section_${section_id}_scores.log"

    if [[ -f "$score_file" ]]; then
        tail -2 "$score_file" | head -1 | grep -oE 'score=[0-9]+' | grep -oE '[0-9]+' || echo "0"
    else
        echo "0"
    fi
}

# ══════════════════════════════════════════════════════════════
# 완료 판단 로직
# ══════════════════════════════════════════════════════════════

# 반복 중단 여부 결정
# 반환: "CONTINUE" / "TARGET_REACHED" / "DIMINISHING_RETURNS" / "MAX_ITERATIONS" / "SCORE_REGRESSION"
should_stop_iterating() {
    local section_id="$1"
    local current_score="$2"
    local iteration="$3"
    local target_score="${4:-85}"
    local max_iterations="${5:-5}"

    # 조건 1: 목표 점수 달성
    if [[ $current_score -ge $target_score ]]; then
        echo "TARGET_REACHED"
        return 0
    fi

    # 조건 2: 최대 반복 횟수 도달
    if [[ $iteration -ge $max_iterations ]]; then
        echo "MAX_ITERATIONS"
        return 0
    fi

    # 조건 3: 수확 체감 (2회 이상 반복 후)
    if [[ $iteration -ge 2 ]]; then
        local prev_score
        prev_score=$(get_previous_score "$section_id")
        local improvement=$((current_score - prev_score))

        # 점수 하락
        if [[ $improvement -lt 0 ]]; then
            echo "SCORE_REGRESSION"
            return 0
        fi

        # 개선폭 3점 미만이고 75점 이상
        if [[ $improvement -lt 3 && $current_score -ge 75 ]]; then
            echo "DIMINISHING_RETURNS"
            return 0
        fi
    fi

    echo "CONTINUE"
    return 0
}

# ══════════════════════════════════════════════════════════════
# 종합 점수 계산
# ══════════════════════════════════════════════════════════════

# 가중 평균으로 전체 점수 계산
calculate_overall_score() {
    # SECTION_ORDER와 section_get_weight 함수 필요

    if ! type section_get_weight &>/dev/null; then
        echo "0"
        return
    fi

    local total_weighted=0
    local total_weight=0

    for section_id in "${SECTION_ORDER[@]}"; do
        local score
        # state_get 또는 다른 방법으로 점수 가져오기
        if type state_get &>/dev/null; then
            score=$(state_get ".sections.\"$section_id\".score" 2>/dev/null)
        else
            score=0
        fi
        score=${score:-0}

        local weight
        weight=$(section_get_weight "$section_id" 2>/dev/null || echo "5")

        total_weighted=$((total_weighted + score * weight))
        total_weight=$((total_weight + weight))
    done

    if [[ $total_weight -gt 0 ]]; then
        echo $((total_weighted / total_weight))
    else
        echo 0
    fi
}

# 섹션별 점수 요약 출력
print_section_scores() {
    if [[ -z "${SECTION_ORDER[*]}" ]]; then
        echo "No sections defined"
        return
    fi

    echo ""
    printf "  %-45s %s %s\n" "Section" "Score" "Iterations"
    echo "  $(printf '=%.0s' {1..60})"

    for section_id in "${SECTION_ORDER[@]}"; do
        local name score iter

        if type section_get_name &>/dev/null; then
            name=$(section_get_name "$section_id")
        else
            name="$section_id"
        fi

        if type state_get &>/dev/null; then
            score=$(state_get ".sections.\"$section_id\".score" 2>/dev/null)
            iter=$(state_get ".sections.\"$section_id\".iteration" 2>/dev/null)
        else
            score=0
            iter=0
        fi

        printf "  %-43s %3d pts  %d\n" "$name" "${score:-0}" "${iter:-0}"
    done

    echo "  $(printf '=%.0s' {1..60})"
}

# 직접 실행 시
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Scoring Module (Core)"
    echo ""
    echo "함수:"
    echo "  parse_score <response>                      점수 추출"
    echo "  parse_breakdown <response>                  세부 점수"
    echo "  parse_feedback <response>                   피드백"
    echo "  log_score <section> <iter> <score> [break]  점수 기록"
    echo "  get_previous_score <section>                이전 점수"
    echo "  should_stop_iterating <section> <score> <iter> [target] [max]"
    echo "  calculate_overall_score                     전체 점수"
    echo "  print_section_scores                        점수 요약"
fi
