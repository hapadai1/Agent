#!/bin/bash
# workflow.sh - 사업계획서 작성 워크플로우
# 이 파일은 프로젝트별로 실행되며, PROJECT_DIR 변수가 설정되어 있어야 함
# 필수 모듈: sections.sh, prompts.sh, scoring.sh, notify.sh (run.sh에서 로드)

# ══════════════════════════════════════════════════════════════
# 프롬프트 모드 설정 (고정 / 자동개선)
# ══════════════════════════════════════════════════════════════
# PROMPT_MODE 환경변수로 제어:
#   - "fixed"  : 기존 prompts.sh 사용 (기본값)
#   - "auto"   : 자동개선 시스템 사용 (YAML 기반 + defect 추적)
#   - "both"   : 양쪽 동시 실행 (테스트용, 비교 목적)
PROMPT_MODE="${PROMPT_MODE:-fixed}"

# 자동개선 모듈 로드 (auto 또는 both 모드일 때)
if [[ "$PROMPT_MODE" == "auto" || "$PROMPT_MODE" == "both" ]]; then
    SCRIPT_DIR_WF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LIB_DIR_WF="$(dirname "$SCRIPT_DIR_WF")"
    [[ -f "${LIB_DIR_WF}/prompt/prompt_loader.sh" ]] && source "${LIB_DIR_WF}/prompt/prompt_loader.sh"
    [[ -f "${LIB_DIR_WF}/eval/defect_tracker.sh" ]] && source "${LIB_DIR_WF}/eval/defect_tracker.sh"
    [[ -f "${LIB_DIR_WF}/eval/trigger_checker.sh" ]] && source "${LIB_DIR_WF}/eval/trigger_checker.sh"
    [[ -f "${LIB_DIR_WF}/prompt/prompt_critic.sh" ]] && source "${LIB_DIR_WF}/prompt/prompt_critic.sh"
    echo "📊 프롬프트 자동개선 모드 활성화 (mode: $PROMPT_MODE)" >&2
fi

# ══════════════════════════════════════════════════════════════
# USER_INPUT_NEEDED 파싱 및 저장
# ══════════════════════════════════════════════════════════════

# 응답에서 USER_INPUT_NEEDED 부분 추출
extract_user_input_needed() {
    local content="$1"
    echo "$content" | awk '/^USER_INPUT_NEEDED:/,0'
}

# 응답에서 USER_INPUT_NEEDED 부분 제거 (본문만 반환)
strip_user_input_needed() {
    local content="$1"
    echo "$content" | awk '/^USER_INPUT_NEEDED:/{exit}1'
}

# USER_INPUT_NEEDED를 별도 파일로 저장
save_user_input_questions() {
    local section_id="$1"
    local content="$2"

    local questions
    questions=$(extract_user_input_needed "$content")

    # "없음"이 아닌 경우만 저장
    if [[ -n "$questions" && ! "$questions" =~ "없음" ]]; then
        local input_dir="${PROJECT_DIR}/inputs"
        mkdir -p "$input_dir"

        local input_file="${input_dir}/section_${section_id}_questions.md"
        echo "$questions" > "$input_file"
        echo "사용자 입력 질문 저장됨: $input_file" >&2
    fi
}

# ══════════════════════════════════════════════════════════════
# 워크플로우 메인 로직
# ══════════════════════════════════════════════════════════════

# 일반 질문용 탭 가져오기
get_ask_tab() {
    local win=$(state_get ".chatgpt.window")
    local tab="${CHATGPT_ASK_TAB:-}"
    if [[ -z "$tab" ]]; then
        tab=$(state_get ".chatgpt.tab")
    fi
    echo "$tab"
}

