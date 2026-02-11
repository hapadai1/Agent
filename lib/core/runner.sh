#!/bin/bash
# runner.sh - 공통 Runner 모듈
# 사용법: source lib/core/runner.sh
#
# 모든 프로젝트에서 재사용 가능한 Writer/Evaluator/Loop 로직 제공
# 스캐폴드에서 생성되는 step_runner.sh가 이 모듈을 사용합니다.

# ══════════════════════════════════════════════════════════════
# 모듈 로드
# ══════════════════════════════════════════════════════════════

_RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# JSON 유틸리티 (lib/core/json.sh 사용 가능하면)
if [[ -f "${_RUNNER_DIR}/json.sh" ]]; then
    source "${_RUNNER_DIR}/json.sh"
fi

# ══════════════════════════════════════════════════════════════
# 설정 변수 (프로젝트에서 override 가능)
# ══════════════════════════════════════════════════════════════

: "${RUNNER_TIMEOUT_WRITER:=300}"
: "${RUNNER_TIMEOUT_EVALUATOR:=180}"
: "${RUNNER_MAX_VERSION:=5}"
: "${RUNNER_TARGET_SCORE:=85}"
: "${RUNNER_MIN_WRITER_LEN:=100}"
: "${RUNNER_MIN_EVAL_LEN:=50}"

# ══════════════════════════════════════════════════════════════
# ChatGPT 에러 감지 (chatgpt.sh 의존성 없이 작동)
# ══════════════════════════════════════════════════════════════

# ChatGPT 응답이 에러인지 확인
# 사용법: if _runner_is_error "$response"; then handle_error; fi
_runner_is_error() {
    local response="$1"

    case "$response" in
        "__STOPPED__"|"__FAILED__"|"__STUCK__"|"__COMPLETED_BUT_EMPTY__"|"__TIMEOUT__"|"__EMPTY__")
            return 0
            ;;
        __ERROR__:*)
            return 0
            ;;
        ""|"no response"|"no markdown content"|"missing value")
            return 0
            ;;
    esac

    return 1
}

# 에러 메시지 생성
_runner_error_msg() {
    local response="$1"

    case "$response" in
        "__TIMEOUT__") echo "요청 시간 초과" ;;
        "__STOPPED__") echo "ChatGPT 중단됨" ;;
        "__FAILED__") echo "ChatGPT 호출 실패" ;;
        "__STUCK__") echo "ChatGPT 응답 없음" ;;
        "__COMPLETED_BUT_EMPTY__"|"__EMPTY__") echo "빈 응답" ;;
        __ERROR__:*) echo "오류: ${response#__ERROR__:}" ;;
        "") echo "빈 응답" ;;
        *) echo "알 수 없는 오류" ;;
    esac
}

# ══════════════════════════════════════════════════════════════
# JSON 추출/파싱 유틸리티
# ══════════════════════════════════════════════════════════════

# 텍스트에서 JSON 블록 추출
_runner_extract_json() {
    local content="$1"

    echo "$content" | python3 -c "
import re
import sys

content = sys.stdin.read()

# \`\`\`json ... \`\`\` 블록에서 추출
match = re.search(r'\`\`\`json\s*([\s\S]*?)\`\`\`', content)
if match:
    print(match.group(1).strip())
else:
    # 직접 JSON 찾기
    match = re.search(r'\{[\s\S]*\}', content)
    if match:
        print(match.group(0))
    else:
        print('{}')
" 2>/dev/null
}

