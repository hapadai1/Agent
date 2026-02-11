#!/bin/bash
# ChatGPT Chrome 자동화 스크립트
# Chrome에 열린 ChatGPT 탭에 질문을 보내고 답변을 가져옵니다.
# 사전 조건: Chrome > 보기 > 개발자 > "Apple Events의 자바스크립트 허용" 활성화

# ══════════════════════════════════════════════════════════════
# 설정 로드
# ══════════════════════════════════════════════════════════════
CHATGPT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${CHATGPT_SCRIPT_DIR}/chatgpt_config.sh" ]]; then
    source "${CHATGPT_SCRIPT_DIR}/chatgpt_config.sh"
fi

# v2 폴링 엔진 로드
if [[ -f "${CHATGPT_SCRIPT_DIR}/chatgpt_poll_v2.sh" ]]; then
    source "${CHATGPT_SCRIPT_DIR}/chatgpt_poll_v2.sh"
fi

# ══════════════════════════════════════════════════════════════
# v2 에러 체크 헬퍼 함수
# ══════════════════════════════════════════════════════════════
# ChatGPT 응답이 에러 코드인지 확인
# 사용법: if _is_chatgpt_error "$response"; then echo "에러"; fi
_is_chatgpt_error() {
    local response="$1"
    [[ "$response" == "__FAILED__" || \
       "$response" == "__STOPPED__" || \
       "$response" == "__STUCK__" || \
       "$response" == "__COMPLETED_BUT_EMPTY__" || \
       "$response" == __ERROR__:* ]]
}

# 기본값 설정 (config 파일이 없는 경우)
: "${CHATGPT_WAIT_SEC:=90}"
: "${CHATGPT_EXTRA_WAIT:=120}"
: "${CHATGPT_EXTRA_ROUNDS:=3}"
: "${CHATGPT_MAX_RETRIES:=3}"
: "${CHATGPT_MIN_RESPONSE_LEN:=10}"
: "${CHATGPT_RETRY_DELAY:=2}"
: "${CHATGPT_SESSION_DIR:=/tmp/chatgpt_sessions}"
: "${CHATGPT_AUTO_NEW_CHAT:=true}"

# 세션 디렉토리 생성
mkdir -p "$CHATGPT_SESSION_DIR" 2>/dev/null

