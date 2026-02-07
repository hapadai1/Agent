#!/bin/bash
# usage_meter.sh - LLM 사용량 측정 및 기록
# latency, 응답 길이, 성공/실패 추적

USAGE_METER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ══════════════════════════════════════════════════════════════
# 설정
# ══════════════════════════════════════════════════════════════

# 로그 디렉토리 (PROJECT_DIR이 있으면 프로젝트별, 없으면 전역)
_usage_log_dir() {
    if [[ -n "$PROJECT_DIR" ]]; then
        echo "${PROJECT_DIR}/logs/llm"
    else
        echo "${USAGE_METER_DIR}/../../logs/llm"
    fi
}

# 로그 파일
_usage_log_file() {
    local dir=$(_usage_log_dir)
    mkdir -p "$dir" 2>/dev/null
    echo "${dir}/usage_$(date +%Y-%m-%d).log"
}

# 통계 파일
_usage_stats_file() {
    local dir=$(_usage_log_dir)
    mkdir -p "$dir" 2>/dev/null
    echo "${dir}/stats.json"
}

# ══════════════════════════════════════════════════════════════
# 사용량 로깅
# ══════════════════════════════════════════════════════════════

# 사용량 기록
# 사용법: usage_log <provider> <latency_ms> <response_len> <exit_code>
usage_log() {
    local provider="$1"
    local latency_ms="$2"
    local response_len="$3"
    local exit_code="${4:-0}"

    local log_file=$(_usage_log_file)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local run_id="${RUN_ID:-$(date +%s)}"
    local step_id="${CURRENT_STEP:-unknown}"

    # 성공/실패 판정
    local status="success"
    if [[ "$exit_code" -ne 0 ]]; then
        status="failure"
    fi

    # 로그 기록
    echo "${timestamp}|${run_id}|${step_id}|${provider}|${latency_ms}ms|${response_len}chars|${status}" >> "$log_file"

    # 통계 업데이트
    _usage_update_stats "$provider" "$latency_ms" "$response_len" "$status"
}

