#!/bin/bash
# monitor.sh - Agent용 Chrome/GPT 상태 모니터링
#
# 사용법:
#   source core/agent/monitor.sh
#   agent_check_tab 3
#   agent_check_gpt_status 3
#   agent_wait_for_response 3 180

# ══════════════════════════════════════════════════════════════
# Chrome Tab 상태 확인
# ══════════════════════════════════════════════════════════════

# Tab이 ChatGPT인지 확인
agent_check_tab() {
    local tab="${1:-1}"
    local win="${2:-1}"

    local result
    result=$(osascript <<EOF 2>/dev/null
tell application "Google Chrome"
    if (count of windows) >= $win then
        set w to window $win
        if (count of tabs of w) >= $tab then
            set t to tab $tab of w
            set tabUrl to URL of t
            set tabTitle to title of t

            if tabUrl contains "chatgpt.com" then
                return "OK|" & tabTitle & "|" & tabUrl
            else
                return "NOT_CHATGPT|" & tabTitle & "|" & tabUrl
            end if
        else
            return "TAB_NOT_FOUND|tab_count:" & (count of tabs of w)
        end if
    else
        return "WINDOW_NOT_FOUND|window_count:" & (count of windows)
    end if
end tell
EOF
    )

    echo "$result"
}

# ══════════════════════════════════════════════════════════════
# GPT 응답 상태 확인
# ══════════════════════════════════════════════════════════════

# GPT가 응답 중인지 확인 (스트리밍 상태)
agent_check_gpt_status() {
    local tab="${1:-1}"
    local win="${2:-1}"

    local result
    result=$(osascript <<EOF 2>/dev/null
tell application "Google Chrome"
    if (count of windows) >= $win then
        set w to window $win
        if (count of tabs of w) >= $tab then
            set t to tab $tab of w

            -- 스트리밍 중인지 확인 (더 정확한 방법)
            set isStreaming to execute t javascript "
                (function() {
                    // 1. Stop 버튼 있으면 → 생성 중
                    var stopBtn = document.querySelector('button[aria-label=\"Stop generating\"]');
                    if (stopBtn) return 'STREAMING';

                    // 2. 마지막 응답에 완료 아이콘(복사/좋아요/재생성)이 있으면 → 완료
                    var articles = document.querySelectorAll('article[data-testid^=\"conversation-turn\"]');
                    if (articles.length > 0) {
                        var lastArticle = articles[articles.length - 1];
                        // 복사 버튼 또는 좋아요 버튼 확인
                        var copyBtn = lastArticle.querySelector('button[aria-label=\"Copy\"]');
                        var likeBtn = lastArticle.querySelector('button[aria-label=\"Good response\"]');
                        var regenBtn = lastArticle.querySelector('button[aria-label=\"Regenerate\"]');
                        if (copyBtn || likeBtn || regenBtn) return 'COMPLETE';
                    }

                    // 3. 입력창 확인
                    var textarea = document.querySelector('textarea[id=\"prompt-textarea\"]');
                    if (!textarea) textarea = document.querySelector('div[contenteditable=\"true\"]');

                    if (textarea) {
                        if (textarea.disabled) return 'LOADING';
                        return 'READY';
                    }

                    return 'UNKNOWN';
                })();
            "

            return isStreaming
        end if
    end if
    return "ERROR"
end tell
EOF
    )

    echo "$result"
}

# ══════════════════════════════════════════════════════════════
# 입력창에 텍스트가 있는지 확인
# ══════════════════════════════════════════════════════════════

agent_check_input() {
    local tab="${1:-1}"
    local win="${2:-1}"

    local result
    result=$(osascript <<EOF 2>/dev/null
tell application "Google Chrome"
    if (count of windows) >= $win then
        set w to window $win
        if (count of tabs of w) >= $tab then
            set t to tab $tab of w

            set inputText to execute t javascript "
                (function() {
                    var textarea = document.querySelector('textarea[id=\"prompt-textarea\"]');
                    if (!textarea) textarea = document.querySelector('div[contenteditable=\"true\"]');
                    if (textarea) {
                        var text = textarea.value || textarea.innerText || '';
                        return text.length > 0 ? 'HAS_INPUT:' + text.length : 'EMPTY';
                    }
                    return 'NO_INPUT_FIELD';
                })();
            "

            return inputText
        end if
    end if
    return "ERROR"
end tell
EOF
    )

    echo "$result"
}

# ══════════════════════════════════════════════════════════════
# 마지막 응답 가져오기
# ══════════════════════════════════════════════════════════════