# ══════════════════════════════════════════════════════════════
# 통합 ChatGPT 호출 함수 (v2)
# ══════════════════════════════════════════════════════════════
# 사용법: chatgpt_call [옵션] "메시지"
#
# 모드 옵션 (--mode=):
#   normal      - 일반 대화 (기본값)
#   research    - 심층 리서치
#   new_chat    - 새 대화 시작 후 질문
#   continue    - 기존 대화에 이어서 질문
#   get_response - 현재 응답만 가져오기 (메시지 불필요)
#
# 추가 옵션:
#   --win=N       - 윈도우 번호 (기본: 1)
#   --tab=N       - 탭 번호 (기본: 1)
#   --timeout=N   - 응답 대기 시간 초 (기본: $CHATGPT_WAIT_SEC)
#   --retry       - 실패 시 재시도 활성화
#   --retry-count=N - 재시도 횟수 (기본: $CHATGPT_MAX_RETRIES)
#   --project=URL - 프로젝트 URL (재시도 시 해당 프로젝트 내 새 대화)
#   --no-wait     - 응답 대기 없이 전송만 (research 모드 시 유용)
#   --section=ID  - 섹션/챕터 ID (변경 시 자동 new chat)
#   --force-new   - 섹션과 관계없이 강제 new chat
#
# 예시:
#   chatgpt_call "안녕하세요"
#   chatgpt_call --mode=research --timeout=300 "AI 트렌드 분석"
#   chatgpt_call --mode=new_chat --retry "질문 내용"
#   chatgpt_call --win=1 --tab=2 --retry --project="https://..." "질문"
#   chatgpt_call --mode=get_response --win=1 --tab=3
# ══════════════════════════════════════════════════════════════
chatgpt_call() {
    # 옵션 파싱
    local mode="normal"
    local win=1
    local tab=1
    local timeout="$CHATGPT_WAIT_SEC"
    local retry=false
    local retry_count="$CHATGPT_MAX_RETRIES"
    local project_url=""
    local no_wait=false
    local section=""
    local force_new=false
    local message=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode=*)
                mode="${1#--mode=}"
                shift
                ;;
            --win=*)
                win="${1#--win=}"
                shift
                ;;
            --tab=*)
                tab="${1#--tab=}"
                shift
                ;;
            --timeout=*)
                timeout="${1#--timeout=}"
                shift
                ;;
            --retry)
                retry=true
                shift
                ;;
            --retry-count=*)
                retry_count="${1#--retry-count=}"
                shift
                ;;
            --project=*)
                project_url="${1#--project=}"
                shift
                ;;
            --no-wait)
                no_wait=true
                shift
                ;;
            --section=*)
                section="${1#--section=}"
                shift
                ;;
            --force-new)
                force_new=true
                shift
                ;;
            -*)
                echo "ERROR: 알 수 없는 옵션: $1" >&2
                return 1
                ;;
            *)
                # 메시지로 처리
                if [[ -z "$message" ]]; then
                    message="$1"
                else
                    message="$message $1"
                fi
                shift
                ;;
        esac
    done

    # 섹션 변경 감지 및 자동 new chat
    local need_new_chat=false
    if [[ "$force_new" == "true" ]]; then
        need_new_chat=true
        echo "🔄 강제 new chat 요청" >&2
    elif [[ -n "$section" && "$CHATGPT_AUTO_NEW_CHAT" == "true" ]]; then
        local session_file="${CHATGPT_SESSION_DIR}/tab_${win}_${tab}_section"
        local prev_section=""
        if [[ -f "$session_file" ]]; then
            prev_section=$(cat "$session_file" 2>/dev/null)
        fi

        if [[ "$prev_section" != "$section" ]]; then
            if [[ -n "$prev_section" ]]; then
                echo "📌 섹션 변경 감지: $prev_section → $section (new chat 시작)" >&2
                need_new_chat=true
            else
                echo "📌 새 섹션 시작: $section" >&2
            fi
            echo "$section" > "$session_file"
        fi
    fi

    # new chat 필요 시 모드 변경
    if [[ "$need_new_chat" == "true" && "$mode" != "new_chat" && "$mode" != "get_response" ]]; then
        mode="new_chat"
    fi

    # 모드별 처리
    case "$mode" in
        get_response)
            # 현재 응답만 가져오기
            _chatgpt_get_last_response "$win" "$tab"
            return $?
            ;;
        new_chat)
            # 새 대화 시작 (프로젝트 URL: 전달값 > 환경변수 > 루트)
            # --mode=new_chat은 명시적 요청이므로 항상 새 채팅 시작 (force=true)
            local new_chat_project_url="${project_url:-${PLAN_PROJECT_URL:-}}"
            if [[ -n "$new_chat_project_url" ]]; then
                _chatgpt_new_chat_in_project "$win" "$tab" "$new_chat_project_url" "force"
            else
                _chatgpt_new_chat "$win" "$tab"
            fi

            # 메시지가 있으면 전송
            if [[ -n "$message" ]]; then
                if [[ "$retry" == "true" ]]; then
                    _chatgpt_send_with_retry "$message" "$win" "$tab" "$timeout" "$retry_count" "$project_url"
                else
                    _chatgpt_send_and_wait "$message" "$win" "$tab" "$timeout"
                fi
            fi
            return $?
            ;;
        research)
            # 심층 리서치
            if [[ -z "$message" ]]; then
                echo "ERROR: research 모드에는 메시지가 필요합니다." >&2
                return 1
            fi

            if [[ "$no_wait" == "true" ]]; then
                _chatgpt_start_research "$message" "$win" "$tab"
            else
                _chatgpt_deep_research "$message" "$win" "$tab" "$timeout"
            fi
            return $?
            ;;
        continue|normal)
            # 일반/이어서 대화
            if [[ -z "$message" ]]; then
                echo "ERROR: 메시지가 필요합니다." >&2
                return 1
            fi

            if [[ "$retry" == "true" ]]; then
                _chatgpt_send_with_retry "$message" "$win" "$tab" "$timeout" "$retry_count" "$project_url"
            else
                _chatgpt_send_and_wait "$message" "$win" "$tab" "$timeout"
            fi
            return $?
            ;;
        *)
            echo "ERROR: 알 수 없는 모드: $mode" >&2
            echo "사용 가능한 모드: normal, research, new_chat, continue, get_response" >&2
            return 1
            ;;
    esac
}

# ══════════════════════════════════════════════════════════════
# 내부 헬퍼 함수들 (_ 접두어)
# ══════════════════════════════════════════════════════════════

# 새 대화 시작 (내부용)
# 주의: 버튼 클릭 방식은 루트로 이동하므로 사용 안 함
# 대신 PLAN_PROJECT_URL이 있으면 그쪽으로 이동
_chatgpt_new_chat() {
    local win="$1"
    local tab="$2"

    # PLAN_PROJECT_URL이 있으면 프로젝트 내 새 채팅 사용
    if [[ -n "${PLAN_PROJECT_URL:-}" ]]; then
        _chatgpt_new_chat_in_project "$win" "$tab" "$PLAN_PROJECT_URL"
        return $?
    fi

    # 프로젝트 URL 없으면 현재 탭 URL에서 프로젝트 감지 시도
    local current_url
    current_url=$(osascript -e "tell application \"$CHATGPT_BROWSER\" to URL of tab $tab of window $win" 2>/dev/null)

    if [[ "$current_url" == *"/g/g-p"* ]] || [[ "$current_url" == *"/project/"* ]]; then
        # 채팅 ID 제거하고 프로젝트 기본 URL 추출
        local base_url
        base_url=$(echo "$current_url" | sed 's|/c/[^/]*$||')
        _chatgpt_new_chat_in_project "$win" "$tab" "$base_url"
        return $?
    fi

    # 그 외: 버튼 클릭 (fallback, 비권장)
    echo "WARNING: 프로젝트 URL 없음. 버튼 클릭 시도 (루트로 이동 가능)" >&2
    osascript <<NEWEOF >/dev/null 2>&1
tell application "$CHATGPT_BROWSER"
    set t to tab $tab of window $win
    execute t javascript "(function(){
        var btn = document.querySelector('[data-testid=create-new-chat-button]');
        if(btn){btn.click(); return 'clicked';}
        return 'not_found';
    })()"
