#!/bin/bash
# code_verify/workflow.sh - 소스 코드 검증 워크플로우
# Claude Code가 개발한 코드를 ChatGPT가 검증

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ══════════════════════════════════════════════════════════════
# 코드 검증 함수들
# ══════════════════════════════════════════════════════════════

# 파일 코드 리뷰 요청
request_code_review() {
    local file_path="$1"

    if [[ ! -f "$file_path" ]]; then
        echo "오류: 파일을 찾을 수 없습니다 - $file_path"
        return 1
    fi

    local file_content
    file_content=$(cat "$file_path")
    local file_name
    file_name=$(basename "$file_path")

    local prompt="다음 코드를 검토해주세요. 버그, 보안 취약점, 성능 문제, 코드 품질 이슈를 찾아주세요.

파일: $file_name

\`\`\`
$file_content
\`\`\`

다음 형식으로 응답해주세요:
ISSUES_FOUND: [숫자]
SEVERITY: [critical/major/minor/none]
DETAILS:
- [이슈 설명]
SUGGESTIONS:
- [개선 제안]"

    local win tab timeout
    win=$(state_get ".chatgpt.window")
    tab=$(state_get ".chatgpt.tab")
    timeout=$(state_get ".chatgpt.default_timeout")

    echo "코드 리뷰 요청: $file_name"

    local response
    response=$(chatgpt_ask "$prompt" "$win" "$tab" "$timeout")

    # 결과 저장
    local review_path="${PROJECT_DIR}/reviews/$(basename "$file_path").review.md"
    mkdir -p "${PROJECT_DIR}/reviews"
    echo "$response" > "$review_path"

    # 이슈 수 파싱
    local issues
    issues=$(echo "$response" | grep -oE 'ISSUES_FOUND:\s*[0-9]+' | grep -oE '[0-9]+' | head -1)
    issues=${issues:-0}

    echo "발견된 이슈: $issues"
    echo "리뷰 저장됨: $review_path"

    # 상태 업데이트
    local total
    total=$(state_get ".total_files_verified")
    ((total++))
    state_set ".total_files_verified" "$total"

    local found
    found=$(state_get ".issues_found")
    found=$((found + issues))
    state_set ".issues_found" "$found"

    echo "$issues"
}

# 테스트 실행 및 결과 검증
run_and_verify_tests() {
    local source_dir
    source_dir=$(state_get ".source_dir")
    local test_cmd
    test_cmd=$(state_get ".test_command")

    echo ""
    echo "######테스트 실행######"
    echo "명령어: $test_cmd"
    echo "디렉토리: $source_dir"

    # 테스트 실행
    local test_output
    test_output=$(cd "$source_dir" && eval "$test_cmd" 2>&1)
    local exit_code=$?

    # 결과 저장
    local test_log="${PROJECT_DIR}/test_results.log"
    echo "실행 시간: $(date)" > "$test_log"
    echo "명령어: $test_cmd" >> "$test_log"
    echo "종료 코드: $exit_code" >> "$test_log"
    echo "" >> "$test_log"
    echo "$test_output" >> "$test_log"

    if [[ $exit_code -eq 0 ]]; then
        echo "테스트 성공"
        return 0
    else
        echo "테스트 실패 (코드: $exit_code)"

        # ChatGPT에 실패 분석 요청
        local prompt="다음 테스트 실패 로그를 분석해주세요. 원인과 해결 방법을 제시해주세요.

\`\`\`
$test_output
\`\`\`

다음 형식으로 응답:
FAILURE_TYPE: [syntax/logic/dependency/environment/other]
ROOT_CAUSE: [원인 설명]
FIX_SUGGESTION: [수정 방법]"

        local win tab timeout
        win=$(state_get ".chatgpt.window")
        tab=$(state_get ".chatgpt.tab")
        timeout=$(state_get ".chatgpt.default_timeout")

        local analysis
        analysis=$(chatgpt_ask "$prompt" "$win" "$tab" "$timeout")

        echo "$analysis" >> "$test_log"
        echo ""
        echo "분석 결과:"
        echo "$analysis"

        return 1
    fi
}

# 빌드 검증
verify_build() {
    local source_dir
    source_dir=$(state_get ".source_dir")
    local build_cmd
    build_cmd=$(state_get ".build_command")

    echo ""
    echo "######빌드 검증######"
    echo "명령어: $build_cmd"

    local build_output
    build_output=$(cd "$source_dir" && eval "$build_cmd" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo "빌드 성공"
        return 0
    else
        echo "빌드 실패"
        echo "$build_output"
        return 1
    fi
}

# 디렉토리 내 모든 소스 파일 검증
verify_directory() {
    local dir="$1"
    local pattern="${2:-*.js}"

    echo ""
    echo "######디렉토리 검증######"
    echo "경로: $dir"
    echo "패턴: $pattern"

    local files
    files=$(find "$dir" -name "$pattern" -type f 2>/dev/null)

    local file_count
    file_count=$(echo "$files" | wc -l | tr -d ' ')
    echo "파일 수: $file_count"

    local idx=1
    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            echo ""
            echo "[$idx/$file_count] 검증 중: $file"
            request_code_review "$file"
            ((idx++))
        fi
    done <<< "$files"
}

# 워크플로우 실행
run_workflow() {
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║       코드 검증 워크플로우 시작              ║"
    echo "╚══════════════════════════════════════════════╝"

    local source_dir
    source_dir=$(state_get ".source_dir")

    if [[ -z "$source_dir" || ! -d "$source_dir" ]]; then
        echo "오류: source_dir이 설정되지 않았거나 존재하지 않습니다"
        return 1
    fi

    # 1. 빌드 검증
    verify_build || echo "빌드 실패 - 계속 진행"

    # 2. 테스트 실행
    run_and_verify_tests

    # 3. 결과 요약
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║            검증 완료                         ║"
    echo "╚══════════════════════════════════════════════╝"

    local verified
    verified=$(state_get ".total_files_verified")
    local issues
    issues=$(state_get ".issues_found")

    echo "검증된 파일: $verified"
    echo "발견된 이슈: $issues"
}
