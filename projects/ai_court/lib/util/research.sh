#!/bin/bash
# research.sh - 리서치 블록 로딩 공통 모듈
# 사용법: source lib/util/research.sh

# ══════════════════════════════════════════════════════════════
# 설정
# ══════════════════════════════════════════════════════════════

# 기본 경로 (PROJECT_DIR이 설정되어 있어야 함)
_get_research_dir() {
    echo "${PROJECT_DIR:-$(pwd)}/research"
}

_get_research_responses_dir() {
    echo "$(_get_research_dir)/responses"
}

# ══════════════════════════════════════════════════════════════
# 리서치 파일 확인
# ══════════════════════════════════════════════════════════════

# 리서치 응답 파일 경로 반환
# 사용법: file=$(get_research_file "market_size")
get_research_file() {
    local research_type="$1"
    echo "$(_get_research_responses_dir)/${research_type}.md"
}

# 리서치 결과가 존재하는지 확인 (md 또는 pdf)
# 사용법: if has_research_result "market_size"; then ... fi
has_research_result() {
    local research_type="$1"
    local responses_dir
    responses_dir=$(_get_research_responses_dir)

    local md_file="${responses_dir}/${research_type}.md"
    local pdf_file="${responses_dir}/${research_type}.pdf"

    # PDF 파일 확인
    if [[ -f "$pdf_file" ]]; then
        return 0
    fi

    # MD 파일 확인 (100자 이상)
    if [[ -f "$md_file" ]]; then
        local size
        size=$(wc -c < "$md_file" | tr -d ' ')
        [[ "$size" -gt 100 ]]
    else
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════
# 리서치 블록 로딩
# ══════════════════════════════════════════════════════════════

# 리서치 결과 로드 (raw content)
# 사용법: content=$(load_research_result "market_size")
load_research_result() {
    local research_type="$1"
    local responses_dir
    responses_dir=$(_get_research_responses_dir)

    local md_file="${responses_dir}/${research_type}.md"
    local pdf_file="${responses_dir}/${research_type}.pdf"

    # MD 파일 우선
    if [[ -f "$md_file" ]]; then
        cat "$md_file"
    elif [[ -f "$pdf_file" ]]; then
        echo "[PDF 파일: ${pdf_file}]"
    fi
}

# 섹션 ID 기반 리서치 블록 로드 (s1_2_*.md 패턴)
# 사용법: block=$(load_research_block "s1_2")
load_research_block() {
    local section_id="$1"
    local responses_dir
    responses_dir=$(_get_research_responses_dir)

    local research_block=""

    for file in "${responses_dir}/${section_id}_"*.md; do
        [[ -f "$file" ]] || continue
        local filename
        filename=$(basename "$file")
        research_block+="
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[리서치 자료: ${filename}]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$(cat "$file")

"
    done

    if [[ -n "$research_block" ]]; then
        echo "[제공 근거 자료]
${research_block}"
    fi
}

# 리서치 블록 포맷팅 (심층 리서치 결과용)
# 사용법: block=$(format_research_block "market_size")
format_research_block() {
    local research_type="$1"
    local research_content
    research_content=$(load_research_result "$research_type")

    if [[ -n "$research_content" ]]; then
        echo "
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[심층 리서치 결과] ★ 본문에 반영 필수 ★
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$research_content
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
}

# ══════════════════════════════════════════════════════════════
# 리서치 블록 존재 여부 확인
# ══════════════════════════════════════════════════════════════

# 섹션에 대한 리서치 파일이 있는지 확인
# 사용법: if has_section_research "s1_2"; then ... fi
has_section_research() {
    local section_id="$1"
    local responses_dir
    responses_dir=$(_get_research_responses_dir)

    local found=false
    for file in "${responses_dir}/${section_id}_"*.md; do
        if [[ -f "$file" ]]; then
            found=true
            break
        fi
    done

    $found
}

# 리서치 파일 목록 반환
# 사용법: files=$(list_research_files "s1_2")
list_research_files() {
    local section_id="$1"
    local responses_dir
    responses_dir=$(_get_research_responses_dir)

    for file in "${responses_dir}/${section_id}_"*.md; do
        [[ -f "$file" ]] && basename "$file"
    done
}

# 리서치 블록 크기 반환 (글자 수)
# 사용법: size=$(get_research_block_size "s1_2")
get_research_block_size() {
    local section_id="$1"
    local block
    block=$(load_research_block "$section_id")
    echo "${#block}"
}