end tell
NEWEOF
    sleep 2
}

# 프로젝트 내 새 대화 시작 (내부용)
# 항상 프로젝트 URL로 이동하여 새 채팅 시작
_chatgpt_new_chat_in_project() {
    local win="$1"
    local tab="$2"
    local project_url="$3"

    # URL 유효성 검사
    if [[ -z "$project_url" ]]; then
        echo "⚠️ 프로젝트 URL이 비어있음" >&2
        return 1
    fi

    echo "🔄 프로젝트에서 새 채팅 시작: $project_url" >&2

    # URL에서 특수문자 이스케이프 (AppleScript 호환)
    local escaped_url
    escaped_url=$(printf '%s' "$project_url" | sed 's/\\/\\\\/g; s/"/\\"/g')

    # 프로젝트 URL로 이동 (새 채팅)
    local nav_result
    nav_result=$(osascript -e "tell application \"$CHATGPT_BROWSER\" to set URL of tab $tab of window $win to \"$escaped_url\"" 2>&1)

    if [[ "$nav_result" == *"error"* ]]; then
        echo "⚠️ URL 이동 실패: $nav_result" >&2
        return 1
    fi

    # 페이지 로드 대기 (더 긴 시간, 더 안정적인 체크)
    echo "  ... 페이지 로드 대기 중" >&2
    sleep 3  # 초기 로딩 시간

    local wait_count=0
    local max_wait=15
    while [ $wait_count -lt $max_wait ]; do
        sleep 1
        ((wait_count++))

        local check_result
        check_result=$(osascript -e "
tell application \"$CHATGPT_BROWSER\"
    set t to tab $tab of window $win
    try
        set jsResult to execute t javascript \"(function(){
            var textarea=document.getElementById('prompt-textarea');
            if(textarea && textarea.offsetParent !== null) return 'ready';
            var prosemirror=document.querySelector('.ProseMirror');
            if(prosemirror && prosemirror.offsetParent !== null) return 'ready';
            var sendBtn=document.querySelector('button[data-testid=send-button]');
            var speechBtn=document.querySelector('button[data-testid=composer-speech-button]');
            if(sendBtn || speechBtn) return 'ready';
            return 'loading';
        })()\"
        return jsResult
    on error
        return \"loading\"
    end try
end tell" 2>/dev/null)

        if [ "$check_result" = "ready" ]; then
            echo "  ✅ 프로젝트 내 새 대화가 준비되었습니다. (${wait_count}초)" >&2
            sleep 1  # 추가 안정화 시간
            return 0
        fi

        if [ $((wait_count % 5)) -eq 0 ]; then
            echo "  ... 페이지 로드 대기 중 (${wait_count}초)" >&2
        fi
    done

    echo "  ⚠️ 페이지 로드 타임아웃 (${max_wait}초) - 계속 진행" >&2
    sleep 2
    return 0
}

# 마지막 응답 가져오기 (내부용)
# encodeURIComponent로 특수문자(한글 따옴표 등) 안전하게 처리
# ChatGPT 오류 메시지 감지 시 이전 article에서 가져오기
_chatgpt_get_last_response() {
    local win="$1"
    local tab="$2"

    local encoded_result
    encoded_result=$(osascript - "$win" "$tab" "$CHATGPT_BROWSER" <<'GETEOF' 2>/dev/null
on run argv
    set win to item 1 of argv as integer
    set tabNum to item 2 of argv as integer
    set browserName to item 3 of argv

    using terms from application "Google Chrome"
        tell application browserName
            with timeout of 30 seconds
            set t to tab tabNum of window win
            set jsResult to execute t javascript "(function(){
                var articles = document.querySelectorAll('article[data-testid^=\"conversation-turn\"]');
            if(articles.length === 0) return encodeURIComponent('no response');

            // 오류 패턴 목록
            var errorPatterns = [
                'Node .* not found in conversation tree',
                '다시 시도',
                'Something went wrong',
                'An error occurred',
                'network error'
            ];

            function isErrorMessage(text) {
                if (!text || text.length < 200) {
                    for (var i = 0; i < errorPatterns.length; i++) {
                        if (text.match(new RegExp(errorPatterns[i], 'i'))) return true;
                    }
                }
                return false;
            }

            function cleanText(text) {
                if (text.indexOf('ChatGPT') === 0) {
                    var idx = text.indexOf(':');
                    if (idx > 0 && idx < 30) text = text.substring(idx + 1);
                }
                text = text.replace(/\\d+m\\s*\\d+s\\s*동안 생각함/g, '');
                text = text.replace(/\\d+분\\s*\\d+초\\s*동안 생각함/g, '');
                text = text.replace('지금 응답 받기', '');
                text = text.replace('ChatGPT', '');
                return text.trim();
            }

            // 마지막 article 시도
            var lastArticle = articles[articles.length - 1];
            var text = cleanText(lastArticle.innerText || '');

            // 오류 메시지면 이전 article 시도
            if (isErrorMessage(text) && articles.length > 1) {
                var prevArticle = articles[articles.length - 2];
                var prevText = cleanText(prevArticle.innerText || '');
                if (prevText.length > text.length) {
                    text = prevText;
                }
            }

            // Deep Think 폴백: article에서 못 가져오면 .markdown 셀렉터 시도
            if (!text || text.length < 50) {
                var markdowns = document.querySelectorAll('.markdown');
                if (markdowns.length > 0) {
                    var mdText = cleanText(markdowns[markdowns.length - 1].innerText || '');
                    if (mdText.length > text.length) {
                        text = mdText;
                    }
                }
            }

            return encodeURIComponent(text);
        })()"
            return jsResult
            end timeout
        end tell
    end using terms from