agent_get_last_response() {
    local tab="${1:-1}"
    local win="${2:-1}"

    osascript <<EOF 2>/dev/null
tell application "Google Chrome"
    if (count of windows) >= $win then
        set w to window $win
        if (count of tabs of w) >= $tab then
            set t to tab $tab of w

            set responseText to execute t javascript "
                (function() {
                    var articles = document.querySelectorAll('article[data-testid^=\"conversation-turn\"]');
                    if (articles.length === 0) return '';
                    var lastArticle = articles[articles.length - 1];
                    var text = lastArticle.innerText || '';
                    if (text.indexOf('ChatGPT') === 0) {
                        var idx = text.indexOf(':');
                        if (idx > 0 && idx < 30) text = text.substring(idx + 1);
                    }
                    return text.trim();
                })();
            "

            return responseText
        end if
    end if
    return ""
end tell
EOF
}

# ══════════════════════════════════════════════════════════════
# 스트리밍 중인 텍스트 가져오기 (실시간)
# ══════════════════════════════════════════════════════════════

agent_get_streaming_text() {
    local tab="${1:-1}"
    local win="${2:-1}"

    osascript <<EOF 2>/dev/null
tell application "Google Chrome"
    if (count of windows) >= $win then
        set w to window $win
        if (count of tabs of w) >= $tab then
            set t to tab $tab of w

            set streamingText to execute t javascript "
                (function() {
                    // 스트리밍 중인 메시지 찾기 (마지막 assistant 메시지)
                    var articles = document.querySelectorAll('article[data-testid^=\"conversation-turn\"]');
                    if (articles.length === 0) return JSON.stringify({status: 'NO_MESSAGES', text: '', chars: 0});

                    var lastArticle = articles[articles.length - 1];
                    var text = lastArticle.innerText || '';

                    // ChatGPT 프리픽스 제거
                    if (text.indexOf('ChatGPT') === 0) {
                        var idx = text.indexOf(':');
                        if (idx > 0 && idx < 30) text = text.substring(idx + 1);
                    }
                    text = text.trim();

                    // 스트리밍 상태 확인
                    var stopBtn = document.querySelector('button[aria-label=\"Stop generating\"]');
                    var isStreaming = stopBtn ? true : false;

                    return JSON.stringify({
                        status: isStreaming ? 'STREAMING' : 'COMPLETE',
                        text: text,
                        chars: text.length
                    });
                })();
            "

            return streamingText
        end if
    end if
    return "{\"status\": \"ERROR\", \"text\": \"\", \"chars\": 0}"
end tell
EOF
}

# 스트리밍 진행 상황 모니터링 (실시간 출력)
agent_monitor_streaming() {
    local tab="${1:-1}"
    local win="${2:-1}"
    local interval="${3:-3}"
    local max_wait="${4:-300}"

    local elapsed=0
    local last_chars=0

    echo "[Stream] 스트리밍 모니터링 시작 (Tab $tab)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    while [[ $elapsed -lt $max_wait ]]; do
        local result
        result=$(agent_get_streaming_text "$tab" "$win")

        local status chars
        status=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null)
        chars=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('chars',0))" 2>/dev/null)

        local delta=$((chars - last_chars))

        if [[ "$status" == "STREAMING" ]]; then
            printf "\r[Stream] %3ds | %6d chars (+%4d) | 생성 중..." "$elapsed" "$chars" "$delta"
        elif [[ "$status" == "COMPLETE" && $chars -gt 0 ]]; then
            printf "\n[Stream] ✅ 완료! %d chars (%.1fs)\n" "$chars" "$elapsed"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            return 0
        elif [[ "$status" == "NO_MESSAGES" ]]; then
            printf "\r[Stream] %3ds | 대기 중 (메시지 없음)..." "$elapsed"
        fi

        last_chars=$chars
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    echo ""
    echo "[Stream] ⚠️ 타임아웃 (${max_wait}s)"
    return 1
}

# ══════════════════════════════════════════════════════════════
# 응답 대기 (모니터링 루프)
# ══════════════════════════════════════════════════════════════

