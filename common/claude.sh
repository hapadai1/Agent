#!/bin/bash
# claude.sh - Claude CLI 래퍼
# Claude Code CLI를 이용한 자동화 호출
#
# 사용법:
#   source claude.sh
#   claude_call --action=review --input=file.md
#   claude_call --action=judge --input=content.md --input=eval.json
#
# 필수: claude CLI 설치 (claude-code)

# set -euo pipefail  # source 시 문제 방지를 위해 비활성화

_CLAUDE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ══════════════════════════════════════════════════════════════
# 설정 (환경변수로 오버라이드 가능)
# ══════════════════════════════════════════════════════════════
: "${CLAUDE_MODEL:=sonnet}"              # 기본 모델
: "${CLAUDE_TIMEOUT:=300}"               # 타임아웃 (초)
: "${CLAUDE_OUTPUT_FORMAT:=json}"        # 출력 형식
: "${CLAUDE_DECISION_SCHEMA:=}"          # 결정 JSON 스키마 파일
: "${CLAUDE_TEMPLATES_DIR:=$_CLAUDE_SCRIPT_DIR/../templates/claude}"

# 결정 JSON 스키마 (MVP)
CLAUDE_DECISION_SCHEMA_INLINE='{
  "type": "object",
  "properties": {
    "decision": {
      "type": "string",
      "enum": ["PASS", "RERUN_PREV", "GOTO", "STOP"]
    },
    "reasons": {
      "type": "array",
      "items": {"type": "string"},
      "minItems": 1
    },
    "next_instruction_for_gpt": {"type": "string"},
    "goto": {"type": "string"}
  },
  "required": ["decision", "reasons"]
}'

# ══════════════════════════════════════════════════════════════
# 유틸리티 함수
# ══════════════════════════════════════════════════════════════

# 로그 출력
_claude_log() {
    echo "[$(date '+%H:%M:%S')] [claude] $*" >&2
}

# 에러 출력
_claude_error() {
    echo "[$(date '+%H:%M:%S')] [claude] ❌ $*" >&2
}

# JSON 파싱 (python3)
_claude_json_get() {
    local json="$1"
    local key="$2"
    python3 -c "
import json, sys
try:
    obj = json.loads(sys.argv[1])
    print(obj.get(sys.argv[2], ''))
except:
    print('')
" "$json" "$key" 2>/dev/null || echo ""
}

# ══════════════════════════════════════════════════════════════
# 메인 호출 함수
# ══════════════════════════════════════════════════════════════

# Claude 호출 (통합)
# 사용법: claude_call [옵션]
#
# 옵션:
#   --action=ACTION       액션 이름 (review, judge, custom)
#   --input=FILE          입력 파일 (여러 개 가능)
#   --prompt=TEXT         직접 프롬프트 (--action 대신)
#   --system=TEXT         시스템 프롬프트
#   --template=FILE       템플릿 파일
#   --output=FILE         출력 파일 (없으면 stdout)
#   --model=MODEL         모델 (sonnet, opus, haiku)
#   --format=FORMAT       출력 형식 (json, text)
#   --schema              결정 JSON 스키마 강제
#   --timeout=SEC         타임아웃
#
claude_call() {
    local action=""
    local inputs=()
    local prompt=""
    local system_prompt=""
    local template=""
    local output_file=""
    local model="$CLAUDE_MODEL"
    local format="$CLAUDE_OUTPUT_FORMAT"
    local use_schema=false
    local timeout="$CLAUDE_TIMEOUT"

    # 옵션 파싱
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --action=*)
                action="${1#--action=}"
                shift
                ;;
            --input=*)
                inputs+=("${1#--input=}")
                shift
                ;;
            --prompt=*)
                prompt="${1#--prompt=}"
                shift
                ;;
            --system=*)
                system_prompt="${1#--system=}"
                shift
                ;;
            --template=*)
                template="${1#--template=}"
                shift
                ;;
            --output=*)
                output_file="${1#--output=}"
                shift
                ;;
            --model=*)
                model="${1#--model=}"
                shift
                ;;
            --format=*)
                format="${1#--format=}"
                shift
                ;;
            --schema)
                use_schema=true
                shift
                ;;
            --timeout=*)
                timeout="${1#--timeout=}"
                shift
                ;;
            *)
                _claude_error "알 수 없는 옵션: $1"
                return 1
                ;;
        esac
    done

    # 프롬프트 결정
    local final_prompt=""

    if [[ -n "$template" && -f "$template" ]]; then
        final_prompt="$(cat "$template")"
    elif [[ -n "$action" ]]; then
        # 액션별 기본 템플릿
        local action_template="$CLAUDE_TEMPLATES_DIR/${action}.md"
        if [[ -f "$action_template" ]]; then
            final_prompt="$(cat "$action_template")"
        else
            final_prompt="$(_claude_get_default_prompt "$action")"
        fi
    elif [[ -n "$prompt" ]]; then
        final_prompt="$prompt"
    else
        _claude_error "프롬프트가 필요합니다 (--action, --template, 또는 --prompt)"
        return 1
    fi

    # 입력 파일 내용 추가
    local input_content=""
    for input_file in "${inputs[@]}"; do
        if [[ -f "$input_file" ]]; then
            input_content+="
