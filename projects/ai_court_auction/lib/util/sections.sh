#!/bin/bash
# sections.sh - 섹션 정의 및 관련 유틸리티

# ══════════════════════════════════════════════════════════════
# 섹션 순서 (처리 순서대로)
# ══════════════════════════════════════════════════════════════

SECTION_ORDER=(
    "overview"
    "product_summary"
    "closure_details"
    "s1_1"
    "s1_2"
    "s1_3"
    "s2_1"
    "s2_2"
    "s3_1"
    "s3_2"
    "s3_3"
    "s4_1"
    "s4_2"
)

# ══════════════════════════════════════════════════════════════
# 섹션 이름 가져오기 (한국어)
# ══════════════════════════════════════════════════════════════

get_section_name() {
    local section_id="$1"
    case "$section_id" in
        "overview") echo "신청·일반현황" ;;
        "product_summary") echo "제품·서비스 개요(요약)" ;;
        "closure_details") echo "폐업기업 세부내용" ;;
        "s1_1") echo "1-1. 폐업 원인 분석 및 개선방안" ;;
        "s1_2") echo "1-2. 창업아이템 배경 및 필요성" ;;
        "s1_3") echo "1-3. 목표시장(고객) 현황 분석" ;;
        "s2_1") echo "2-1. 창업아이템 현황 (준비 정도)" ;;
        "s2_2") echo "2-2. 실현 및 구체화 방안" ;;
        "s3_1") echo "3-1. 비즈니스 모델 및 사업화 추진성과" ;;
        "s3_2") echo "3-2. 사업화 추진 전략" ;;
        "s3_3") echo "3-3. 사업추진 일정 및 자금운용 계획" ;;
        "s4_1") echo "4-1. 기업구성 및 보유 역량" ;;
        "s4_2") echo "4-2. ESG 경영 도입 현황" ;;
        *) echo "$section_id" ;;
    esac
}

# ══════════════════════════════════════════════════════════════
# 섹션별 페이지 분량 (A4 기준)
# ══════════════════════════════════════════════════════════════

get_section_pages() {
    local section_id="$1"
    case "$section_id" in
        "overview") echo "1" ;;
        "product_summary") echo "1" ;;
        "closure_details") echo "1" ;;
        "s1_1") echo "1.5" ;;
        "s1_2") echo "1.5" ;;
        "s1_3") echo "1.5" ;;
        "s2_1") echo "1" ;;
        "s2_2") echo "1.5" ;;
        "s3_1") echo "1" ;;
        "s3_2") echo "1" ;;
        "s3_3") echo "1.5" ;;
        "s4_1") echo "1" ;;
        "s4_2") echo "0.5" ;;
        *) echo "1" ;;
    esac
}

# ══════════════════════════════════════════════════════════════
# 섹션별 가중치 (종합 점수 계산용)
# ══════════════════════════════════════════════════════════════

get_section_weight() {
    local section_id="$1"
    case "$section_id" in
        "overview") echo "5" ;;
        "product_summary") echo "5" ;;
        "closure_details") echo "8" ;;
        "s1_1") echo "12" ;;
        "s1_2") echo "10" ;;
        "s1_3") echo "12" ;;
        "s2_1") echo "8" ;;
        "s2_2") echo "10" ;;
        "s3_1") echo "8" ;;
        "s3_2") echo "8" ;;
        "s3_3") echo "6" ;;
        "s4_1") echo "5" ;;
        "s4_2") echo "3" ;;
        *) echo "5" ;;
    esac
}

# ══════════════════════════════════════════════════════════════
# 유틸리티 함수
# ══════════════════════════════════════════════════════════════

# 섹션 인덱스 가져오기 (1부터 시작)
get_section_index() {
    local section_id="$1"
    local idx=1
    for sid in "${SECTION_ORDER[@]}"; do
        if [[ "$sid" == "$section_id" ]]; then
            echo "$idx"
            return
        fi
        ((idx++))
    done
    echo "0"
}

# 전체 섹션 수
get_total_sections() {
    echo "${#SECTION_ORDER[@]}"
}

# 리서치 타입 매핑
get_research_type() {
    local section_id="$1"
    case "$section_id" in
        "s1_3") echo "market_size" ;;
        "s3_1") echo "competitive" ;;
        "s3_2") echo "customer_needs" ;;
        *) echo "" ;;
    esac
}
