#!/usr/bin/env bash
# chatgpt_poll_v2.sh - ChatGPT 완료 감지 v2 엔진 (설계_2 MVP+)
# 기존 chatgpt.sh에서 source하여 사용

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JS_DIR="$SCRIPT_DIR/js"

# ══════════════════════════════════════════════════════════════
# 파라미터 (환경변수로 오버라이드 가능)
# ══════════════════════════════════════════════════════════════
: "${CGPT_V2_TIMEOUT_SEC:=1500}"           # 기본 타임아웃 (25분)
: "${CGPT_V2_POST_SEND_WAIT:=1.0}"         # send 후 대기
: "${CGPT_V2_POLL_NORMAL:=30}"             # 기본 폴링 간격
: "${CGPT_V2_POLL_CONFIRM:=5}"             # 완료 근접 시 폴링 간격
: "${CGPT_V2_EXTRACT_SCROLL_WAIT_MS:=500}" # scrollIntoView 후 대기 (ms)
: "${CGPT_V2_EMPTY_STREAK_MAX:=50}"        # 연속 빈 응답 최대 (25분/30초=50회)
: "${CGPT_V2_EMPTY_ELAPSED_MAX:=1500}"     # 빈 응답 누적 시간 최대 (25분=1500초)
: "${CGPT_V2_SALVAGE_TRIES:=3}"            # salvage 재시도 횟수

# ══════════════════════════════════════════════════════════════
# 유틸리티
# ══════════════════════════════════════════════════════════════

# JSON 파싱 (python3 사용)
_json_get() {
    local json="$1"
    local key="$2"
    python3 -c "
import json, sys
try:
    obj = json.loads(sys.argv[1])
    keys = sys.argv[2].split('.')
    v = obj
    for k in keys:
        if not k:
            continue
        if isinstance(v, dict) and k in v:
            v = v[k]
        else:
            v = ''
            break
    if v is None:
        v = ''
    if isinstance(v, bool):
        print('true' if v else 'false')
    elif isinstance(v, (dict, list)):
        print(json.dumps(v, ensure_ascii=False))
    else:
        print(str(v))
except Exception:
    print('')
" "$json" "$key" 2>/dev/null || echo ""
}

# AppleScript 문자열 이스케이프
_as_escape() {
    python3 -c "
import sys
s = sys.stdin.read()
s = s.replace('\\\\', '\\\\\\\\').replace('\"', '\\\\\"').replace('\n', ' ')
print(s)
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# JS 실행
# ══════════════════════════════════════════════════════════════

# JS 파일 실행 (base64 인코딩 방식 - 이스케이핑 문제 해결)
# args: win tab js_file [extra_js_prefix]
_cgpt_exec_js() {
    local win="$1"
    local tab="$2"
    local js_file="$3"
    local extra_prefix="${4:-}"

    local js_code
    js_code="$(cat "$JS_DIR/$js_file")"

    local full_js="${extra_prefix}${js_code}"

    # Base64 인코딩으로 이스케이핑 문제 회피
    local b64_js
    b64_js="$(printf '%s' "$full_js" | base64 | tr -d '\n')"

    local out
    out="$(osascript <<EOF 2>/dev/null
tell application "Google Chrome"
    with timeout of 30 seconds
        set t to tab $tab of window $win
        set jsWrapper to "(function(){ var decoded = decodeURIComponent(escape(atob('$b64_js'))); return eval(decoded); })()"
        execute t javascript jsWrapper
    end timeout
end tell
EOF
    )" || true

    # "missing value" 처리
    if [[ "$out" == "missing value" ]]; then
        out=""
    fi

    printf '%s' "$out"
}

# ══════════════════════════════════════════════════════════════
# Poll (상태 감지)
# ══════════════════════════════════════════════════════════════

# Poll 실행
# args: win tab
# 반환: JSON { status, reason, hasText, turnIndex }
_cgpt_poll_v2() {
    local win="$1"
    local tab="$2"
    _cgpt_exec_js "$win" "$tab" "cgpt_poll_v2.js"
}

# ══════════════════════════════════════════════════════════════
# Extract (텍스트 회수)
# ══════════════════════════════════════════════════════════════