end run
GETEOF
)
    # URL 디코딩 (Python 사용)
    if [[ -n "$encoded_result" ]]; then
        python3 -c "import urllib.parse; print(urllib.parse.unquote('$encoded_result'))" 2>/dev/null || echo "$encoded_result"
    fi
}

# 심층 리서치 시작만 (내부용)
_chatgpt_start_research() {
    local message="$1"
    local win="$2"
    local tab="$3"

    echo "🔬 심층 리서치 시작 중..." >&2

    # 심층 리서치 페이지로 이동
    osascript <<NAVEOF >/dev/null 2>&1
tell application "$CHATGPT_BROWSER"
    set t to tab $tab of window $win
    execute t javascript "(function(){var link=document.querySelector('[data-testid=deep-research-sidebar-item]');if(link)link.click();else window.location.href='https://chatgpt.com/deep-research';})()"
end tell
NAVEOF

    sleep 3

    # 메시지 전송
    _chatgpt_send_message "$message" "$win" "$tab"

    echo "✅ 리서치 프롬프트 전송 완료" >&2
    echo "   ChatGPT에서 심층 리서치가 진행됩니다." >&2
    return 0
}

# 심층 리서치 + 응답 대기 (내부용)
_chatgpt_deep_research() {
    local message="$1"
    local win="$2"
    local tab="$3"
    local timeout="$4"

    echo "심층 리서치 시작..." >&2

    # 심층 리서치 페이지로 이동
    osascript <<NAVEOF >/dev/null 2>&1
tell application "$CHATGPT_BROWSER"
    set t to tab $tab of window $win
    execute t javascript "(function(){var link=document.querySelector('[data-testid=deep-research-sidebar-item]');if(link)link.click();else window.location.href='https://chatgpt.com/deep-research';})()"
end tell
NAVEOF

    sleep 3

    # 메시지 전송 및 응답 대기
    local result
    result=$(_chatgpt_send_and_wait "$message" "$win" "$tab" "$timeout")

    # 완료 후 일반 모드로 복귀
    echo "심층 리서치 완료. 새 대화로 복귀 중..." >&2
    osascript <<BACKEOF >/dev/null 2>&1
tell application "$CHATGPT_BROWSER"
    set t to tab $tab of window $win
    set URL of t to "https://chatgpt.com/?model=gpt-4o"
end tell
BACKEOF

    sleep 3
    echo "$result"
}

# 메시지 전송만 (응답 대기 없음) - 내부용
_chatgpt_send_message() {
    local message="$1"
    local win="$2"
    local tab="$3"

    # 응답 생성 중인지 확인 - 생성 중이면 완료될 때까지 대기
    local max_wait=60
    local waited=0
    while [ $waited -lt $max_wait ]; do
        local is_generating
        is_generating=$(osascript <<CHECKEOF 2>/dev/null
tell application "$CHATGPT_BROWSER"
    with timeout of 10 seconds
    set t to tab $tab of window $win
    set jsResult to execute t javascript "(function(){
        var stopBtn = document.querySelector('button[data-testid=\"stop-button\"]');
        if(stopBtn) return 'generating';
        var sendBtn = document.querySelector('button[data-testid=\"send-button\"]');
        var speechBtn = document.querySelector('button[data-testid=\"composer-speech-button\"]');
        if(sendBtn || speechBtn) return 'ready';
        return 'generating';
    })()"
    return jsResult
    end timeout
end tell
CHECKEOF
        )

        if [ "$is_generating" = "ready" ]; then
            break
        fi

        echo "  ... 이전 응답 완료 대기 중 (${waited}초)" >&2
        sleep 5
        ((waited += 5))
    done

    if [ $waited -ge $max_wait ]; then
        echo "⚠️ 이전 응답 완료 대기 타임아웃 (${max_wait}초)" >&2
        echo "  🔄 새 채팅 시작 후 재시도..." >&2

        # 새 채팅 시작
        _chatgpt_new_chat "$win" "$tab"
        sleep 2
    fi

    # JavaScript로 직접 텍스트 입력 (URL 인코딩 - UTF-8 한글 지원, 줄바꿈은 </p><p>로 변환 - ProseMirror 형식)
    # 방안 A: 임시 파일 사용 - heredoc 변수 치환 문제 회피
    local temp_msg_file="/tmp/chatgpt_msg_$$.txt"
    echo "$message" | python3 -c "