# 섹션 작성 요청
do_draft() {
    local section_id="$1"

    local name
    name=$(get_section_name "$section_id")
    local pages
    pages=$(get_section_pages "$section_id")

    echo ""
    echo "######시작######"
    echo "섹션: $name"
    echo "분량: ${pages}페이지"
    echo "######요청######"

    # 프롬프트 생성
    local prompt
    prompt=$(prompt_draft "$section_id" "$pages")

    echo "$prompt"
    echo ""

    # ChatGPT에 요청 (일반 질문 탭 사용)
    local win tab
    win=$(state_get ".chatgpt.window")
    tab=$(get_ask_tab)
    local timeout
    timeout=$(state_get ".chatgpt.default_timeout")

    local response
    response=$(chatgpt_call --tab="$tab" --timeout="$timeout" --retry "$prompt")

    # 결과 저장
    local file
    file=$(state_get ".sections.\"$section_id\".file")
    local iteration
    iteration=$(state_get ".sections.\"$section_id\".iteration")
    ((iteration++))

    local draft_path="${PROJECT_DIR}/drafts/${file%.md}_v${iteration}.md"

    # USER_INPUT_NEEDED 분리 저장
    save_user_input_questions "$section_id" "$response"

    # 본문만 draft에 저장 (USER_INPUT_NEEDED 제거)
    local clean_response
    clean_response=$(strip_user_input_needed "$response")
    echo "$clean_response" > "$draft_path"

    # 상태 업데이트
    state_set ".sections.\"$section_id\".iteration" "$iteration"
    state_set ".sections.\"$section_id\".state" "drafted"

    echo "저장됨: $draft_path"
}

# 섹션 검증 요청
do_verify() {
    local section_id="$1"

    local name
    name=$(get_section_name "$section_id")

    echo "" >&2
    echo "######검증######" >&2
    echo "섹션: $name" >&2

    # 최신 드래프트 읽기
    local file
    file=$(state_get ".sections.\"$section_id\".file")
    local iteration
    iteration=$(state_get ".sections.\"$section_id\".iteration")
    local draft_path="${PROJECT_DIR}/drafts/${file%.md}_v${iteration}.md"

    if [[ ! -f "$draft_path" ]]; then
        echo "오류: 드래프트 파일을 찾을 수 없습니다 - $draft_path"
        return 1
    fi

    local draft_content
    draft_content=$(cat "$draft_path")

    # 출처/용어주석/USER_INPUT_NEEDED 섹션 제거 (검증 시 불필요, 토큰 절약)
    draft_content=$(echo "$draft_content" | awk '/^출처|^용어 주석|^USER_INPUT_NEEDED:/{exit}1')

    # 검증 프롬프트 생성
    local prompt
    prompt=$(prompt_verify "$section_id" "$draft_content")

    # ChatGPT에 요청 (일반 질문 탭 사용)
    local win tab
    win=$(state_get ".chatgpt.window")
    tab=$(get_ask_tab)
    local timeout
    timeout=$(state_get ".chatgpt.default_timeout")

    local response
    response=$(chatgpt_call --tab="$tab" --timeout="$timeout" --retry "$prompt")

    # 점수 파싱
    local score
    score=$(parse_score "$response")

    echo "점수: ${score}/100" >&2

    # 상태 업데이트
    state_set ".sections.\"$section_id\".score" "$score"
    state_set ".sections.\"$section_id\".state" "verified"

    # 점수 기록
    log_score "$section_id" "$iteration" "$score" "$(parse_breakdown "$response")"

    # 피드백 저장
    echo "$response" > "${PROJECT_DIR}/scores/section_${section_id}_feedback_v${iteration}.txt"

    echo "$score"
}

# 섹션 재작성 요청
do_rewrite() {
    local section_id="$1"

    local name
    name=$(get_section_name "$section_id")

    echo ""
    echo "######재작성######"
    echo "섹션: $name"

    # 최신 드래프트와 피드백 읽기
    local file
    file=$(state_get ".sections.\"$section_id\".file")
    local iteration
    iteration=$(state_get ".sections.\"$section_id\".iteration")

    local draft_path="${PROJECT_DIR}/drafts/${file%.md}_v${iteration}.md"
    local feedback_path="${PROJECT_DIR}/scores/section_${section_id}_feedback_v${iteration}.txt"

    local draft_content
    draft_content=$(cat "$draft_path")
    local feedback
    feedback=$(cat "$feedback_path" 2>/dev/null || echo "")

    # 재작성 프롬프트 생성
    local prompt
    prompt=$(prompt_rewrite "$section_id" "$draft_content" "$feedback")

    # ChatGPT에 요청 (일반 질문 탭 사용)
    local win tab
    win=$(state_get ".chatgpt.window")
    tab=$(get_ask_tab)
    local timeout
    timeout=$(state_get ".chatgpt.default_timeout")

    local response
    response=$(chatgpt_call --tab="$tab" --timeout="$timeout" --retry "$prompt")

    # 새 버전으로 저장
    ((iteration++))
    local new_draft_path="${PROJECT_DIR}/drafts/${file%.md}_v${iteration}.md"
    echo "$response" > "$new_draft_path"

    # 상태 업데이트
    state_set ".sections.\"$section_id\".iteration" "$iteration"
    state_set ".sections.\"$section_id\".state" "improved"

    echo "저장됨: $new_draft_path"
}