# Extract 실행 (2단계: DOM → scrollIntoView)
# args: win tab turnIndex
# 반환: 텍스트 또는 빈 문자열
_cgpt_extract_v2() {
    local win="$1"
    local tab="$2"
    local turn_index="$3"

    # Step 1: DOM 추출
    local result
    result="$(_cgpt_exec_js "$win" "$tab" "cgpt_extract.js" "window.__cgpt_turnIndex=$turn_index; window.__cgpt_scrollMode=false; ")"

    if [[ -z "$result" ]]; then
        echo ""
        return 1
    fi

    local ok step text
    ok="$(_json_get "$result" "ok")"
    step="$(_json_get "$result" "step")"
    text="$(_json_get "$result" "text")"

    # DOM에서 성공
    if [[ "$ok" == "true" ]]; then
        echo "$text"
        return 0
    fi

    # scroll 필요
    if [[ "$step" == "need_scroll_retry" ]]; then
        # 스크롤 대기
        local wait_sec
        wait_sec="$(echo "scale=3; $CGPT_V2_EXTRACT_SCROLL_WAIT_MS / 1000" | bc)"
        sleep "$wait_sec"

        # Step 2: scrollIntoView 후 재시도
        result="$(_cgpt_exec_js "$win" "$tab" "cgpt_extract.js" "window.__cgpt_turnIndex=$turn_index; window.__cgpt_scrollMode=true; ")"

        if [[ -z "$result" ]]; then
            echo ""
            return 1
        fi

        ok="$(_json_get "$result" "ok")"
        text="$(_json_get "$result" "text")"

        if [[ "$ok" == "true" ]]; then
            echo "$text"
            return 0
        fi
    fi

    # 실패
    echo ""
    return 1
}

# ══════════════════════════════════════════════════════════════
# Salvage (타임아웃 시 텍스트 회수 재시도)
# ══════════════════════════════════════════════════════════════