import urllib.parse, sys
text = sys.stdin.read().rstrip()
# ProseMirror는 각 줄을 <p> 태그로 감싸야 함 (줄바꿈 = </p><p>)
text = text.replace('\\n', '</p><p>')
print(urllib.parse.quote(text))
" > "$temp_msg_file" 2>/dev/null

    local input_result
    input_result=$(osascript - "$win" "$tab" "$temp_msg_file" "$CHATGPT_BROWSER" <<'INPUTEOF' 2>/dev/null
on run argv
    set win to item 1 of argv as integer
    set tabNum to item 2 of argv as integer
    set msgFile to item 3 of argv
    set browserName to item 4 of argv

    -- 임시 파일에서 인코딩된 메시지 읽기
    set encodedMsg to do shell script "cat " & quoted form of msgFile

    using terms from application "Google Chrome"
        tell application browserName
            with timeout of 60 seconds
            set t to tab tabNum of window win
            try
                set jsResult to execute t javascript "(function(){
                    try {
                        var msg = decodeURIComponent('" & encodedMsg & "');
                        var el = document.querySelector('.ProseMirror');
                        if(!el) el = document.getElementById('prompt-textarea');
                        if(!el) return 'no_element';

                        if(el.classList && el.classList.contains('ProseMirror')) {
                            el.innerHTML = '<p>' + msg + '</p>';
                        } else {
                            el.value = msg.split('</p><p>').join(String.fromCharCode(10));
                        }

                        el.dispatchEvent(new Event('input', {bubbles: true}));
                        el.focus();
                        return 'ok';
                    } catch(e) {
                        return 'error:' + e.message;
                    }
                })()"
                return jsResult
            on error errMsg
                return "error:" & errMsg
            end try
            end timeout
        end tell
    end using terms from
end run
INPUTEOF
)

    # 임시 파일 정리
    rm -f "$temp_msg_file" 2>/dev/null

    if [[ "$input_result" == "ok" ]]; then
        echo "  ✅ 텍스트 입력 완료" >&2
    else
        echo "  ⚠️ 텍스트 입력 결과: $input_result" >&2
    fi

    sleep 1

    # 전송 버튼 클릭 (heredoc 방식)
    local send_attempts=0
    local max_send_attempts=5

    while [ $send_attempts -lt $max_send_attempts ]; do
        local send_result
        send_result=$(osascript <<SENDEOF 2>/dev/null
tell application "$CHATGPT_BROWSER"
    with timeout of 30 seconds
    set t to tab $tab of window $win
    try
        set jsResult to execute t javascript "(function(){
            var btn = document.querySelector('button[data-testid=\"send-button\"]');
            if(btn) { btn.click(); return 'sent'; }
            return 'no_button';
        })()"
        return jsResult
    on error
        return "no_button"
    end try
    end timeout
end tell
SENDEOF
        )

        if [ "$send_result" = "sent" ]; then
            echo "  ✅ 전송 완료" >&2
            break
        fi

        ((send_attempts++))
        if [ $send_attempts -lt $max_send_attempts ]; then
            echo "  ... 전송 버튼 대기 중 (시도 ${send_attempts}/${max_send_attempts})" >&2
            sleep 2
        fi
    done

    if [ $send_attempts -ge $max_send_attempts ]; then
        echo "⚠️ 전송 버튼을 찾을 수 없음" >&2
    fi
}

# 메시지 전송 + 응답 대기 (내부용) - v2 폴링 엔진 사용
_chatgpt_send_and_wait() {
    local message="$1"
    local win="$2"
    local tab="$3"
    local wait_sec="$4"

    # 메시지 전송
    _chatgpt_send_message "$message" "$win" "$tab"

    echo "⏳ 질문 전송 완료. 응답 대기 중... (최대 ${wait_sec}초)" >&2

    # POST_SEND_WAIT 대기
    sleep "${CGPT_V2_POST_SEND_WAIT:-1.0}"

    # v2 폴링 엔진 사용
    local response
    response="$(_cgpt_poll_and_extract_v2 "$win" "$tab" "$wait_sec")"
    local exit_code=$?

    echo "$response"
    return $exit_code
}

