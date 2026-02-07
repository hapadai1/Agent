#!/bin/bash
# hard_gate.sh - 규칙 기반 품질 판정
#
# 사용법:
#   ./hard_gate.sh --type=generate --file=path/to/output.md
#   ./hard_gate.sh --type=eval --file=path/to/eval.json
#
# 출력: JSON (stdout)
# Exit codes: 0=PASS, 1=RETRY_SAME_CHAT, 2=RETRY_NEW_CHAT, 3=STOP

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.json"

# 파라미터 파싱
TYPE=""
FILE=""

for arg in "$@"; do
  case $arg in
    --type=*)
      TYPE="${arg#*=}"
      ;;
    --file=*)
      FILE="${arg#*=}"
      ;;
  esac
done

# 유효성 검사
if [[ -z "$TYPE" || -z "$FILE" ]]; then
  echo '{"decision":"STOP","reasons":["missing required arguments: --type and --file"]}'
  exit 3
fi

if [[ ! -f "$FILE" ]]; then
  echo '{"decision":"RETRY_SAME_CHAT","reasons":["file not found: '"$FILE"'"]}'
  exit 1
fi

# config.json 로드
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo '{"decision":"STOP","reasons":["config.json not found"]}'
  exit 3
fi

# ============================================================
# 생성 결과 (out.md) 판정
# ============================================================
check_generate() {
  local file="$1"
  local reasons=()
  local decision="PASS"

  # 파일 내용 읽기
  local content
  content=$(cat "$file")
  local char_count=${#content}
  local line_count
  line_count=$(wc -l < "$file" | tr -d ' ')

  # 1. 최소 글자수 체크 (1200자)
  local min_length
  min_length=$(jq -r '.hard_gate.generate.min_output_length' "$CONFIG_FILE")
  if [[ $char_count -lt $min_length ]]; then
    reasons+=("output_length: $char_count < $min_length")
    decision="RETRY_SAME_CHAT"
  fi

  # 2. 빈 출력 체크
  if [[ $char_count -lt 100 ]]; then
    reasons+=("empty_or_minimal_output: $char_count chars")
    decision="RETRY_SAME_CHAT"
  fi

  # 3. 도메인 반복 체크 (같은 도메인 5회 이상)
  local max_domain_repeat
  max_domain_repeat=$(jq -r '.hard_gate.generate.max_domain_repeat' "$CONFIG_FILE")

  # URL에서 도메인 추출하고 카운트
  local domain_counts
  domain_counts=$(grep -oE 'https?://[^/]+' "$file" 2>/dev/null | sort | uniq -c | sort -rn | head -1 || echo "0")
  local top_domain_count
  top_domain_count=$(echo "$domain_counts" | awk '{print $1}' | tr -d ' ')
  top_domain_count=${top_domain_count:-0}

  if [[ $top_domain_count -ge $max_domain_repeat ]]; then
    local top_domain
    top_domain=$(echo "$domain_counts" | awk '{print $2}')
    reasons+=("domain_repeat: $top_domain appears $top_domain_count times (>= $max_domain_repeat)")
    decision="RETRY_NEW_CHAT"
  fi

  # 4. URL 비율 체크 (30% 이상)
  local max_url_ratio
  max_url_ratio=$(jq -r '.hard_gate.generate.max_url_line_ratio' "$CONFIG_FILE")
  local url_lines
  url_lines=$(grep -cE 'https?://' "$file" 2>/dev/null || echo "0")

  if [[ $line_count -gt 0 ]]; then
    local url_ratio
    url_ratio=$(echo "scale=2; $url_lines / $line_count" | bc)
    if (( $(echo "$url_ratio >= $max_url_ratio" | bc -l) )); then
      reasons+=("url_line_ratio: $url_ratio >= $max_url_ratio")
      decision="RETRY_NEW_CHAT"
    fi
  fi

  # 5. 필수 키워드 체크
  local required_min
  required_min=$(jq -r '.hard_gate.generate.required_keyword_min' "$CONFIG_FILE")
  local keywords
  keywords=$(jq -r '.hard_gate.generate.required_keywords[]' "$CONFIG_FILE")

  local found_count=0
  local missing_keywords=()
  while IFS= read -r keyword; do
    if grep -q "$keyword" "$file"; then
      ((found_count++))
    else
      missing_keywords+=("$keyword")
    fi
  done <<< "$keywords"

  if [[ $found_count -lt $required_min ]]; then
    reasons+=("missing_keywords: [${missing_keywords[*]}] (found $found_count < $required_min)")
    if [[ "$decision" != "RETRY_NEW_CHAT" ]]; then
      decision="RETRY_NEW_CHAT"
    fi
  fi

  # 6. 금지 토큰 체크
  local forbidden
  forbidden=$(jq -r '.hard_gate.generate.forbidden_tokens[]' "$CONFIG_FILE")
  local found_forbidden=()

  while IFS= read -r token; do
    if grep -qiF "$token" "$file" 2>/dev/null; then
      found_forbidden+=("$token")
    fi
  done <<< "$forbidden"

  if [[ ${#found_forbidden[@]} -gt 0 ]]; then
    reasons+=("forbidden_tokens: [${found_forbidden[*]}]")
    if [[ "$decision" == "PASS" ]]; then
      decision="RETRY_SAME_CHAT"
    fi
  fi

  # 7. 이상 패턴 체크 (컨텍스트 오염 징후)
  if grep -qiE '이전에 말씀드린|앞서 언급한|다음 섹션에서' "$file"; then
    reasons+=("context_pollution: found cross-reference pattern")
    decision="RETRY_NEW_CHAT"
  fi

  # 결과 출력
  local reasons_json
  if [[ ${#reasons[@]} -eq 0 ]]; then
    reasons_json="[]"
  else
    reasons_json=$(printf '%s\n' "${reasons[@]}" | jq -R . | jq -s .)
  fi

  echo "{\"decision\":\"$decision\",\"reasons\":$reasons_json,\"stats\":{\"chars\":$char_count,\"lines\":$line_count}}"

  # exit code
  case $decision in
    PASS) exit 0 ;;
    RETRY_SAME_CHAT) exit 1 ;;
    RETRY_NEW_CHAT) exit 2 ;;
    STOP) exit 3 ;;
  esac
}

# ============================================================
# 평가 결과 (eval.json) 판정
# ============================================================
check_eval() {
  local file="$1"
  local reasons=()
  local decision="PASS"

  # JSON 파싱 체크
  if ! jq empty "$file" 2>/dev/null; then
    reasons+=("json_parse_failed")
    echo '{"decision":"RETRY_NEW_CHAT","reasons":["json_parse_failed"]}'
    exit 2
  fi

  # score 추출
  local score
  score=$(jq -r '.total_score // .score // 0' "$file" 2>/dev/null || echo "0")

  # defect_tags 추출
  local defect_count
  defect_count=$(jq -r '.defect_tags | length' "$file" 2>/dev/null || echo "0")

  # 1. score=0 체크
  if [[ "$score" == "0" || "$score" == "null" ]]; then
    reasons+=("score_is_zero")

    # score=0 이면서 defect_tags도 없으면 평가 실패
    if [[ "$defect_count" == "0" ]]; then
      reasons+=("no_defect_tags_with_zero_score")
      decision="RETRY_NEW_CHAT"
    else
      decision="RETRY_SAME_CHAT"
    fi
  fi

  # 2. 낮은 점수인데 defect_tags 없음
  local low_threshold
  low_threshold=$(jq -r '.hard_gate.eval.low_score_threshold' "$CONFIG_FILE")

  if [[ "$score" -lt "$low_threshold" && "$defect_count" == "0" ]]; then
    reasons+=("low_score_without_defects: score=$score < $low_threshold, defects=0")
    decision="RETRY_NEW_CHAT"
  fi

  # 결과 출력
  local reasons_json
  if [[ ${#reasons[@]} -eq 0 ]]; then
    reasons_json="[]"
  else
    reasons_json=$(printf '%s\n' "${reasons[@]}" | jq -R . | jq -s .)
  fi

  echo "{\"decision\":\"$decision\",\"reasons\":$reasons_json,\"stats\":{\"score\":$score,\"defect_count\":$defect_count}}"

  # exit code
  case $decision in
    PASS) exit 0 ;;
    RETRY_SAME_CHAT) exit 1 ;;
    RETRY_NEW_CHAT) exit 2 ;;
    STOP) exit 3 ;;
  esac
}

# ============================================================
# 메인
# ============================================================
case $TYPE in
  generate)
    check_generate "$FILE"
    ;;
  eval)
    check_eval "$FILE"
    ;;
  *)
    echo '{"decision":"STOP","reasons":["unknown type: '"$TYPE"'"]}'
    exit 3
    ;;
esac
