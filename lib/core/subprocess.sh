#!/bin/bash
# subprocess.sh - 서브프로세스 실행 및 에러 로깅
# 사용법: source lib/core/subprocess.sh
#
# Python 등 서브프로세스 실행 시 에러를 조용히 무시하지 않고
# 선택적으로 로깅할 수 있는 유틸리티 제공

# ══════════════════════════════════════════════════════════════
# 설정
# ══════════════════════════════════════════════════════════════

# 에러 로그 활성화 (환경변수로 제어)
SUBPROCESS_LOG_ERRORS="${SUBPROCESS_LOG_ERRORS:-false}"
SUBPROCESS_LOG_FILE="${SUBPROCESS_LOG_FILE:-/tmp/subprocess_errors.log}"

# ══════════════════════════════════════════════════════════════
# Python 실행 래퍼
# ══════════════════════════════════════════════════════════════

# Python 코드 실행 (에러 로깅 포함)
# 사용법: result=$(py_exec "print('hello')")
py_exec() {
    local code="$1"
    local stderr_file
    stderr_file=$(mktemp)

    local result
    result=$(python3 -c "$code" 2>"$stderr_file")
    local exit_code=$?

    # 에러가 있으면 로깅
    if [[ $exit_code -ne 0 && -s "$stderr_file" ]]; then
        if [[ "$SUBPROCESS_LOG_ERRORS" == "true" ]]; then
            {
                echo "===== $(date '+%Y-%m-%d %H:%M:%S') ====="
                echo "Exit code: $exit_code"
                echo "Code: ${code:0:200}..."
                echo "Error:"
                cat "$stderr_file"
                echo ""
            } >> "$SUBPROCESS_LOG_FILE"
        fi
    fi

    rm -f "$stderr_file"
    echo "$result"
    return $exit_code
}

# Python 코드 실행 (stdin 입력 포함)
# 사용법: result=$(echo "$input" | py_exec_stdin "import sys; print(sys.stdin.read())")
py_exec_stdin() {
    local code="$1"
    local stderr_file
    stderr_file=$(mktemp)

    local result
    result=$(python3 -c "$code" 2>"$stderr_file")
    local exit_code=$?

    if [[ $exit_code -ne 0 && -s "$stderr_file" ]]; then
        if [[ "$SUBPROCESS_LOG_ERRORS" == "true" ]]; then
            {
                echo "===== $(date '+%Y-%m-%d %H:%M:%S') ====="
                echo "Exit code: $exit_code"
                echo "Code: ${code:0:200}..."
                echo "Error:"
                cat "$stderr_file"
                echo ""
            } >> "$SUBPROCESS_LOG_FILE"
        fi
    fi

    rm -f "$stderr_file"
    echo "$result"
    return $exit_code
}

# ══════════════════════════════════════════════════════════════
# 안전한 명령 실행
# ══════════════════════════════════════════════════════════════

# 명령 실행 (에러 캡처)
# 사용법: result=$(safe_exec "ls -la")
#        if [[ $? -ne 0 ]]; then echo "failed"; fi
safe_exec() {
    local cmd="$1"
    local stderr_file
    stderr_file=$(mktemp)

    local result
    result=$(eval "$cmd" 2>"$stderr_file")
    local exit_code=$?

    if [[ $exit_code -ne 0 && -s "$stderr_file" ]]; then
        if [[ "$SUBPROCESS_LOG_ERRORS" == "true" ]]; then
            {
                echo "===== $(date '+%Y-%m-%d %H:%M:%S') ====="
                echo "Command: $cmd"
                echo "Exit code: $exit_code"
                echo "Error:"
                cat "$stderr_file"
                echo ""
            } >> "$SUBPROCESS_LOG_FILE"
        fi
    fi

    rm -f "$stderr_file"
    echo "$result"
    return $exit_code
}

# ══════════════════════════════════════════════════════════════
# 에러 로그 관리
# ══════════════════════════════════════════════════════════════

# 에러 로그 활성화
enable_subprocess_logging() {
    export SUBPROCESS_LOG_ERRORS=true
}

# 에러 로그 비활성화
disable_subprocess_logging() {
    export SUBPROCESS_LOG_ERRORS=false
}

# 에러 로그 파일 설정
set_subprocess_log_file() {
    export SUBPROCESS_LOG_FILE="$1"
}

# 에러 로그 확인
show_subprocess_errors() {
    if [[ -f "$SUBPROCESS_LOG_FILE" ]]; then
        cat "$SUBPROCESS_LOG_FILE"
    else
        echo "에러 로그 파일이 없습니다: $SUBPROCESS_LOG_FILE"
    fi
}

# 에러 로그 삭제
clear_subprocess_errors() {
    rm -f "$SUBPROCESS_LOG_FILE"
}

# 최근 에러 확인 (마지막 N개)
tail_subprocess_errors() {
    local n="${1:-10}"
    if [[ -f "$SUBPROCESS_LOG_FILE" ]]; then
        tail -n "$n" "$SUBPROCESS_LOG_FILE"
    fi
}