# 사람 입력이 필요한 섹션 처리 (예시로 초안 작성 후 다음 진행)
do_human_input_section() {
    local section_id="$1"

    local name
    name=$(get_section_name "$section_id")

    echo ""
    echo "######사용자 입력 섹션######"
    echo "섹션: $name"

    # ChatGPT에 질문+예시 요청
    local prompt
    prompt=$(prompt_draft_with_examples "$section_id")

    local win tab
    win=$(state_get ".chatgpt.window")
    tab=$(get_ask_tab)
    local timeout
    timeout=$(state_get ".chatgpt.default_timeout")

    local response
    response=$(chatgpt_call --tab="$tab" --timeout="$timeout" --retry "$prompt")

    # USER_INPUT_NEEDED 분리 저장
    save_user_input_questions "$section_id" "$response"

    # 본문만 draft에 저장 (예시 데이터로 작성된 초안)
    local clean_response
    clean_response=$(strip_user_input_needed "$response")

    local file
    file=$(state_get ".sections.\"$section_id\".file")
    local iteration
    iteration=$(state_get ".sections.\"$section_id\".iteration")
    ((iteration++))
    local draft_path="${PROJECT_DIR}/drafts/${file%.md}_v${iteration}.md"
    echo "$clean_response" > "$draft_path"

    # 상태 업데이트
    state_set ".sections.\"$section_id\".iteration" "$iteration"
    state_set ".sections.\"$section_id\".state" "human_input_needed"

    echo ""
    echo "✏️ [입력 필요] $name"
    echo ""
    echo "예시 데이터로 초안이 작성되었습니다."
    echo "질문 파일: inputs/section_${section_id}_questions.md"
    echo ""
    echo "답변 작성 후 알려주세요."
    echo "예시: \"입력 완료, inputs/${section_id}_input.md\""
    echo ""
}

# 사용자 입력 완료 후 재작성
do_human_input_rewrite() {
    local section_id="$1"
    local input_file="$2"

    local name
    name=$(get_section_name "$section_id")

    echo ""
    echo "######사용자 입력 반영######"
    echo "섹션: $name"
    echo "입력 파일: $input_file"

    # 사용자 입력 파일 읽기
    local user_input
    user_input=$(cat "${PROJECT_DIR}/${input_file}" 2>/dev/null || echo "")

    if [[ -z "$user_input" ]]; then
        echo "⚠️ 입력 파일이 비어있거나 존재하지 않습니다: $input_file"
        return 1
    fi

    # 최신 드래프트 읽기
    local file
    file=$(state_get ".sections.\"$section_id\".file")
    local iteration
    iteration=$(state_get ".sections.\"$section_id\".iteration")
    local draft_path="${PROJECT_DIR}/drafts/${file%.md}_v${iteration}.md"
    local draft_content
    draft_content=$(cat "$draft_path" 2>/dev/null || echo "")

    # 사용자 입력 반영하여 재작성 프롬프트
    local prompt
    prompt=$(prompt_rewrite_with_user_input "$section_id" "$draft_content" "$user_input")

    local win tab
    win=$(state_get ".chatgpt.window")
    tab=$(get_ask_tab)
    local timeout
    timeout=$(state_get ".chatgpt.default_timeout")

    local response
    response=$(chatgpt_call --tab="$tab" --timeout="$timeout" --retry "$prompt")

    # 새 버전으로 저장
    ((iteration++))
    local new_draft_path="${PROJECT_DIR}/drafts/${file%.md}_v${iteration}.md"
    echo "$response" > "$new_draft_path"

    # 상태 업데이트
    state_set ".sections.\"$section_id\".iteration" "$iteration"
    state_set ".sections.\"$section_id\".state" "drafted"

    # human_input_files에 경로 저장
    state_set ".human_input_files.\"$section_id\"" "\"$input_file\""

    echo "저장됨: $new_draft_path"
}

