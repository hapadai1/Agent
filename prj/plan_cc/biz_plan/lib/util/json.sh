#!/bin/bash
# json.sh - JSON 파일 처리 유틸리티
# 사용법: source json.sh

# ══════════════════════════════════════════════════════════════
# JSON 파일 값 추출
# ══════════════════════════════════════════════════════════════

# JSON 파일에서 값 추출
# 사용법: json_get_from_file "/path/to/file.json" "key" [default]
# 예시: score=$(json_get_from_file "$file" "total_score" "0")
json_get_from_file() {
    local file="$1"
    local key="$2"
    local default="${3:-?}"
    python3 -c "import json; d=json.load(open('$file')); print(d.get('$key', '$default'))" 2>/dev/null || echo "$default"
}

# Stage 2 점수 추출 (normalized_score 우선, 없으면 total_score)
# 사용법: get_stage2_score "/path/to/file.json"
# 예시: score=$(get_stage2_score "$eval_file")
get_stage2_score() {
    local file="$1"
    python3 -c "import json; d=json.load(open('$file')); print(d.get('normalized_score', d.get('total_score', 0)))" 2>/dev/null || echo "?"
}

# ══════════════════════════════════════════════════════════════
# 파일 검색 유틸리티
# ══════════════════════════════════════════════════════════════

# 대상 파일 찾기 (섹션/버전 필터링)
# 사용법: files=$(find_target_files "$dir" "$section" "$version")
# 예시: files=$(find_target_files "$RUNS_DIR" "s1_2" "6")
find_target_files() {
    local dir="$1"
    local section="$2"
    local version="$3"

    local pattern="*.out.md"
    if [[ -n "$section" && -n "$version" ]]; then
        pattern="${section}_v${version}.out.md"
    elif [[ -n "$section" ]]; then
        pattern="${section}_v*.out.md"
    elif [[ -n "$version" ]]; then
        pattern="*_v${version}.out.md"
    fi

    find "$dir" -name "$pattern" | sort
}
