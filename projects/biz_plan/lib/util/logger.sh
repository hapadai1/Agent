#!/bin/bash
# logger.sh - 공통 로그 모듈
# 사용법: source logger.sh

# ══════════════════════════════════════════════════════════════
# 전역 변수
# ══════════════════════════════════════════════════════════════
LOG_FILE=""
LOG_CHAPTER=""
LOG_VERSION=""
LOG_LEVEL="${LOG_LEVEL:-INFO}"  # DEBUG, INFO, WARN, ERROR

# 로그 레벨 숫자 (bash 3.2 호환)
_log_level_num() {
    case "$1" in
        DEBUG) echo 0 ;;
        INFO)  echo 1 ;;
        WARN)  echo 2 ;;
        ERROR) echo 3 ;;
        *)     echo 1 ;;
    esac
}

# ══════════════════════════════════════════════════════════════
# 초기화 함수
# ══════════════════════════════════════════════════════════════

# 로그 파일 초기화
# 사용법: log_init "/path/to/runs/2026-02-06/challenger"
log_init() {
    local run_dir="$1"
    local timestamp=$(date +%H%M%S)

    mkdir -p "$run_dir"
    LOG_FILE="${run_dir}/test_${timestamp}.log"

    # 로그 파일 헤더
    {
        echo "════════════════════════════════════════════════════════════"
        echo "  테스트 실행 로그"
        echo "  시작: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  경로: $run_dir"
        echo "════════════════════════════════════════════════════════════"
        echo ""
    } > "$LOG_FILE"

    echo "📝 로그 파일: $LOG_FILE" >&2
}

# 챕터/버전 컨텍스트 설정
# 사용법: log_set_context "s1_2" "v1"
log_set_context() {
    LOG_CHAPTER="${1:-}"
    LOG_VERSION="${2:-}"
}

# ══════════════════════════════════════════════════════════════
# 로그 출력 함수
# ══════════════════════════════════════════════════════════════

# 기본 로그 함수 (내부용)
_log() {
    local level="$1"
    local msg="$2"
    local ts=$(date '+%H:%M:%S')

    # 레벨 체크
    local current_level=$(_log_level_num "$LOG_LEVEL")
    local msg_level=$(_log_level_num "$level")
    if [[ $msg_level -lt $current_level ]]; then
        return 0
    fi

    # 컨텍스트 포맷
    local context=""
    if [[ -n "$LOG_CHAPTER" ]]; then
        context="[$LOG_CHAPTER]"
    fi
    if [[ -n "$LOG_VERSION" ]]; then
        context="$context [$LOG_VERSION]"
    fi

    # 로그 라인 생성
    local line="[$ts]$context $msg"

    # 터미널 출력
    echo "$line" >&2

    # 파일 출력 (LOG_FILE이 설정된 경우)
    if [[ -n "$LOG_FILE" && -f "$LOG_FILE" ]]; then
        echo "$line" >> "$LOG_FILE"
    fi
}

# 레벨별 로그 함수
log_debug() {
    _log "DEBUG" "$1"
}

log_info() {
    _log "INFO" "$1"
}

log_warn() {
    _log "WARN" "⚠️ $1"
}

log_error() {
    _log "ERROR" "❌ $1"
}

log_ok() {
    _log "INFO" "✅ $1"
}

# ══════════════════════════════════════════════════════════════
# 상세 로그 함수 (프롬프트/응답/평가용)
# ══════════════════════════════════════════════════════════════

# 프롬프트 로그 (요약 + 파일 저장)
# 사용법: log_prompt "writer" "프롬프트 내용" "/path/to/save"
log_prompt() {
    local type="$1"      # writer, evaluator, tab5
    local content="$2"
    local save_path="$3"

    local char_count=${#content}
    local preview=$(echo "$content" | head -3 | tr '\n' ' ' | cut -c1-80)

    log_info "${type^} 프롬프트 전송 (${char_count}자)"
    log_debug "미리보기: ${preview}..."

    # 파일 저장
    if [[ -n "$save_path" ]]; then
        echo "$content" > "$save_path"
        log_debug "프롬프트 저장: $save_path"
    fi
}

# 응답 로그 (요약 + 파일 저장)
# 사용법: log_response "writer" "응답 내용" "소요시간(초)" "/path/to/save"
log_response() {
    local type="$1"
    local content="$2"
    local elapsed="$3"
    local save_path="$4"

    local char_count=${#content}
    local preview=$(echo "$content" | head -3 | tr '\n' ' ' | cut -c1-80)

    if [[ $char_count -lt 100 ]]; then
        log_warn "${type^} 응답 짧음 (${char_count}자, ${elapsed}초)"
    else
        log_ok "${type^} 응답 완료 (${char_count}자, ${elapsed}초)"
    fi

    log_debug "미리보기: ${preview}..."

    # 파일 저장
    if [[ -n "$save_path" ]]; then
        echo "$content" > "$save_path"
        log_info "저장: $(basename "$save_path")"
    fi
}

# 평가 결과 로그
# 사용법: log_eval "점수" "강점" "개선점" "/path/to/save"
log_eval() {
    local score="$1"
    local strengths="$2"
    local weaknesses="$3"
    local save_path="$4"

    if [[ "$score" -ge 70 ]]; then
        log_ok "점수: ${score}점"
    elif [[ "$score" -ge 50 ]]; then
        log_info "점수: ${score}점"
    else
        log_warn "점수: ${score}점 (낮음)"
    fi

    if [[ -n "$strengths" ]]; then
        log_debug "강점: $strengths"
    fi
    if [[ -n "$weaknesses" ]]; then
        log_debug "개선점: $weaknesses"
    fi

    if [[ -n "$save_path" ]]; then
        log_info "저장: $(basename "$save_path")"
    fi
}

# ══════════════════════════════════════════════════════════════
# 버전별 상세 로그 저장
# ══════════════════════════════════════════════════════════════

# 버전 디렉토리 생성 및 경로 반환
# 사용법: version_dir=$(log_version_dir "/path/to/runs" "s1_2" "v1")
log_version_dir() {
    local run_dir="$1"
    local sample_id="$2"
    local version="$3"

    local version_dir="${run_dir}/${sample_id}_${version}"
    mkdir -p "$version_dir"
    echo "$version_dir"
}

# 메타 정보 저장
# 사용법: log_meta "$version_dir" "시작시간" "종료시간" "점수" "글자수"
log_meta() {
    local version_dir="$1"
    local start_time="$2"
    local end_time="$3"
    local score="$4"
    local char_count="$5"

    local meta_file="${version_dir}/meta.json"

    cat > "$meta_file" <<EOF
{
    "start_time": "$start_time",
    "end_time": "$end_time",
    "duration_sec": $((end_time - start_time)),
    "score": $score,
    "char_count": $char_count,
    "chapter": "$LOG_CHAPTER",
    "version": "$LOG_VERSION"
}
EOF
}

# ══════════════════════════════════════════════════════════════
# 유틸리티
# ══════════════════════════════════════════════════════════════

# 로그 파일 경로 반환
log_file_path() {
    echo "$LOG_FILE"
}

# 현재 컨텍스트 출력
log_context() {
    echo "Chapter: $LOG_CHAPTER, Version: $LOG_VERSION"
}