--- 입력: $(basename "$input_file") ---
$(cat "$input_file")
"
        else
            _claude_error "입력 파일 없음: $input_file"
            return 1
        fi
    done

    if [[ -n "$input_content" ]]; then
        final_prompt+="

$input_content"
    fi

    # Claude CLI 옵션 구성
    local claude_opts=()
    claude_opts+=("--print")
    claude_opts+=("--model" "$model")

    if [[ "$format" == "json" ]]; then
        claude_opts+=("--output-format" "json")
    fi

    if [[ -n "$system_prompt" ]]; then
        claude_opts+=("--system-prompt" "$system_prompt")
    fi

    if [[ "$use_schema" == true ]]; then
        claude_opts+=("--json-schema" "$CLAUDE_DECISION_SCHEMA_INLINE")
    fi

    # 로그
    _claude_log "액션: ${action:-custom}, 모델: $model, 입력: ${#inputs[@]}개"

    # Claude CLI 실행 (macOS 호환 - timeout 대신 직접 실행)
    local result
    local exit_code=0

    # timeout 명령 사용 가능 여부 확인
    if command -v gtimeout &>/dev/null; then
        result=$(gtimeout "$timeout" claude "${claude_opts[@]}" "$final_prompt" 2>&1) || exit_code=$?
    elif command -v timeout &>/dev/null; then
        result=$(timeout "$timeout" claude "${claude_opts[@]}" "$final_prompt" 2>&1) || exit_code=$?
    else
        # timeout 없이 실행 (macOS 기본)
        result=$(claude "${claude_opts[@]}" "$final_prompt" 2>&1) || exit_code=$?
    fi

    if [[ $exit_code -eq 124 ]]; then
        _claude_error "타임아웃 (${timeout}초)"
        echo "__TIMEOUT__"
        return 1
    elif [[ $exit_code -ne 0 ]]; then
        _claude_error "Claude CLI 오류 (exit=$exit_code)"
        echo "__ERROR__:$result"
        return 1
    fi

    # JSON 형식일 때 result 필드 추출
    if [[ "$format" == "json" ]]; then
        local extracted
        extracted=$(python3 -c "
import json, sys
try:
    obj = json.loads(sys.stdin.read())
    if 'result' in obj:
        print(obj['result'])
    else:
        print(json.dumps(obj, ensure_ascii=False))
except Exception as e:
    print(sys.stdin.read())
" <<< "$result" 2>/dev/null) || extracted="$result"
        result="$extracted"
    fi

    # 출력
    if [[ -n "$output_file" ]]; then
        echo "$result" > "$output_file"
        _claude_log "출력 저장: $output_file"
    else
        echo "$result"
    fi

    return 0
}

# ══════════════════════════════════════════════════════════════
# 액션별 기본 프롬프트
# ══════════════════════════════════════════════════════════════

_claude_get_default_prompt() {
    local action="$1"

    case "$action" in
        review)
            cat <<'EOF'
당신은 콘텐츠 검수자입니다. 아래 내용을 검토하고 결정을 내려주세요.

## 검토 기준
- 형식 준수 여부
- 근거/출처 포함 여부
- 논리적 흐름
- 완성도