agent_wait_for_response() {
    local tab="${1:-1}"
    local timeout="${2:-180}"
    local win="${3:-1}"
    local check_interval="${4:-5}"

    local elapsed=0
    local last_gpt_status=""
    local response_started=false

    echo "[Monitor] 응답 대기 시작 (Tab $tab, timeout=${timeout}s)"

    while [[ $elapsed -lt $timeout ]]; do
        local gpt_status
        gpt_status=$(agent_check_gpt_status "$tab" "$win")

        # 상태 변화 로깅
        if [[ "$gpt_status" != "$last_gpt_status" ]]; then
            echo "[Monitor] 상태 변경: $last_gpt_status → $gpt_status (${elapsed}s)"
            last_gpt_status="$gpt_status"
        fi

        case "$gpt_status" in
            "STREAMING")
                response_started=true
                ;;
            "READY")
                if [[ "$response_started" == "true" ]]; then
                    echo "[Monitor] 응답 완료 (${elapsed}s)"
                    return 0
                fi
                ;;
            "LOADING")
                # 로딩 중, 계속 대기
                ;;
            "ERROR"|"UNKNOWN")
                echo "[Monitor] WARNING: 상태 확인 실패 ($gpt_status)"
                ;;
        esac

        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
    done

    echo "[Monitor] 타임아웃 (${timeout}s)"
    return 1
}

# ══════════════════════════════════════════════════════════════
# 종합 상태 체크
# ══════════════════════════════════════════════════════════════