# 재시도 로직 (내부용)
_chatgpt_send_with_retry() {
    local message="$1"
    local win="$2"
    local tab="$3"
    local wait_sec="$4"
    local max_retries="$5"
    local project_url="$6"
    local min_len="${CHATGPT_MIN_RESPONSE_LEN:-100}"

    local attempt=1
    local response=""

    while [ $attempt -le $max_retries ]; do
        echo "" >&2
        echo "━━━ [$(date '+%H:%M:%S')] 시도 ${attempt}/${max_retries} ━━━" >&2

        response=$(_chatgpt_send_and_wait "$message" "$win" "$tab" "$wait_sec")

        # 응답 검증 (v2 에러 코드 포함)
        if [[ "$response" == "__FAILED__" || "$response" == "__STOPPED__" ]]; then
            echo "⚠️ 스트리밍 실패/중지 감지됨" >&2
        elif [[ "$response" == "__STUCK__" ]]; then
            echo "⚠️ 브라우저 통신 이상 (STUCK) 감지됨" >&2
        elif [[ "$response" == "__COMPLETED_BUT_EMPTY__" ]]; then
            echo "⚠️ 완료됐으나 텍스트 회수 실패" >&2
        elif [[ "$response" == __ERROR__:* ]]; then
            local error_reason="${response#__ERROR__:}"
            echo "⚠️ 오류 감지: $error_reason" >&2
        elif [[ -n "$response" && ${#response} -ge $min_len && "$response" != "no response" && "$response" != "no markdown content" && "$response" != "missing value" ]]; then
            echo "[$(date '+%H:%M:%S')] ✅ 응답 수신 완료 (${#response}자)" >&2
            echo "$response"
            return 0
        else
            echo "⚠️ 응답 실패 또는 너무 짧음 (${#response}자, 최소 ${min_len}자 필요)" >&2
            if [[ -n "$response" ]]; then
                echo "  [DEBUG] 응답 내용: '${response:0:200}'" >&2
            fi
        fi

        if [ $attempt -lt $max_retries ]; then
            echo "🔄 새 채팅 시작 후 재시도..." >&2
            # 프로젝트 URL 결정: 전달된 값 > 환경변수 > 루트
            local retry_project_url="${project_url:-$PLAN_PROJECT_URL}"
            if [[ -n "$retry_project_url" ]]; then
                _chatgpt_new_chat_in_project "$win" "$tab" "$retry_project_url"
            else
                _chatgpt_new_chat "$win" "$tab"
            fi
            sleep "${CHATGPT_RETRY_DELAY:-2}"
        fi

        ((attempt++))
    done

    echo "" >&2
    echo "[$(date '+%H:%M:%S')] ❌ ${max_retries}회 모두 실패" >&2
    echo "$response"
    return 1
}

# ══════════════════════════════════════════════════════════════
# 기존 함수들 (하위 호환성 - chatgpt_call 래퍼)
# ══════════════════════════════════════════════════════════════

# ChatGPT 탭 목록 출력
chatgpt_tabs() {
    osascript - "$CHATGPT_BROWSER" <<'EOF'
on run argv
    set browserName to item 1 of argv

    using terms from application "Google Chrome"
        tell application browserName
            set output to ""
            set winCount to count of windows
            repeat with i from 1 to winCount
                set tabCount to count of tabs of window i
                repeat with j from 1 to tabCount
                    set t to tab j of window i
                    if URL of t contains "chatgpt" then
                        set output to output & "W" & i & ":T" & j & " | " & title of t & " | " & URL of t & linefeed
                    end if
                end repeat
            end repeat
            return output
        end tell
    end using terms from
end run
EOF
}

# ChatGPT 탭 자동 감지 (일반 대화 탭 / 심층 리서치 탭 구분)
# 사용법: chatgpt_detect_tabs [윈도우번호]
# 결과: CHATGPT_ASK_TAB, CHATGPT_RESEARCH_TAB 환경변수 설정
chatgpt_detect_tabs() {
    local win="${1:-1}"

    # 초기화
    export CHATGPT_ASK_TAB=""
    export CHATGPT_RESEARCH_TAB=""

    local result
    result=$(osascript <<DETECTEOF
tell application "$CHATGPT_BROWSER"
    set askTab to ""
    set researchTab to ""
    set tabCount to count of tabs of window $win
    repeat with j from 1 to tabCount
        set t to tab j of window $win
        set tabURL to URL of t
        if tabURL contains "chatgpt" then
            if tabURL contains "deep-research" then
                set researchTab to j as string
            else
                -- 일반 ChatGPT 탭 (첫 번째 발견된 것 사용)
                if askTab is "" then
                    set askTab to j as string
                end if
            end if
        end if
    end repeat
    return askTab & ":" & researchTab
end tell
DETECTEOF
    )

    CHATGPT_ASK_TAB=$(echo "$result" | cut -d: -f1)
    CHATGPT_RESEARCH_TAB=$(echo "$result" | cut -d: -f2)

    export CHATGPT_ASK_TAB
    export CHATGPT_RESEARCH_TAB

    echo "탭 감지 완료: 일반=${CHATGPT_ASK_TAB:-없음}, 심층리서치=${CHATGPT_RESEARCH_TAB:-없음}" >&2
}

# 탭이 심층 리서치 모드인지 확인
# 사용법: is_deep_research_tab [윈도우번호] [탭번호]
is_deep_research_tab() {
    local win="${1:-1}"
    local tab="${2:-1}"
    local url
    url=$(osascript -e "tell application \"$CHATGPT_BROWSER\" to URL of tab $tab of window $win" 2>/dev/null)
    [[ "$url" == *"deep-research"* ]]
}

# ══════════════════════════════════════════════════════════════
# 레거시 함수들 (하위 호환성 유지 - 내부적으로 통합 함수 호출)
# ══════════════════════════════════════════════════════════════

# ChatGPT에 메시지 전송 및 응답 대기 (레거시 래퍼)
# 사용법: chatgpt_ask "질문 내용" [윈도우번호] [탭번호] [대기초]
# 권장: chatgpt_call --mode=normal "질문"
chatgpt_ask() {
    local message="$1"
    local win="${2:-1}"
    local tab="${3:-1}"
    local wait_sec="${4:-$CHATGPT_WAIT_SEC}"

    if [ -z "$message" ]; then
        echo "사용법: chatgpt_ask \"질문 내용\" [윈도우번호] [탭번호] [대기초]"
        return 1
    fi

    _chatgpt_send_and_wait "$message" "$win" "$tab" "$wait_sec"
}

# 심층 리서치 시작만 (응답 대기 없음) - 레거시 래퍼
# 사용법: chatgpt_start_research "질문 내용" [윈도우번호] [탭번호]
# 권장: chatgpt_call --mode=research --no-wait "질문"
chatgpt_start_research() {
    local message="$1"
    local win="${2:-1}"
    local tab="${3:-1}"

    if [ -z "$message" ]; then
        echo "사용법: chatgpt_start_research \"질문 내용\" [윈도우번호] [탭번호]" >&2
        return 1
    fi

    _chatgpt_start_research "$message" "$win" "$tab"
}

# 심층 리서치 질문 전송 (레거시 래퍼)
# 사용법: chatgpt_deep_research "질문 내용" [윈도우번호] [탭번호] [대기초]
# 권장: chatgpt_call --mode=research --timeout=300 "질문"
chatgpt_deep_research() {
    local message="$1"
    local win="${2:-1}"
    local tab="${3:-1}"
    local wait_sec="${4:-300}"

    if [ -z "$message" ]; then
        echo "사용법: chatgpt_deep_research \"질문 내용\" [윈도우번호] [탭번호] [대기초]" >&2
        return 1
    fi

    _chatgpt_deep_research "$message" "$win" "$tab" "$wait_sec"
}

# 새 대화 시작하기 (레거시 래퍼)
# 사용법: chatgpt_new_chat [윈도우번호] [탭번호]
# 권장: chatgpt_call --mode=new_chat --win=N --tab=N
chatgpt_new_chat() {
    local win="${1:-1}"
    local tab="${2:-1}"
    _chatgpt_new_chat "$win" "$tab"
}

# 프로젝트 내 새 대화 시작하기 (레거시 래퍼)
# 사용법: chatgpt_new_chat_in_project [윈도우번호] [탭번호] [프로젝트URL]
# 권장: chatgpt_call --mode=new_chat --project=URL
chatgpt_new_chat_in_project() {
    local win="${1:-1}"
    local tab="${2:-1}"
    local project_url="${3:-}"

    if [[ -z "$project_url" ]]; then
        echo "ERROR: 프로젝트 URL이 필요합니다." >&2
        return 1
    fi

    _chatgpt_new_chat_in_project "$win" "$tab" "$project_url"
}

# 재시도 기능이 포함된 ChatGPT 요청 (레거시 래퍼)
# 사용법: chatgpt_ask_with_retry "질문" [윈도우번호] [탭번호] [대기초] [재시도횟수]
# 권장: chatgpt_call --retry "질문"
chatgpt_ask_with_retry() {
    local message="$1"
    local win="${2:-1}"
    local tab="${3:-1}"
    local wait_sec="${4:-$CHATGPT_WAIT_SEC}"
    local max_retries="${5:-$CHATGPT_MAX_RETRIES}"

    if [ -z "$message" ]; then
        echo "사용법: chatgpt_ask_with_retry \"질문\" [윈도우번호] [탭번호] [대기초] [재시도횟수]" >&2
        return 1
    fi

    _chatgpt_send_with_retry "$message" "$win" "$tab" "$wait_sec" "$max_retries" ""
}

# 프로젝트 내 재시도 기능이 포함된 ChatGPT 요청 (레거시 래퍼)
# 사용법: chatgpt_ask_with_retry_in_project "질문" [윈도우번호] [탭번호] [프로젝트URL] [대기초] [재시도횟수]
# 권장: chatgpt_call --retry --project=URL "질문"
chatgpt_ask_with_retry_in_project() {
    local message="$1"
    local win="${2:-1}"
    local tab="${3:-1}"
    local project_url="${4:-}"
    local wait_sec="${5:-$CHATGPT_WAIT_SEC}"
    local max_retries="${6:-$CHATGPT_MAX_RETRIES}"

    if [ -z "$message" ]; then
        echo "사용법: chatgpt_ask_with_retry_in_project \"질문\" [윈도우] [탭] [프로젝트URL] [대기초] [재시도횟수]" >&2
        return 1
    fi

    _chatgpt_send_with_retry "$message" "$win" "$tab" "$wait_sec" "$max_retries" "$project_url"
}

# 기존 대화에 메시지 전송 (레거시 래퍼)
# 사용법: chatgpt_continue "메시지" [윈도우번호] [탭번호] [대기초]
# 권장: chatgpt_call --mode=continue "질문"
chatgpt_continue() {
    chatgpt_ask "$@"
}

# 마지막 응답만 가져오기 (레거시 래퍼)
# 사용법: chatgpt_last_response [윈도우번호] [탭번호]
# 권장: chatgpt_call --mode=get_response
chatgpt_last_response() {
    local win="${1:-1}"
    local tab="${2:-1}"
    _chatgpt_get_last_response "$win" "$tab"
}

# ══════════════════════════════════════════════════════════════
# 스크립트가 직접 실행된 경우 도움말 출력
# ══════════════════════════════════════════════════════════════
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "ChatGPT Chrome 자동화 스크립트 v2"
    echo ""
    echo "사용법: source chatgpt.sh 로 로드 후 아래 함수 사용"
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "★ 권장: 통합 함수 chatgpt_call() ★"
    echo "══════════════════════════════════════════════════════════════"
    echo ""
    echo "모드 옵션 (--mode=):"
    echo "  normal      - 일반 대화 (기본값)"
    echo "  research    - 심층 리서치"
    echo "  new_chat    - 새 대화 시작 후 질문"
    echo "  continue    - 기존 대화에 이어서 질문"
    echo "  get_response - 현재 응답만 가져오기"
    echo ""
    echo "추가 옵션:"
    echo "  --win=N       - 윈도우 번호 (기본: 1)"
    echo "  --tab=N       - 탭 번호 (기본: 1)"
    echo "  --timeout=N   - 응답 대기 시간(초)"
    echo "  --retry       - 실패 시 재시도"
    echo "  --retry-count=N - 재시도 횟수"
    echo "  --project=URL - 프로젝트 URL"
    echo "  --no-wait     - 응답 대기 없이 전송만"
    echo ""
    echo "예시:"
    echo "  chatgpt_call \"안녕하세요\""
    echo "  chatgpt_call --mode=research --timeout=300 \"AI 트렌드 분석\""
    echo "  chatgpt_call --mode=new_chat --retry \"질문 내용\""
    echo "  chatgpt_call --retry --project=\"https://...\" \"질문\""
    echo "  chatgpt_call --mode=get_response --win=1 --tab=3"
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "레거시 함수 (하위 호환성)"
    echo "══════════════════════════════════════════════════════════════"
    echo "  chatgpt_ask \"질문\"              → chatgpt_call \"질문\""
    echo "  chatgpt_ask_with_retry \"질문\"   → chatgpt_call --retry \"질문\""
    echo "  chatgpt_deep_research \"질문\"    → chatgpt_call --mode=research \"질문\""
    echo "  chatgpt_new_chat                → chatgpt_call --mode=new_chat"
    echo "  chatgpt_last_response           → chatgpt_call --mode=get_response"
    echo ""
    echo "현재 설정:"
    echo "  CHATGPT_WAIT_SEC=${CHATGPT_WAIT_SEC}초 (1회 대기)"
    echo "  CHATGPT_EXTRA_WAIT=${CHATGPT_EXTRA_WAIT}초 × ${CHATGPT_EXTRA_ROUNDS}회 (추가 대기)"
    echo "  CHATGPT_MAX_RETRIES=${CHATGPT_MAX_RETRIES}회 (재시도)"
    echo "  CHATGPT_MIN_RESPONSE_LEN=${CHATGPT_MIN_RESPONSE_LEN}자 (최소 응답)"
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "세션 관리"
    echo "══════════════════════════════════════════════════════════════"
    echo "  chatgpt_session_status       - 현재 세션 상태 확인"
    echo "  chatgpt_session_reset        - 모든 세션 상태 초기화"
    echo "  chatgpt_session_reset_tab N  - 특정 탭 세션만 초기화"
fi

# ══════════════════════════════════════════════════════════════
# 세션 관리 함수들
# ══════════════════════════════════════════════════════════════

# 현재 세션 상태 확인
chatgpt_session_status() {
    local session_dir="${CHATGPT_SESSION_DIR:-/tmp/chatgpt_sessions}"

    echo "━━━ ChatGPT 세션 상태 ━━━"
    echo "세션 디렉토리: $session_dir"
    echo "자동 new chat: $CHATGPT_AUTO_NEW_CHAT"
    echo ""

    if [[ -d "$session_dir" ]]; then
        local files=$(ls -1 "$session_dir"/tab_*_section 2>/dev/null)
        if [[ -n "$files" ]]; then
            echo "탭별 현재 섹션:"
            for f in $files; do
                local basename=$(basename "$f")
                local win_tab=$(echo "$basename" | sed 's/tab_\([0-9]*\)_\([0-9]*\)_section/W\1:T\2/')
                local section=$(cat "$f" 2>/dev/null)
                echo "  $win_tab: $section"
            done
        else
            echo "저장된 세션 없음"
        fi
    else
        echo "세션 디렉토리 없음"
    fi
}

# 모든 세션 상태 초기화
chatgpt_session_reset() {
    local session_dir="${CHATGPT_SESSION_DIR:-/tmp/chatgpt_sessions}"

    if [[ -d "$session_dir" ]]; then
        rm -f "$session_dir"/tab_*_section 2>/dev/null
        echo "✅ 모든 세션 상태가 초기화되었습니다." >&2
    else
        echo "세션 디렉토리가 없습니다." >&2
    fi
}

# 특정 탭 세션 초기화
# 사용법: chatgpt_session_reset_tab [윈도우번호] [탭번호]
chatgpt_session_reset_tab() {
    local win="${1:-1}"
    local tab="${2:-1}"
    local session_dir="${CHATGPT_SESSION_DIR:-/tmp/chatgpt_sessions}"
    local session_file="${session_dir}/tab_${win}_${tab}_section"

    if [[ -f "$session_file" ]]; then
        rm -f "$session_file"
        echo "✅ Tab ${win}:${tab} 세션이 초기화되었습니다." >&2
    else
        echo "Tab ${win}:${tab} 세션 파일이 없습니다." >&2
    fi
}