# 통계 업데이트
_usage_update_stats() {
    local provider="$1"
    local latency_ms="$2"
    local response_len="$3"
    local status="$4"

    local stats_file=$(_usage_stats_file)

    python3 -c "
import json
import os
from datetime import datetime

stats_file = '$stats_file'
provider = '$provider'
latency = int('$latency_ms') if '$latency_ms'.isdigit() else 0
response_len = int('$response_len') if '$response_len'.isdigit() else 0
status = '$status'

# 기존 통계 로드
if os.path.exists(stats_file):
    try:
        with open(stats_file, 'r') as f:
            stats = json.load(f)
    except:
        stats = {}
else:
    stats = {}

# 오늘 날짜
today = datetime.now().strftime('%Y-%m-%d')

# 초기화
if 'providers' not in stats:
    stats['providers'] = {}
if provider not in stats['providers']:
    stats['providers'][provider] = {
        'total_calls': 0,
        'success_count': 0,
        'failure_count': 0,
        'total_latency_ms': 0,
        'total_response_chars': 0,
        'daily': {}
    }

p = stats['providers'][provider]

# 전체 통계 업데이트
p['total_calls'] += 1
if status == 'success':
    p['success_count'] += 1
else:
    p['failure_count'] += 1
p['total_latency_ms'] += latency
p['total_response_chars'] += response_len

# 일별 통계
if today not in p['daily']:
    p['daily'][today] = {'calls': 0, 'success': 0, 'failure': 0, 'latency_ms': 0}
p['daily'][today]['calls'] += 1
if status == 'success':
    p['daily'][today]['success'] += 1
else:
    p['daily'][today]['failure'] += 1
p['daily'][today]['latency_ms'] += latency

# 평균 계산
if p['total_calls'] > 0:
    p['avg_latency_ms'] = p['total_latency_ms'] // p['total_calls']
    p['success_rate'] = round(p['success_count'] / p['total_calls'] * 100, 1)

# 마지막 업데이트 시간
stats['last_updated'] = datetime.now().isoformat()

# 저장
with open(stats_file, 'w') as f:
    json.dump(stats, f, indent=2, ensure_ascii=False)
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 통계 조회
# ══════════════════════════════════════════════════════════════

# 전체 통계 출력
usage_stats() {
    local stats_file=$(_usage_stats_file)

    if [[ ! -f "$stats_file" ]]; then
        echo "No usage data yet"
        return
    fi

    python3 -c "
import json

with open('$stats_file', 'r') as f:
    stats = json.load(f)

print('LLM Usage Statistics')
print('═' * 50)
print()

for provider, data in stats.get('providers', {}).items():
    print(f'[{provider.upper()}]')
    print(f'  Total calls:     {data.get(\"total_calls\", 0)}')
    print(f'  Success rate:    {data.get(\"success_rate\", 0)}%')
    print(f'  Avg latency:     {data.get(\"avg_latency_ms\", 0)}ms')
    print(f'  Total chars:     {data.get(\"total_response_chars\", 0):,}')
    print()

print(f'Last updated: {stats.get(\"last_updated\", \"N/A\")}')
" 2>/dev/null
}

# 오늘 통계
usage_today() {
    local stats_file=$(_usage_stats_file)
    local today=$(date +%Y-%m-%d)

    if [[ ! -f "$stats_file" ]]; then
        echo "No usage data yet"
        return
    fi

    python3 -c "
import json

with open('$stats_file', 'r') as f:
    stats = json.load(f)

today = '$today'
print(f'Today ({today}) Usage')
print('═' * 40)
print()

for provider, data in stats.get('providers', {}).items():
    daily = data.get('daily', {}).get(today, {})
    if daily:
        print(f'[{provider.upper()}]')
        print(f'  Calls:    {daily.get(\"calls\", 0)}')
        print(f'  Success:  {daily.get(\"success\", 0)}')
        print(f'  Failure:  {daily.get(\"failure\", 0)}')
        print(f'  Latency:  {daily.get(\"latency_ms\", 0)}ms total')
        print()
" 2>/dev/null
}

# Provider별 통계
usage_provider() {
    local provider="$1"
    local stats_file=$(_usage_stats_file)

    if [[ -z "$provider" ]]; then
        echo "Usage: usage_provider <provider>" >&2
        return 1
    fi

    if [[ ! -f "$stats_file" ]]; then
        echo "No usage data yet"
        return
    fi

    python3 -c "
import json

with open('$stats_file', 'r') as f:
    stats = json.load(f)

provider = '$provider'
data = stats.get('providers', {}).get(provider)

if not data:
    print(f'No data for provider: {provider}')
else:
    print(f'{provider.upper()} Statistics')
    print('═' * 40)
    print()
    print(f'Total calls:       {data.get(\"total_calls\", 0)}')
    print(f'Success count:     {data.get(\"success_count\", 0)}')
    print(f'Failure count:     {data.get(\"failure_count\", 0)}')
    print(f'Success rate:      {data.get(\"success_rate\", 0)}%')
    print(f'Avg latency:       {data.get(\"avg_latency_ms\", 0)}ms')
    print(f'Total chars:       {data.get(\"total_response_chars\", 0):,}')
    print()
    print('Daily breakdown:')
    for day, d in sorted(data.get('daily', {}).items(), reverse=True)[:7]:
        print(f'  {day}: {d.get(\"calls\", 0)} calls, {d.get(\"success\", 0)} success')
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 로그 조회
# ══════════════════════════════════════════════════════════════

# 최근 로그
usage_recent() {
    local count="${1:-10}"
    local log_file=$(_usage_log_file)

    if [[ ! -f "$log_file" ]]; then
        echo "No log for today"
        return
    fi

    echo "Recent $count calls:"
    echo ""
    tail -n "$count" "$log_file" | while IFS='|' read -r ts run_id step_id provider latency chars status; do
        printf "  %s | %-8s | %s | %s | %s\n" "$ts" "$provider" "$latency" "$chars" "$status"
    done
}

# 로그 파일 위치
usage_log_path() {
    _usage_log_file
}

# ══════════════════════════════════════════════════════════════
# 통계 초기화
# ══════════════════════════════════════════════════════════════

usage_reset() {
    local stats_file=$(_usage_stats_file)

    if [[ -f "$stats_file" ]]; then
        rm -f "$stats_file"
        echo "Usage stats reset" >&2
    fi
}

# 직접 실행 시
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Usage Meter - LLM 사용량 측정"
    echo ""
    echo "함수:"
    echo "  usage_log <provider> <latency> <len> <code>  사용량 기록"
    echo "  usage_stats                                   전체 통계"
    echo "  usage_today                                   오늘 통계"
    echo "  usage_provider <name>                         Provider별 통계"
    echo "  usage_recent [N]                              최근 N건 로그"
    echo "  usage_reset                                   통계 초기화"
fi