# ══════════════════════════════════════════════════════════════
# 비동기 리서치 관리
# ══════════════════════════════════════════════════════════════

# 백그라운드 리서치 PID 파일
RESEARCH_PID_FILE="${PROJECT_DIR}/.research_pid"
RESEARCH_SECTION_FILE="${PROJECT_DIR}/.research_section"

# 심층 리서치 시작 (백그라운드 아님, 프롬프트 전송만)
# 사용법: start_research_background section_id
start_research_background() {
    local section_id="$1"

    # do_research()로 위임 (이제 동일한 동작)
    do_research "$section_id"
}

# 리서치 진행 중인지 확인
is_research_running() {
    if [[ -f "$RESEARCH_PID_FILE" ]]; then
        local pid
        pid=$(cat "$RESEARCH_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0  # 실행 중
        else
            # 프로세스 종료됨 - 파일 정리
            rm -f "$RESEARCH_PID_FILE" "$RESEARCH_SECTION_FILE"
        fi
    fi
    return 1  # 실행 중 아님
}

# 현재 리서치 중인 섹션 ID 반환
get_researching_section() {
    if [[ -f "$RESEARCH_SECTION_FILE" ]]; then
        cat "$RESEARCH_SECTION_FILE"
    fi
}

# 리서치 완료 대기
wait_for_research() {
    local section_id="$1"

    echo "리서치 완료 대기 중: $(get_section_name "$section_id")"

    while true; do
        local state
        state=$(state_get ".sections.\"$section_id\".state")

        if [[ "$state" == "research_done" ]]; then
            echo "리서치 완료 확인됨"
            return 0
        elif [[ "$state" != "researching" ]]; then
            echo "예상치 못한 상태: $state"
            return 1
        fi

        sleep 5
        echo "  ... 대기 중"
    done
}

# 리서치 시작 (응답 대기 없음, 사용자가 PDF로 수동 저장)
do_research() {
    local section_id="$1"

    local research_type
    research_type=$(get_research_type "$section_id")

    if [[ -z "$research_type" ]]; then
        return 0
    fi

    local name
    name=$(get_section_name "$section_id")

    echo ""
    echo "######리서치 시작######"
    echo "섹션: $name"
    echo "유형: $research_type"

    local prompt
    prompt=$(prompt_research "$research_type")

    local win
    win=$(state_get ".chatgpt.window")

    local research_tab="${CHATGPT_RESEARCH_TAB:-}"
    if [[ -z "$research_tab" ]]; then
        research_tab=$(state_get ".chatgpt.tab")
        echo "⚠️  심층리서치 전용 탭 미감지, 기본 탭 사용" >&2
    else
        echo "심층리서치 탭: Window $win, Tab $research_tab" >&2
    fi

    # 리서치 시작만 (응답 대기 없음)
    chatgpt_start_research "$prompt" "$win" "$research_tab"

    # 상태를 researching으로 변경 (사용자가 완료 알릴 때까지)
    state_set ".sections.\"$section_id\".state" "researching"

    echo ""
    echo "🔬 [리서치 진행 중] $name"
    echo ""
    echo "ChatGPT 심층 리서치가 시작되었습니다."
    echo "완료 후 PDF로 저장하고 알려주세요."
    echo ""
    echo "예시: \"리서치 완료, research/${research_type}.pdf\""
    echo ""
}

# 섹션 처리 메인 루프
process_section() {
    local section_id="$1"

    local name
    name=$(get_section_name "$section_id")
    local needs_human
    needs_human=$(state_get ".sections.\"$section_id\".needs_human")
    local needs_research
    needs_research=$(state_get ".sections.\"$section_id\".needs_research")
    local target_score
    target_score=$(state_get ".target_score")
    local max_iter
    max_iter=$(state_get ".max_iterations_per_section")

    echo ""
    echo "════════════════════════════════════════"
    echo "섹션 처리: $name"
    echo "════════════════════════════════════════"

    # 리서치 필요 시 먼저 실행
    if [[ "$needs_research" == "true" ]]; then
        local research_type
        research_type=$(get_research_type "$section_id")
        local completed
        completed=$(state_get ".research_completed")

        if [[ ! "$completed" == *"$research_type"* ]]; then
            do_research "$section_id"
        fi
    fi

    # 사람 입력 필요 섹션
    if [[ "$needs_human" == "true" ]]; then
        do_human_input_section "$section_id"
    else
        # 자동 초안 작성
        do_draft "$section_id"
    fi

    # 검증-개선 루프
    local iteration=1
    while [[ $iteration -le $max_iter ]]; do
        local score
        score=$(do_verify "$section_id")

        local stop_reason
        stop_reason=$(should_stop_iterating "$section_id" "$score" "$iteration" "$target_score" "$max_iter")

        case "$stop_reason" in
            "TARGET_REACHED")
                echo "목표 점수 달성: ${score}점"
                state_set ".sections.\"$section_id\".state" "completed"
                break
                ;;
            "DIMINISHING_RETURNS")
                echo "수확 체감으로 중단: ${score}점"
                state_set ".sections.\"$section_id\".state" "completed"
                break
                ;;
            "MAX_ITERATIONS")
                echo "최대 반복 횟수 도달: ${score}점"
                state_set ".sections.\"$section_id\".state" "completed"
                break
                ;;
            "SCORE_REGRESSION")
                echo "점수 하락 - 이전 버전 유지"
                # 이전 버전으로 복원 로직
                state_set ".sections.\"$section_id\".state" "completed"
                break
                ;;
            "CONTINUE")
                do_rewrite "$section_id"
                ((iteration++))
                ;;
        esac
    done
}