# Salvage 실행
# args: win tab
# 반환: 가장 긴 텍스트 또는 빈 문자열
_cgpt_salvage_v2() {
    local win="$1"
    local tab="$2"

    local backoffs=(0.3 0.7 1.5)
    local best_text=""
    local best_len=0

    for i in $(seq 0 $((CGPT_V2_SALVAGE_TRIES - 1))); do
        # Poll로 turnIndex 가져오기
        local poll_result
        poll_result="$(_cgpt_poll_v2 "$win" "$tab")"

        if [[ -z "$poll_result" ]]; then
            sleep "${backoffs[$i]:-1.5}"
            continue
        fi

        local turn_index
        turn_index="$(_json_get "$poll_result" "turnIndex")"

        if [[ -z "$turn_index" || "$turn_index" == "-1" ]]; then
            sleep "${backoffs[$i]:-1.5}"
            continue
        fi

        # Extract 시도
        local text
        text="$(_cgpt_extract_v2 "$win" "$tab" "$turn_index")"

        if [[ -n "$text" && ${#text} -gt $best_len ]]; then
            best_text="$text"
            best_len=${#text}
        fi

        if [[ $best_len -gt 0 ]]; then
            break
        fi

        sleep "${backoffs[$i]:-1.5}"
    done

    echo "$best_text"
}

# ══════════════════════════════════════════════════════════════
# 메인 폴링 루프 (chatgpt.sh에서 호출)
# ══════════════════════════════════════════════════════════════

# 폴링 및 텍스트 회수
# args: win tab timeout_sec
# 반환: 텍스트 또는 에러 코드 (__STUCK__, __ERROR__:reason, __COMPLETED_BUT_EMPTY__)
_cgpt_poll_and_extract_v2() {
    local win="$1"
    local tab="$2"
    local timeout_sec="${3:-$CGPT_V2_TIMEOUT_SEC}"

    local start_time
    start_time="$(date +%s)"

    local empty_streak=0
    local empty_elapsed=0
    local last_empty_time=0

    local poll_interval="$CGPT_V2_POLL_NORMAL"
    local prev_reason=""
    local poll_count=0

    while true; do
        local now
        now="$(date +%s)"
        local elapsed=$((now - start_time))
        poll_count=$((poll_count + 1))

        # 타임아웃 체크
        if (( elapsed >= timeout_sec )); then
            echo "" >&2
            echo "[$(date '+%H:%M:%S')] 타임아웃 도달. salvage 시도 중..." >&2

            local salvage_text
            salvage_text="$(_cgpt_salvage_v2 "$win" "$tab")"

            if [[ -n "$salvage_text" && ${#salvage_text} -ge 10 ]]; then
                echo "[$(date '+%H:%M:%S')] salvage 성공 (${#salvage_text}자)" >&2
                echo "$salvage_text"
                return 0
            fi

            echo "[$(date '+%H:%M:%S')] salvage 실패" >&2
            echo "__COMPLETED_BUT_EMPTY__"
            return 1
        fi

        # Poll 실행
        local poll_result
        poll_result="$(_cgpt_poll_v2 "$win" "$tab")"

        # 빈 응답 처리
        if [[ -z "$poll_result" ]]; then
            empty_streak=$((empty_streak + 1))

            if [[ $last_empty_time -eq 0 ]]; then
                last_empty_time="$now"
            fi
            empty_elapsed=$((now - last_empty_time))

            echo "  [$(date '+%H:%M:%S')] POLL #${poll_count} (${elapsed}s) ❌ EMPTY (streak=${empty_streak})" >&2

            # STUCK 체크
            if (( empty_streak >= CGPT_V2_EMPTY_STREAK_MAX )) || (( empty_elapsed >= CGPT_V2_EMPTY_ELAPSED_MAX )); then
                echo "" >&2
                echo "[$(date '+%H:%M:%S')] __STUCK__ (연속=${empty_streak}, 누적=${empty_elapsed}s)" >&2
                echo "__STUCK__"
                return 2
            fi

            sleep "$poll_interval"
            continue
        fi

        # 빈 응답 카운터 리셋
        empty_streak=0
        empty_elapsed=0
        last_empty_time=0

        # JSON 파싱
        local status reason has_text turn_index
        status="$(_json_get "$poll_result" "status")"
        reason="$(_json_get "$poll_result" "reason")"
        has_text="$(_json_get "$poll_result" "hasText")"
        turn_index="$(_json_get "$poll_result" "turnIndex")"

        # 항상 상세 로그 출력
        local text_icon="📄"
        [[ "$has_text" == "true" ]] && text_icon="✅" || text_icon="⏳"
        local status_icon="⏳"
        [[ "$status" == "COMPLETED" ]] && status_icon="✅"
        [[ "$status" == "ERROR" ]] && status_icon="❌"
        echo "  [$(date '+%H:%M:%S')] POLL #${poll_count} (${elapsed}s) ${status_icon} status=${status} reason=${reason} text=${text_icon} turn=${turn_index}" >&2
        prev_reason="$reason"

        case "$status" in
            COMPLETED)
                # Extract 실행
                if [[ -n "$turn_index" && "$turn_index" != "-1" ]]; then
                    local text
                    text="$(_cgpt_extract_v2 "$win" "$tab" "$turn_index")"

                    if [[ -n "$text" && ${#text} -ge 10 ]]; then
                        echo "" >&2
                        echo "━━━ [$(date '+%H:%M:%S')] ChatGPT 응답 완료 ━━━" >&2
                        echo "$text"
                        return 0
                    fi

                    # Extract 실패 시 salvage
                    echo "  [$(date '+%H:%M:%S')] Extract 실패, salvage 시도..." >&2
                    local salvage_text
                    salvage_text="$(_cgpt_salvage_v2 "$win" "$tab")"

                    if [[ -n "$salvage_text" && ${#salvage_text} -ge 10 ]]; then
                        echo "" >&2
                        echo "━━━ [$(date '+%H:%M:%S')] ChatGPT 응답 완료 (salvage) ━━━" >&2
                        echo "$salvage_text"
                        return 0
                    fi
                fi

                echo "__COMPLETED_BUT_EMPTY__"
                return 1
                ;;

            ERROR)
                echo "" >&2
                echo "[$(date '+%H:%M:%S')] __ERROR__:$reason" >&2
                echo "__ERROR__:$reason"
                return 1
                ;;

            WAIT)
                # 탭 활성화로 브라우저 스로틀링 방지 (streaming 포함)
                if [[ "$reason" == "streaming" || "$reason" == "unknown_wait" || "$reason" == "no_text_yet" ]]; then
                    osascript -e "tell application \"Google Chrome\" to tell window $win to set active tab index to $tab" 2>/dev/null || true
                fi

                # 동적 폴링 간격
                if [[ "$reason" == "unknown_wait" || "$reason" == "no_text_yet" ]]; then
                    poll_interval=10  # 10초로 단축
                elif [[ "$reason" == "no_actions_yet" ]]; then
                    poll_interval="$CGPT_V2_POLL_CONFIRM"  # 5초
                else
                    poll_interval="$CGPT_V2_POLL_NORMAL"   # 30초
                fi
                ;;

            *)
                # 알 수 없는 상태
                poll_interval="$CGPT_V2_POLL_NORMAL"
                ;;
        esac

        sleep "$poll_interval"
    done
}

# ══════════════════════════════════════════════════════════════
# Export (chatgpt.sh에서 사용)
# ══════════════════════════════════════════════════════════════

# 함수들은 source 시 자동으로 사용 가능