agent_full_status() {
    local tab="${1:-3}"
    local win="${2:-1}"

    echo "━━━ Agent Monitor: Tab $tab Status ━━━"
    echo ""

    # Tab 확인
    local tab_status
    tab_status=$(agent_check_tab "$tab" "$win")
    echo "Tab: $tab_status"

    # GPT 상태
    local gpt_status
    gpt_status=$(agent_check_gpt_status "$tab" "$win")
    echo "GPT: $gpt_status"

    # 입력창 상태
    local input_status
    input_status=$(agent_check_input "$tab" "$win")
    echo "Input: $input_status"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ══════════════════════════════════════════════════════════════
# 자동 진단 - 실패 원인 분석
# ══════════════════════════════════════════════════════════════

agent_diagnose_failure() {
    local tab="${1:-1}"
    local win="${2:-1}"

    echo "[Diagnose] 실패 원인 분석..." >&2

    # 1. Chrome 실행 확인
    if ! pgrep -x "Google Chrome" > /dev/null; then
        echo "CHROME_NOT_RUNNING|Chrome을 실행하세요|false"
        return
    fi

    # 2. Tab 상태 확인
    local tab_status
    tab_status=$(agent_check_tab "$tab" "$win")

    if [[ "$tab_status" == WINDOW_NOT_FOUND* ]]; then
        echo "WINDOW_NOT_FOUND|ChatGPT 윈도우를 열어주세요|false"
        return
    fi

    if [[ "$tab_status" == TAB_NOT_FOUND* ]]; then
        echo "TAB_NOT_FOUND|Tab $tab 없음. 탭을 추가하세요|false"
        return
    fi

    if [[ "$tab_status" == NOT_CHATGPT* ]]; then
        echo "WRONG_TAB|Tab $tab이 ChatGPT가 아님|false"
        return
    fi

    # 3. GPT 상태 확인
    local gpt_status
    gpt_status=$(agent_check_gpt_status "$tab" "$win")

    if [[ "$gpt_status" == "STREAMING" ]]; then
        echo "STILL_STREAMING|응답 생성 중. 추가 대기 필요|true"
        return
    fi

    if [[ "$gpt_status" == "LOADING" ]]; then
        echo "LOADING|로딩 중. 잠시 대기|true"
        return
    fi

    # 4. 응답 존재 확인
    local last_response
    last_response=$(agent_get_last_response "$tab" "$win")

    if [[ -n "$last_response" && ${#last_response} -gt 100 ]]; then
        echo "RESPONSE_EXISTS|응답 있음. 캡처 재시도|true|${#last_response}"
        return
    fi

    # 5. 원인 불명
    echo "UNKNOWN|원인 불명. 수동 확인 필요|false"
}

# ══════════════════════════════════════════════════════════════
# 자동 복구 시도
# ══════════════════════════════════════════════════════════════

agent_auto_recover() {
    local tab="${1:-1}"
    local win="${2:-1}"
    local max_attempts="${3:-3}"

    echo "[Recovery] 자동 복구 시도 (최대 ${max_attempts}회)..." >&2

    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        echo "[Recovery] 시도 $attempt/$max_attempts" >&2

        # 진단
        local diag
        diag=$(agent_diagnose_failure "$tab" "$win")

        local diagnosis action can_retry response_len
        diagnosis=$(echo "$diag" | cut -d'|' -f1)
        action=$(echo "$diag" | cut -d'|' -f2)
        can_retry=$(echo "$diag" | cut -d'|' -f3)
        response_len=$(echo "$diag" | cut -d'|' -f4)

        echo "[Recovery] 진단: $diagnosis" >&2
        echo "[Recovery] 조치: $action" >&2

        case "$diagnosis" in
            STILL_STREAMING|LOADING)
                echo "[Recovery] 대기 중..." >&2
                agent_wait_for_response "$tab" 60 "$win"
                ;;

            RESPONSE_EXISTS)
                echo "[Recovery] 응답 직접 가져오기..." >&2
                local response
                response=$(agent_get_last_response "$tab" "$win")
                if [[ -n "$response" && ${#response} -gt 100 ]]; then
                    echo "[Recovery] ✅ 복구 성공! (${#response} chars)" >&2
                    echo "$response"
                    return 0
                fi
                ;;

            CHROME_NOT_RUNNING|WINDOW_NOT_FOUND|TAB_NOT_FOUND|WRONG_TAB)
                echo "[Recovery] ❌ 자동 복구 불가: $action" >&2
                return 1
                ;;

            *)
                if [[ "$can_retry" != "true" ]]; then
                    echo "[Recovery] ❌ 복구 불가" >&2
                    return 1
                fi
                ;;
        esac

        ((attempt++))
        sleep 2
    done

    echo "[Recovery] ❌ 복구 실패. 수동 개입 필요." >&2
    return 1
}

# ══════════════════════════════════════════════════════════════
# 전체 탭 상태 요약
# ══════════════════════════════════════════════════════════════

agent_status_all() {
    local win="${1:-1}"

    echo "═══════════════════════════════════════"
    echo " ChatGPT 탭 상태 (Window $win)"
    echo "═══════════════════════════════════════"

    for tab in 1 2 3 4 5; do
        local tab_status gpt_status
        tab_status=$(agent_check_tab "$tab" "$win")

        if [[ "$tab_status" == OK* ]]; then
            gpt_status=$(agent_check_gpt_status "$tab" "$win")
            local title
            title=$(echo "$tab_status" | cut -d'|' -f2)
            printf "Tab %d: %-10s | %s\n" "$tab" "$gpt_status" "${title:0:35}"
        else
            local reason
            reason=$(echo "$tab_status" | cut -d'|' -f1)
            printf "Tab %d: %-10s\n" "$tab" "$reason"
        fi
    done

    echo "═══════════════════════════════════════"
}

# ══════════════════════════════════════════════════════════════
# macOS 알림 확인 (Chrome/ChatGPT)
# ══════════════════════════════════════════════════════════════

# 마지막 Chrome 알림 시간 가져오기
agent_get_last_notification() {
    local app="${1:-com.google.chrome}"

    sqlite3 ~/Library/Group\ Containers/group.com.apple.usernoted/db2/db "
        SELECT datetime(r.delivered_date + 978307200, 'unixepoch', 'localtime')
        FROM record r
        JOIN app a ON r.app_id = a.app_id
        WHERE a.identifier = '$app' AND r.delivered_date > 0
        ORDER BY r.delivered_date DESC
        LIMIT 1;
    " 2>/dev/null
}

# 특정 시간 이후 알림이 있는지 확인
agent_check_new_notification() {
    local since_epoch="$1"  # Unix timestamp
    local app="${2:-com.google.chrome}"

    # macOS epoch offset (2001-01-01)
    local mac_epoch=$((since_epoch - 978307200))

    local count
    count=$(sqlite3 ~/Library/Group\ Containers/group.com.apple.usernoted/db2/db "
        SELECT COUNT(*)
        FROM record r
        JOIN app a ON r.app_id = a.app_id
        WHERE a.identifier = '$app' AND r.delivered_date > $mac_epoch;
    " 2>/dev/null)

    if [[ "$count" -gt 0 ]]; then
        echo "NEW_NOTIFICATION"
    else
        echo "NO_NEW"
    fi
}

# 알림 기반 응답 완료 대기
agent_wait_for_notification() {
    local timeout="${1:-300}"
    local app="${2:-com.google.chrome}"

    local start_epoch=$(date +%s)
    local elapsed=0

    echo "[Notify] 알림 대기 시작 (최대 ${timeout}초)"

    while [[ $elapsed -lt $timeout ]]; do
        local result
        result=$(agent_check_new_notification "$start_epoch" "$app")

        if [[ "$result" == "NEW_NOTIFICATION" ]]; then
            echo "[Notify] ✅ 새 알림 감지! (${elapsed}초)"
            return 0
        fi

        sleep 5
        elapsed=$((elapsed + 5))
        printf "\r[Notify] 대기 중... %3ds" "$elapsed"
    done

    echo ""
    echo "[Notify] ⚠️ 타임아웃 (알림 없음)"
    return 1
}

echo "[Monitor] monitor.sh 로드됨"
