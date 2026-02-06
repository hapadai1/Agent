#!/bin/bash
# scoring.sh - 점수 파싱 및 완료 판단 로직

# ══════════════════════════════════════════════════════════════
# 점수 파싱
# ══════════════════════════════════════════════════════════════

# ChatGPT 응답에서 점수 추출
# 예상 형식: "SCORE: 78/100" 또는 "총점: 78점"
parse_score() {
    local response="$1"
    local score=""

    # 패턴 1: SCORE: 78/100 또는 SCORE: 78
    score=$(echo "$response" | grep -oE 'SCORE:\s*[0-9]+' | grep -oE '[0-9]+' | head -1)

    # 패턴 2: 78/100
    if [[ -z "$score" ]]; then
        score=$(echo "$response" | grep -oE '[0-9]+/100' | grep -oE '^[0-9]+' | head -1)
    fi

    # 패턴 3: 총점: 78 또는 78점
    if [[ -z "$score" ]]; then
        score=$(echo "$response" | grep -oE '(총점|점수)[:\s]*[0-9]+' | grep -oE '[0-9]+' | head -1)
    fi

    # 패턴 4: 단독 숫자점 (78점)
    if [[ -z "$score" ]]; then
        score=$(echo "$response" | grep -oE '[0-9]+점' | grep -oE '[0-9]+' | head -1)
    fi

    # 기본값 0
    echo "${score:-0}"
}

# 세부 점수 파싱 (BREAKDOWN: 완성도=25, 구체성=20, ...)
parse_breakdown() {
    local response="$1"
    echo "$response" | grep -oE 'BREAKDOWN:.*' | head -1
}

# 피드백 텍스트 추출
parse_feedback() {
    local response="$1"

    # WEAKNESSES와 PRIORITY_FIX 부분 추출
    local weaknesses
    local priority

    weaknesses=$(echo "$response" | sed -n '/WEAKNESSES:/,/PRIORITY_FIX:/p' | head -20)
    priority=$(echo "$response" | grep -A2 'PRIORITY_FIX:' | head -3)

    echo "$weaknesses"
    echo "$priority"
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

    local score_file="${OUTPUT_DIR}/scores/section_${section_id}_scores.log"

    echo "$(date '+%Y-%m-%d %H:%M:%S') | iteration=$iteration | score=$score | $breakdown" >> "$score_file"
}

# 이전 점수 가져오기 (개선폭 계산용)
get_previous_score() {
    local section_id="$1"
    local score_file="${OUTPUT_DIR}/scores/section_${section_id}_scores.log"

    if [[ -f "$score_file" ]]; then
        # 마지막에서 두 번째 줄의 점수
        tail -2 "$score_file" | head -1 | grep -oE 'score=[0-9]+' | grep -oE '[0-9]+' || echo "0"
    else
        echo "0"
    fi
}

# ══════════════════════════════════════════════════════════════
# 완료 판단 로직
# ══════════════════════════════════════════════════════════════

# 섹션 반복 중단 여부 결정
# 반환: "CONTINUE" / "TARGET_REACHED" / "DIMINISHING_RETURNS" / "MAX_ITERATIONS" / "SCORE_REGRESSION"
should_stop_iterating() {
    local section_id="$1"
    local current_score="$2"
    local iteration="$3"
    local target_score="$4"
    local max_iterations="$5"

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

        # 점수가 하락한 경우 - 이전 버전 유지
        if [[ $improvement -lt 0 ]]; then
            echo "SCORE_REGRESSION"
            return 0
        fi

        # 개선폭이 3점 미만이고 이미 75점 이상인 경우
        if [[ $improvement -lt 3 && $current_score -ge 75 ]]; then
            echo "DIMINISHING_RETURNS"
            return 0
        fi
    fi

    # 계속 반복
    echo "CONTINUE"
    return 0
}

# ══════════════════════════════════════════════════════════════
# 종합 점수 계산
# ══════════════════════════════════════════════════════════════

# 가중 평균으로 전체 점수 계산
calculate_overall_score() {
    local total_weighted=0
    local total_weight=0

    for section_id in "${SECTION_ORDER[@]}"; do
        local score
        score=$(state_get ".sections.\"$section_id\".score")
        score=${score:-0}

        local weight
        weight=$(get_section_weight "$section_id")

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
    echo ""
    printf "  %-45s %s %s\n" "섹션" "점수" "반복"
    print_divider

    for section_id in "${SECTION_ORDER[@]}"; do
        local name
        name=$(get_section_name "$section_id")
        local score
        score=$(state_get ".sections.\"$section_id\".score")
        local iter
        iter=$(state_get ".sections.\"$section_id\".iteration")

        printf "  %-43s %3d점  %d회\n" "$name" "${score:-0}" "${iter:-0}"
    done

    print_divider
}