## 출력 형식 (JSON)
```json
{
  "decision": "PASS | RERUN_PREV | STOP",
  "reasons": ["이유1", "이유2"],
  "next_instruction_for_gpt": "재실행 시 지시사항 (RERUN_PREV인 경우)"
}
```

decision 설명:
- PASS: 다음 단계로 진행
- RERUN_PREV: 이전 GPT 작업 재실행 필요
- STOP: 진행 중단 (심각한 문제)
EOF
            ;;
        judge)
            cat <<'EOF'
당신은 최종 판정자입니다. 콘텐츠와 평가 결과를 검토하고 최종 결정을 내려주세요.

## 출력 형식 (JSON)
```json
{
  "decision": "PASS | RERUN_PREV | GOTO | STOP",
  "reasons": ["이유1", "이유2"],
  "goto": "이동할 블록 ID (GOTO인 경우)",
  "next_instruction_for_gpt": "재실행 지시사항 (RERUN_PREV인 경우)"
}
```
EOF
            ;;
        *)
            echo "검토 후 JSON 형식으로 결정을 출력해주세요."
            ;;
    esac
}

# ══════════════════════════════════════════════════════════════
# 편의 함수 (액션별 래퍼)
# ══════════════════════════════════════════════════════════════

# 콘텐츠 검토
# 사용법: claude_review input.md [output.json]
claude_review() {
    local input="$1"
    local output="${2:-}"

    local opts=(--action=review --input="$input" --schema)
    [[ -n "$output" ]] && opts+=(--output="$output")

    claude_call "${opts[@]}"
}

# 최종 판정
# 사용법: claude_judge content.md eval.json [output.json]
claude_judge() {
    local content="$1"
    local eval_file="$2"
    local output="${3:-}"

    local opts=(--action=judge --input="$content" --input="$eval_file" --schema)
    [[ -n "$output" ]] && opts+=(--output="$output")

    claude_call "${opts[@]}"
}

# ══════════════════════════════════════════════════════════════
# 결정 파싱 유틸리티
# ══════════════════════════════════════════════════════════════

# 결정 JSON에서 decision 추출
# 사용법: decision=$(claude_get_decision "$json")
claude_get_decision() {
    local json="$1"
    _claude_json_get "$json" "decision"
}

# 결정 JSON에서 reasons 추출
claude_get_reasons() {
    local json="$1"
    python3 -c "
import json, sys
try:
    obj = json.loads(sys.argv[1])
    reasons = obj.get('reasons', [])
    for r in reasons:
        print(r)
except:
    pass
" "$json" 2>/dev/null
}

# 결정 JSON에서 next_instruction 추출
claude_get_instruction() {
    local json="$1"
    _claude_json_get "$json" "next_instruction_for_gpt"
}

# 결정 JSON에서 goto 추출
claude_get_goto() {
    local json="$1"
    _claude_json_get "$json" "goto"
}

# ══════════════════════════════════════════════════════════════
# 스크립트 직접 실행 시 도움말
# ══════════════════════════════════════════════════════════════

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "Claude CLI 래퍼 스크립트"
    echo ""
    echo "사용법: source claude.sh 로 로드 후 함수 사용"
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "주요 함수"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "claude_call [옵션]        # 통합 호출 함수"
    echo "  --action=ACTION         # 액션 (review, judge)"
    echo "  --input=FILE            # 입력 파일 (여러 개 가능)"
    echo "  --output=FILE           # 출력 파일"
    echo "  --model=MODEL           # 모델 (sonnet, opus, haiku)"
    echo "  --schema                # 결정 JSON 스키마 강제"
    echo ""
    echo "claude_review FILE [OUT]  # 콘텐츠 검토"
    echo "claude_judge A B [OUT]    # 최종 판정"
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "결정 파싱"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "claude_get_decision JSON  # decision 추출"
    echo "claude_get_reasons JSON   # reasons 추출"
    echo "claude_get_instruction JSON  # next_instruction 추출"
    echo "claude_get_goto JSON      # goto 추출"
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "설정 (환경변수)"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "CLAUDE_MODEL=$CLAUDE_MODEL"
    echo "CLAUDE_TIMEOUT=$CLAUDE_TIMEOUT"
    echo "CLAUDE_OUTPUT_FORMAT=$CLAUDE_OUTPUT_FORMAT"
fi
