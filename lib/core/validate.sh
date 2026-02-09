#!/bin/bash
# validate.sh - 입력 검증 공통 모듈
# 사용법: source lib/core/validate.sh

# ══════════════════════════════════════════════════════════════
# 파일/디렉토리 검증
# ══════════════════════════════════════════════════════════════

# 파일 존재 확인 (에러 메시지 포함)
# 사용법: assert_file_exists "$file" "설정 파일" || return 1
assert_file_exists() {
    local file="$1"
    local description="${2:-파일}"

    if [[ ! -f "$file" ]]; then
        echo "ERROR: ${description}을(를) 찾을 수 없습니다: $file" >&2
        return 1
    fi
    return 0
}

# 디렉토리 존재 확인 (에러 메시지 포함)
# 사용법: assert_dir_exists "$dir" "출력 디렉토리" || return 1
assert_dir_exists() {
    local dir="$1"
    local description="${2:-디렉토리}"

    if [[ ! -d "$dir" ]]; then
        echo "ERROR: ${description}을(를) 찾을 수 없습니다: $dir" >&2
        return 1
    fi
    return 0
}

# 파일이 읽기 가능한지 확인
# 사용법: assert_file_readable "$file" || return 1
assert_file_readable() {
    local file="$1"
    local description="${2:-파일}"

    if [[ ! -r "$file" ]]; then
        echo "ERROR: ${description}을(를) 읽을 수 없습니다: $file" >&2
        return 1
    fi
    return 0
}

# 디렉토리가 쓰기 가능한지 확인
# 사용법: assert_dir_writable "$dir" || return 1
assert_dir_writable() {
    local dir="$1"
    local description="${2:-디렉토리}"

    if [[ ! -w "$dir" ]]; then
        echo "ERROR: ${description}에 쓸 수 없습니다: $dir" >&2
        return 1
    fi
    return 0
}

# 파일/디렉토리 생성 보장 (없으면 생성)
# 사용법: ensure_dir "$dir"
ensure_dir() {
    local dir="$1"
    mkdir -p "$dir" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 값 검증
# ══════════════════════════════════════════════════════════════

# 값이 비어있지 않은지 확인
# 사용법: assert_not_empty "$value" "섹션 이름" || return 1
assert_not_empty() {
    local value="$1"
    local name="${2:-값}"

    if [[ -z "$value" ]]; then
        echo "ERROR: ${name}이(가) 비어있습니다" >&2
        return 1
    fi
    return 0
}

# 값이 숫자인지 확인
# 사용법: assert_is_number "$value" "점수" || return 1
assert_is_number() {
    local value="$1"
    local name="${2:-값}"

    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "ERROR: ${name}은(는) 숫자여야 합니다: $value" >&2
        return 1
    fi
    return 0
}

# 값이 범위 내인지 확인
# 사용법: assert_in_range "$score" 0 100 "점수" || return 1
assert_in_range() {
    local value="$1"
    local min="$2"
    local max="$3"
    local name="${4:-값}"

    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "ERROR: ${name}은(는) 숫자여야 합니다: $value" >&2
        return 1
    fi

    if [[ "$value" -lt "$min" || "$value" -gt "$max" ]]; then
        echo "ERROR: ${name}은(는) ${min}~${max} 범위여야 합니다: $value" >&2
        return 1
    fi
    return 0
}

# 값이 허용된 목록에 있는지 확인
# 사용법: assert_in_list "$step" "writer evaluator prompt" "스텝" || return 1
assert_in_list() {
    local value="$1"
    local allowed="$2"  # 공백으로 구분된 목록
    local name="${3:-값}"

    local item
    for item in $allowed; do
        if [[ "$value" == "$item" ]]; then
            return 0
        fi
    done

    echo "ERROR: ${name}은(는) [$allowed] 중 하나여야 합니다: $value" >&2
    return 1
}

# ══════════════════════════════════════════════════════════════
# 응답 검증
# ══════════════════════════════════════════════════════════════

# 응답 길이 검증
# 사용법: assert_min_length "$response" 500 "Writer 응답" || return 1
assert_min_length() {
    local value="$1"
    local min_length="$2"
    local name="${3:-응답}"

    local actual_length=${#value}
    if [[ $actual_length -lt $min_length ]]; then
        echo "ERROR: ${name}이(가) 너무 짧습니다 (${actual_length}자 < ${min_length}자)" >&2
        return 1
    fi
    return 0
}

# 응답에 특정 패턴이 포함되어 있는지 확인
# 사용법: assert_contains "$response" "{" "JSON 응답" || return 1
assert_contains() {
    local value="$1"
    local pattern="$2"
    local name="${3:-응답}"

    if [[ "$value" != *"$pattern"* ]]; then
        echo "ERROR: ${name}에 필수 패턴이 없습니다: $pattern" >&2
        return 1
    fi
    return 0
}

# ══════════════════════════════════════════════════════════════
# 복합 검증
# ══════════════════════════════════════════════════════════════

# Writer 응답 검증 (500자 이상, 비어있지 않음)
# 사용법: validate_writer_response "$response" || return 1
validate_writer_response() {
    local response="$1"
    local min_length="${2:-500}"

    assert_not_empty "$response" "Writer 응답" || return 1
    assert_min_length "$response" "$min_length" "Writer 응답" || return 1
    return 0
}

# Evaluator 응답 검증 (JSON 포함, 50자 이상)
# 사용법: validate_evaluator_response "$response" || return 1
validate_evaluator_response() {
    local response="$1"
    local min_length="${2:-50}"

    assert_not_empty "$response" "Evaluator 응답" || return 1
    assert_min_length "$response" "$min_length" "Evaluator 응답" || return 1
    assert_contains "$response" "{" "Evaluator 응답" || return 1
    assert_contains "$response" "}" "Evaluator 응답" || return 1
    return 0
}

# ══════════════════════════════════════════════════════════════
# 조용한 검증 (에러 메시지 없이 true/false만)
# ══════════════════════════════════════════════════════════════

# 파일 존재 여부 (조용히)
# 사용법: if file_exists "$file"; then ...
file_exists() {
    [[ -f "$1" ]]
}

# 디렉토리 존재 여부 (조용히)
# 사용법: if dir_exists "$dir"; then ...
dir_exists() {
    [[ -d "$1" ]]
}

# 값이 비어있는지 (조용히)
# 사용법: if is_empty "$value"; then ...
is_empty() {
    [[ -z "$1" ]]
}

# 값이 숫자인지 (조용히)
# 사용법: if is_number "$value"; then ...
is_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}