# 전체 워크플로우 실행 (비동기 버전)
run_workflow() {
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║     사업계획서 작성 워크플로우 시작          ║"
    echo "║     (비동기 리서치 모드)                     ║"
    echo "╚══════════════════════════════════════════════╝"

    local topic
    topic=$(state_get ".topic")
    echo "주제: $topic"
    echo ""

    # 미완료 섹션 큐 생성
    local pending_sections=()
    for section_id in "${SECTION_ORDER[@]}"; do
        local state
        state=$(state_get ".sections.\"$section_id\".state")
        if [[ "$state" != "completed" ]]; then
            pending_sections+=("$section_id")
        fi
    done

    echo "처리할 섹션: ${#pending_sections[@]}개"
    echo ""

    # 메인 루프: 모든 섹션이 완료될 때까지
    while [[ ${#pending_sections[@]} -gt 0 ]]; do
        local processed_any=false

        for i in "${!pending_sections[@]}"; do
            local section_id="${pending_sections[$i]}"
            local state
            state=$(state_get ".sections.\"$section_id\".state")
            local needs_research
            needs_research=$(state_get ".sections.\"$section_id\".needs_research")
            local name
            name=$(get_section_name "$section_id")

            case "$state" in
                "completed")
                    # 완료됨 - 큐에서 제거
                    unset 'pending_sections[$i]'
                    pending_sections=("${pending_sections[@]}")
                    echo "✅ 완료됨: $name"
                    processed_any=true
                    break
                    ;;

                "researching")
                    # 리서치 진행 중 - 건너뛰기
                    echo "⏳ 리서치 중: $name (건너뛰기)"
                    continue
                    ;;

                "research_done")
                    # 리서치 완료 - 작성 진행
                    echo ""
                    echo "════════════════════════════════════════"
                    echo "섹션 처리: $name (리서치 완료)"
                    echo "════════════════════════════════════════"
                    process_section_draft_only "$section_id"
                    processed_any=true
                    break
                    ;;

                "pending")
                    if [[ "$needs_research" == "true" ]]; then
                        # 리서치 필요 + 리서치 탭 사용 가능하면 백그라운드 시작
                        if ! is_research_running; then
                            start_research_background "$section_id"
                            processed_any=true
                            # 바로 다음 섹션으로 (리서치는 백그라운드)
                            continue
                        else
                            echo "⏳ 리서치 탭 사용 중 - 대기: $name"
                            continue
                        fi
                    else
                        # 리서치 불필요 - 바로 작성
                        echo ""
                        echo "════════════════════════════════════════"
                        echo "섹션 처리: $name"
                        echo "════════════════════════════════════════"
                        process_section "$section_id"
                        processed_any=true
                        break
                    fi
                    ;;

                *)
                    # 기타 상태 (drafted, verified 등) - 계속 처리
                    echo ""
                    echo "════════════════════════════════════════"
                    echo "섹션 처리: $name (상태: $state)"
                    echo "════════════════════════════════════════"
                    process_section "$section_id"
                    processed_any=true
                    break
                    ;;
            esac
        done

        # 아무것도 처리 못했으면 리서치 완료 대기
        if [[ "$processed_any" == false ]]; then
            if is_research_running; then
                local researching_section
                researching_section=$(get_researching_section)
                echo "모든 일반 섹션 완료. 리서치 완료 대기: $(get_section_name "$researching_section")"
                wait_for_research "$researching_section"
            else
                # 더 이상 처리할 게 없음
                break
            fi
        fi

        # 글로벌 상태 업데이트
        state_set ".global_state" "DRAFTING"
    done

    # 전체 점수 계산
    local overall
    overall=$(calculate_overall_score)
    state_set ".overall_score" "$overall"

    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║            워크플로우 완료                   ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""

    print_section_scores
    echo ""
    echo "종합 점수: ${overall}점"

    # 알림
    notify_user "사업계획서 작성 완료" "종합 점수: ${overall}점"
}

