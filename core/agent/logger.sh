#!/bin/bash
# logger.sh - Agent 로그 기록
#
# 사용법:
#   source logger.sh
#   log_action "claude" "start_loop" '{"section":"s1_2"}'

# 프로젝트 루트 찾기
find_project_root() {
  local dir="${1:-.}"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.rai" || -d "$dir/core/agent" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo "."
}

PROJECT_ROOT="$(find_project_root "$(pwd)")"
RAI_DIR="${PROJECT_ROOT}/.rai"
LOG_FILE="${RAI_DIR}/agent_log.jsonl"
STATE_FILE="${RAI_DIR}/agent_state.json"
LOCK_FILE="${RAI_DIR}/.agent.lock"

# 로그 파일 초기화 (없으면 생성)
init_log() {
  mkdir -p "$RAI_DIR"
  touch "$LOG_FILE"
}

# trace_id 생성 (타임스탬프 기반)
generate_trace_id() {
  echo "run_$(date +%Y%m%d_%H%M%S)_$$"
}

# 현재 trace_id 가져오기 (없으면 생성)
get_trace_id() {
  local trace_id
  trace_id=$(jq -r '.trace_id // empty' "$STATE_FILE" 2>/dev/null)
  if [[ -z "$trace_id" || "$trace_id" == "null" ]]; then
    trace_id=$(generate_trace_id)
    update_state ".trace_id" "\"$trace_id\""
  fi
  echo "$trace_id"
}

# 시퀀스 번호 가져오기 (trace_id 기준)
get_next_seq() {
  local trace_id="$1"
  local last_seq
  last_seq=$(grep "\"trace_id\":\"$trace_id\"" "$LOG_FILE" 2>/dev/null | tail -1 | jq -r '.seq // 0' 2>/dev/null)
  last_seq=${last_seq:-0}
  if [[ -z "$last_seq" || "$last_seq" == "null" ]]; then
    last_seq=0
  fi
  echo $((last_seq + 1))
}

# 타임스탬프
get_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ============================================================
# 로그 기록 함수들
# ============================================================

# 기본 로그 기록 (간소화)
log_entry() {
  local agent="$1"
  local action="$2"
  shift 2
  local extra_args=("$@")

  local trace_id
  trace_id=$(get_trace_id)
  local seq
  seq=$(get_next_seq "$trace_id")
  seq=${seq:-1}
  local ts
  ts=$(get_timestamp)

  # 기본 JSON 생성
  local entry
  entry="{\"trace_id\":\"$trace_id\",\"seq\":$seq,\"ts\":\"$ts\",\"agent\":\"$agent\",\"action\":\"$action\""

  # 추가 키-값 쌍 추가
  for kv in "${extra_args[@]}"; do
    entry="$entry,$kv"
  done

  entry="$entry}"

  echo "$entry" >> "$LOG_FILE"
  echo "$entry"
}

# 액션 로그 (일반)
log_action() {
  local agent="$1"
  local action="$2"
  shift 2
  log_entry "$agent" "$action" "$@"
}

# 판단 로그 (decision + reasons)
log_decision() {
  local agent="$1"
  local decision="$2"
  local reasons="$3"
  local score="${4:-0}"

  log_entry "$agent" "decision" \
    "\"decision\":\"$decision\"" \
    "\"reasons\":$reasons" \
    "\"score\":$score"
}

# 생성 완료 로그
log_generate() {
  local output_file="$1"
  local chars="$2"

  log_entry "gpt_tab3" "generate" \
    "\"output_file\":\"$output_file\"" \
    "\"chars\":$chars"
}

# 평가 완료 로그
log_evaluate() {
  local output_file="$1"
  local score="$2"
  local defect_count="$3"

  log_entry "gpt_tab4" "evaluate" \
    "\"output_file\":\"$output_file\"" \
    "\"score\":$score" \
    "\"defect_count\":$defect_count"
}

# ============================================================
# 상태 관리 함수들
# ============================================================

# 상태 업데이트
update_state() {
  local path="$1"
  local value="$2"

  local tmp_file="${STATE_FILE}.tmp"
  jq "$path = $value" "$STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$STATE_FILE"
}

# 현재 상태 읽기
get_state() {
  local path="$1"
  jq -r "$path" "$STATE_FILE" 2>/dev/null || echo ""
}

# 새 trace 시작
start_new_trace() {
  local section="$1"
  local version="$2"

  local trace_id
  trace_id=$(generate_trace_id)

  # 상태 초기화
  jq -n \
    --arg trace_id "$trace_id" \
    --arg section "$section" \
    --arg version "$version" \
    '{
      current: {
        section: $section,
        version: $version,
        stage: "generate",
        retry_count: 0
      },
      last_decision: {
        decision: null,
        reasons: [],
        timestamp: null
      },
      trace_id: $trace_id,
      lock: false
    }' > "$STATE_FILE"

  log_action "claude" "start_trace" "\"section\":\"$section\"" "\"version\":\"$version\""

  echo "$trace_id"
}

# 스테이지 업데이트
update_stage() {
  local stage="$1"
  update_state ".current.stage" "\"$stage\""
  log_action "claude" "stage_change" "\"stage\":\"$stage\""
}

# 재시도 카운트 증가
increment_retry() {
  local current
  current=$(get_state ".current.retry_count")
  current=${current:-0}
  local next=$((current + 1))
  update_state ".current.retry_count" "$next"
  echo "$next"
}

# 재시도 카운트 리셋
reset_retry() {
  update_state ".current.retry_count" "0"
}

# ============================================================
# 락 관리
# ============================================================

acquire_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    local pid
    pid=$(cat "$LOCK_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "Agent already running (PID: $pid)"
      return 1
    fi
  fi
  echo $$ > "$LOCK_FILE"
  update_state ".lock" "true"
  return 0
}

release_lock() {
  rm -f "$LOCK_FILE"
  update_state ".lock" "false"
}

# 초기화
init_log