# JSON에서 키 값 추출
_runner_json_get() {
    local json="$1"
    local key="$2"

    echo "$json" | python3 -c "
import json
import sys

try:
    data = json.load(sys.stdin)
    print(data.get('$key', ''))
except:
    print('')
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 상태 저장 (간단한 버전)
# ══════════════════════════════════════════════════════════════

# 상태 파일에 저장
# 사용법: _runner_save_state "completed" "$output_file" 1500 45
_runner_save_state() {
    local status="$1"
    local output_file="$2"
    local chars="${3:-0}"
    local duration="${4:-0}"

    local state_dir="${STATE_DIR:-${RUNTIME_DIR}/state}"
    local state_file="${state_dir}/current.json"
    mkdir -p "$state_dir"

    cat > "$state_file" <<EOF
{
  "section": "${SECTION:-unknown}",
  "version": ${VERSION:-1},
  "step": "${STEP:-unknown}",
  "status": "$status",
  "timestamp": "$(date -Iseconds)",
  "files": {
    "output": "$output_file"
  },
  "metrics": {
    "output_chars": $chars,
    "duration_sec": $duration
  }
}
EOF
}

# ══════════════════════════════════════════════════════════════
# Writer 실행
# ══════════════════════════════════════════════════════════════

# 범용 Writer 실행
# 사용법: runner_writer "$prompt" "$output_file" [--dry-run]
#
# 환경변수:
#   CHATGPT_TAB - ChatGPT 탭 번호 (기본: 1)
#   CHATGPT_PROJECT_URL - 프로젝트 URL (선택)
#   TIMEOUT_WRITER - 타임아웃 (기본: 300초)
#
# 반환값:
#   0: 성공 (출력 파일 생성됨)
#   1: 실패
runner_writer() {
    local prompt="$1"
    local output_file="$2"
    local dry_run="${3:-false}"

    local tab="${CHATGPT_TAB:-1}"
    local timeout="${TIMEOUT_WRITER:-$RUNNER_TIMEOUT_WRITER}"
    local project_url="${CHATGPT_PROJECT_URL:-}"

    echo "━━━ Writer 실행 ━━━"

    # 프롬프트 검증
    if [[ -z "$prompt" ]]; then
        echo "ERROR: 프롬프트가 비어있습니다" >&2
        return 1
    fi

    # Dry-run 모드
    if [[ "$dry_run" == "true" || "$dry_run" == "--dry-run" ]]; then
        echo "[DRY-RUN] ChatGPT 호출 스킵"
        echo "# DRY RUN - $(date)" > "$output_file"
        _runner_save_state "dry_run" "$output_file" 0 0
        return 0
    fi

    # ChatGPT 함수 확인
    if ! type chatgpt_call &>/dev/null; then
        echo "ERROR: chatgpt_call 함수를 찾을 수 없습니다. load_chatgpt를 먼저 호출하세요." >&2
        return 1
    fi

    # 새 채팅 시작
    echo "🔄 새 채팅 시작 (Tab $tab)"
    if [[ -n "$project_url" ]]; then
        chatgpt_call --mode=new_chat --tab="$tab" --project="$project_url" >/dev/null 2>&1
    else
        chatgpt_call --mode=new_chat --tab="$tab" >/dev/null 2>&1
    fi
    sleep 2

    # ChatGPT 호출
    local start_time=$(date +%s)
    echo "ChatGPT 호출 중 (timeout: ${timeout}초)..."

    local response
    response=$(chatgpt_call --tab="$tab" --timeout="$timeout" --retry "$prompt")

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # 에러 체크
    if _runner_is_error "$response"; then
        echo "⚠️ ChatGPT 오류: $(_runner_error_msg "$response")" >&2
        _runner_save_state "failed" "$output_file" 0 "$duration"
        return 1
    fi

    # 길이 체크
    local chars=${#response}
    if [[ $chars -lt $RUNNER_MIN_WRITER_LEN ]]; then
        echo "⚠️ 응답이 너무 짧음 (${chars}자 < ${RUNNER_MIN_WRITER_LEN}자)" >&2
        _runner_save_state "failed" "$output_file" "$chars" "$duration"
        return 1
    fi

    # 결과 저장
    echo "$response" > "$output_file"

    echo ""
    echo "━━━ Writer 결과 ━━━"
    echo "출력 파일: $output_file"
    echo "응답 길이: ${chars}자"
    echo "소요 시간: ${duration}초"

    _runner_save_state "completed" "$output_file" "$chars" "$duration"

    return 0
}

# ══════════════════════════════════════════════════════════════
# Evaluator 실행
# ══════════════════════════════════════════════════════════════

# 범용 Evaluator 실행
# 사용법: runner_evaluator "$writer_output_file" "$eval_prompt" "$eval_output_file" [--dry-run]
#
# 반환값:
#   0: 성공 (eval.json 생성됨)
#   1: 실패
runner_evaluator() {
    local writer_output_file="$1"
    local eval_prompt="$2"
    local eval_output_file="$3"
    local dry_run="${4:-false}"

    local tab="${CHATGPT_TAB:-1}"
    local timeout="${TIMEOUT_EVALUATOR:-$RUNNER_TIMEOUT_EVALUATOR}"
    local project_url="${CHATGPT_PROJECT_URL:-}"

    echo "━━━ Evaluator 실행 ━━━"

    # Writer 출력 확인
    if [[ ! -f "$writer_output_file" ]]; then
        echo "ERROR: Writer 출력 파일 없음: $writer_output_file" >&2
        return 1
    fi

    local writer_content
    writer_content=$(cat "$writer_output_file")
    local writer_len=${#writer_content}
    echo "Writer 출력: ${writer_len}자"

    # Dry-run 모드
    if [[ "$dry_run" == "true" || "$dry_run" == "--dry-run" ]]; then
        echo "[DRY-RUN] ChatGPT 호출 스킵"
        echo '{"total_score": 75, "feedback": "dry run"}' > "$eval_output_file"
        _runner_save_state "dry_run" "$eval_output_file" 0 0
        return 0
    fi

    # ChatGPT 함수 확인
    if ! type chatgpt_call &>/dev/null; then
        echo "ERROR: chatgpt_call 함수를 찾을 수 없습니다." >&2
        return 1
    fi

    # 새 채팅 시작
    echo "🔄 새 채팅 시작 (Tab $tab)"
    if [[ -n "$project_url" ]]; then
        chatgpt_call --mode=new_chat --tab="$tab" --project="$project_url" >/dev/null 2>&1
    else
        chatgpt_call --mode=new_chat --tab="$tab" >/dev/null 2>&1
    fi
    sleep 2

    # ChatGPT 호출
    local start_time=$(date +%s)
    echo "ChatGPT 호출 중 (timeout: ${timeout}초)..."

    local response
    response=$(chatgpt_call --tab="$tab" --timeout="$timeout" --retry "$eval_prompt")

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # 에러 체크
    if _runner_is_error "$response"; then
        echo "⚠️ ChatGPT 오류: $(_runner_error_msg "$response")" >&2
        _runner_save_state "failed" "$eval_output_file" 0 "$duration"
        return 1
    fi

    # JSON 추출
    local json_only
    json_only=$(_runner_extract_json "$response")
    local chars=${#json_only}

    # JSON 검증
    if [[ $chars -lt $RUNNER_MIN_EVAL_LEN ]]; then
        echo "⚠️ JSON 추출 실패 (${chars}자 < ${RUNNER_MIN_EVAL_LEN}자)" >&2
        _runner_save_state "failed" "$eval_output_file" "$chars" "$duration"
        return 1
    fi

    # 결과 저장
    echo "$json_only" > "$eval_output_file"

    # 점수 추출
    local score
    score=$(_runner_json_get "$json_only" "total_score")

    echo ""
    echo "━━━ Evaluator 결과 ━━━"
    echo "출력 파일: $eval_output_file"
    echo "JSON 길이: ${chars}자"
    echo "평가 점수: ${score}점"
    echo "소요 시간: ${duration}초"

    _runner_save_state "completed" "$eval_output_file" "$chars" "$duration"

    return 0
}

# ══════════════════════════════════════════════════════════════
# Loop 실행
# ══════════════════════════════════════════════════════════════

# 범용 Loop 실행
# 사용법: runner_loop "$section" "$start_version" "$writer_fn" "$evaluator_fn" [options]
#
# 콜백 함수:
#   writer_fn($version) - Writer 실행 함수
#   evaluator_fn($version) - Evaluator 실행 함수
#
# 옵션 (환경변수):
#   LOOP_MAX - 최대 반복 횟수 (기본: 5)
#   LOOP_TARGET - 목표 점수 (기본: 85)
#   DRY_RUN - "true"면 테스트 모드
#
# 반환값:
#   0: 목표 달성
#   1: 최대 버전 도달 (목표 미달성)
runner_loop() {
    local section="$1"
    local start_version="${2:-1}"
    local writer_fn="${3:-run_writer}"
    local evaluator_fn="${4:-run_evaluator}"

    local loop_max="${LOOP_MAX:-$RUNNER_MAX_VERSION}"
    local loop_target="${LOOP_TARGET:-$RUNNER_TARGET_SCORE}"
    local max_version=$((start_version + loop_max - 1))
    local current_version="$start_version"
    local current_score=0
    local loop_start_time=$(date +%s)

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  🔄 자동 반복 모드 (Loop Mode)                               ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  섹션:      $section"
    echo "║  시작 버전: v${start_version}"
    echo "║  반복 횟수: ${loop_max}회 (v${start_version} ~ v${max_version})"
    echo "║  목표 점수: ${loop_target}점"
    echo "║  시작 시간: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    while [[ $current_version -le $max_version ]]; do
        echo ""
        echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
        echo "┃  📝 버전 v${current_version} / v${max_version} 시작                              ┃"
        echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"

        # VERSION 변수 업데이트
        export VERSION="$current_version"
        export SECTION="$section"

        # Writer 실행
        echo ""
        echo "━━━ [v${current_version}] Step 1/2: Writer 실행 ━━━"
        if ! "$writer_fn" "$current_version"; then
            echo "❌ Writer 실행 실패 (v${current_version})"
            ((current_version++))
            continue
        fi

        # Evaluator 실행
        echo ""
        echo "━━━ [v${current_version}] Step 2/2: Evaluator 실행 ━━━"
        if ! "$evaluator_fn" "$current_version"; then
            echo "❌ Evaluator 실행 실패 (v${current_version})"
            ((current_version++))
            continue
        fi

        # 점수 확인 (RUNS_DIR과 SECTION 사용)
        local eval_file="${RUNS_DIR}/${section}_v${current_version}.eval.json"
        if [[ -f "$eval_file" ]]; then
            current_score=$(python3 -c "import json; print(json.load(open('$eval_file')).get('total_score', 0))" 2>/dev/null || echo "0")
        else
            current_score=0
        fi

        echo ""
        echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
        echo "┃  ✅ 버전 v${current_version} 완료: ${current_score}점                            ┃"
        echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"

        # 목표 점수 달성 확인
        if [[ $current_score -ge $loop_target ]]; then
            echo ""
            echo "🎯 목표 점수 달성! (${current_score}점 >= ${loop_target}점)"
            break
        fi

        ((current_version++))

        if [[ $current_version -le $max_version ]]; then
            echo ""
            echo "📊 점수 미달 (${current_score}점 < ${loop_target}점) → v${current_version} 진행"
        fi
    done

    # 최종 결과
    local loop_end_time=$(date +%s)
    local loop_duration=$((loop_end_time - loop_start_time))
    local loop_minutes=$((loop_duration / 60))
    local loop_seconds=$((loop_duration % 60))

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  🏁 반복 완료                                                ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║  섹션:      $section"
    echo "║  최종 버전: v${VERSION}"
    echo "║  최종 점수: ${current_score}점"
    echo "║  목표 점수: ${loop_target}점"
    if [[ $current_score -ge $loop_target ]]; then
        echo "║  결과:      ✅ 목표 달성"
    else
        echo "║  결과:      ⚠️  최대 버전 도달"
    fi
    echo "║  소요 시간: ${loop_minutes}분 ${loop_seconds}초"
    echo "║  종료 시간: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "╚══════════════════════════════════════════════════════════════╝"

    if [[ $current_score -ge $loop_target ]]; then
        return 0
    else
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════
# 유틸리티 함수
# ══════════════════════════════════════════════════════════════

# 프롬프트 파일 로드 및 변수 치환
# 사용법: prompt=$(runner_load_prompt "$template_file" "key1=value1" "key2=value2")
runner_load_prompt() {
    local template_file="$1"
    shift

    if [[ ! -f "$template_file" ]]; then
        echo "ERROR: 프롬프트 파일 없음: $template_file" >&2
        return 1
    fi

    local template
    template=$(cat "$template_file")

    # 변수 치환 (key=value 쌍)
    for kv in "$@"; do
        local key="${kv%%=*}"
        local value="${kv#*=}"
        template="${template//\{$key\}/$value}"
    done

    echo "$template"
}

# Evaluator 프롬프트 생성 (Writer 출력 포함)
# 사용법: prompt=$(runner_eval_prompt "$template_file" "$section_name" "$writer_output")
runner_eval_prompt() {
    local template_file="$1"
    local section_name="$2"
    local writer_output="$3"

    if [[ ! -f "$template_file" ]]; then
        echo "ERROR: Evaluator 프롬프트 파일 없음: $template_file" >&2
        return 1
    fi

    local template
    template=$(cat "$template_file")

    # 치환
    template="${template//\{section_name\}/$section_name}"
    template="${template//\{section_content\}/$writer_output}"

    echo "$template"
}

# 이전 버전 평가 피드백 로드
# 사용법: feedback=$(runner_load_feedback "$runs_dir" "$section" "$current_version")
runner_load_feedback() {
    local runs_dir="$1"
    local section="$2"
    local version="$3"

    local prev_version=$((version - 1))
    local prev_eval_file="${runs_dir}/${section}_v${prev_version}.eval.json"

    if [[ ! -f "$prev_eval_file" ]]; then
        echo ""
        return 1
    fi

    python3 -c "
import json
try:
    with open('$prev_eval_file', 'r') as f:
        data = json.load(f)

    score = data.get('total_score', 0)
    tags = data.get('defect_tags', [])
    weaknesses = data.get('weaknesses', [])
    priority_fix = data.get('priority_fix', '')

    feedback = f'이전 점수: {score}점\\n'
    if tags:
        feedback += f'결함 태그: {\", \".join(tags)}\\n'
    if weaknesses:
        feedback += '주요 약점:\\n'
        for w in weaknesses[:3]:
            issue = w.get('issue', '')[:150]
            fix = w.get('fix', '')[:150]
            feedback += f'- 문제: {issue}\\n  해결: {fix}\\n'
    if priority_fix:
        feedback += f'최우선 개선: {priority_fix[:200]}'

    print(feedback)
except Exception as e:
    pass
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 모듈 로드 완료 메시지
# ══════════════════════════════════════════════════════════════

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "lib/core/runner.sh - 공통 Runner 모듈"
    echo ""
    echo "사용법: source lib/core/runner.sh"
    echo ""
    echo "주요 함수:"
    echo "  runner_writer \"\$prompt\" \"\$output_file\"      - Writer 실행"
    echo "  runner_evaluator \"\$in\" \"\$prompt\" \"\$out\"    - Evaluator 실행"
    echo "  runner_loop \"\$section\" \"\$ver\" fn1 fn2       - Loop 실행"
    echo ""
    echo "유틸리티:"
    echo "  runner_load_prompt \"\$file\" \"k1=v1\" ...        - 프롬프트 로드"
    echo "  runner_eval_prompt \"\$file\" \"\$name\" \"\$out\"   - Eval 프롬프트"
    echo "  runner_load_feedback \"\$dir\" \"\$sec\" \"\$ver\"   - 피드백 로드"
fi