# 리서치 완료된 섹션 작성만 처리 (리서치 건너뛰기)
process_section_draft_only() {
    local section_id="$1"

    local name
    name=$(get_section_name "$section_id")
    local needs_human
    needs_human=$(state_get ".sections.\"$section_id\".needs_human")
    local target_score
    target_score=$(state_get ".target_score")
    local max_iter
    max_iter=$(state_get ".max_iterations_per_section")

    # 사람 입력 필요 섹션
    if [[ "$needs_human" == "true" ]]; then
        do_human_input_section "$section_id"
    else
        # 자동 초안 작성
        do_draft "$section_id"
    fi

    # 검증-개선 루프
    local iteration=1
    while [[ $iteration -le $max_iter ]]; do
        local score
        score=$(do_verify "$section_id")

        local stop_reason
        stop_reason=$(should_stop_iterating "$section_id" "$score" "$iteration" "$target_score" "$max_iter")

        case "$stop_reason" in
            "TARGET_REACHED")
                echo "목표 점수 달성: ${score}점"
                state_set ".sections.\"$section_id\".state" "completed"
                break
                ;;
            "DIMINISHING_RETURNS")
                echo "수확 체감으로 중단: ${score}점"
                state_set ".sections.\"$section_id\".state" "completed"
                break
                ;;
            "MAX_ITERATIONS")
                echo "최대 반복 횟수 도달: ${score}점"
                state_set ".sections.\"$section_id\".state" "completed"
                break
                ;;
            "SCORE_REGRESSION")
                echo "점수 하락 - 이전 버전 유지"
                state_set ".sections.\"$section_id\".state" "completed"
                break
                ;;
            "CONTINUE")
                do_rewrite "$section_id"
                ((iteration++))
                ;;
        esac
    done
}

# 특정 섹션부터 재개
resume_from_section() {
    local start_section="$1"
    local started=false

    for section_id in "${SECTION_ORDER[@]}"; do
        if [[ "$section_id" == "$start_section" ]]; then
            started=true
        fi

        if [[ "$started" == true ]]; then
            process_section "$section_id"
        fi
    done
}
