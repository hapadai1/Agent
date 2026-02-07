#!/bin/bash
# response/parser.sh - ChatGPT 응답 파싱
# 본문, USER_INPUT_NEEDED, RESEARCH_NEEDED 섹션 분리 및 파일 생성
#
# 사용법:
#   ./parser.sh parse <response_file> <section_id> <project_dir>
#   ./parser.sh parse-stdin <section_id> <project_dir>  # stdin에서 읽기

PARSER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ══════════════════════════════════════════════════════════════
# 메타데이터 파싱
# ══════════════════════════════════════════════════════════════
parse_response() {
    local response="$1"
    local section_id="$2"
    local project_dir="$3"

    local drafts_dir="${project_dir}/drafts"
    local inputs_dir="${project_dir}/inputs"
    local research_prompts_dir="${project_dir}/research/prompts"

    mkdir -p "$drafts_dir" "$inputs_dir" "$research_prompts_dir"

    # 메타데이터 추출
    local metadata=""
    local body=""

    if [[ "$response" == *"===METADATA_START==="* ]]; then
        body=$(echo "$response" | sed -n '1,/===METADATA_START===/p' | sed '$d')
        metadata=$(echo "$response" | sed -n '/===METADATA_START===/,/===METADATA_END===/p')
    else
        body="$response"
    fi

    # 1. 본문 저장
    local draft_file="${drafts_dir}/${section_id}_v1.md"
    echo "$body" > "$draft_file"
    echo "✅ 본문 저장: $draft_file" >&2

    # 2. USER_INPUT_NEEDED 파싱
    if [[ "$metadata" == *"[USER_INPUT_NEEDED]"* ]]; then
        local user_input
        user_input=$(echo "$metadata" | sed -n '/\[USER_INPUT_NEEDED\]/,/\[RESEARCH_NEEDED\]/p' | sed '1d;$d')

        if [[ "$user_input" != *"없음"* && -n "$(echo "$user_input" | tr -d '[:space:]')" ]]; then
            local input_file="${inputs_dir}/${section_id}_questions.md"
            cat > "$input_file" <<EOF
# ${section_id} - 사용자 입력 필요 항목

아래 질문에 답변해주세요.

$user_input

---
답변 완료 후 "입력 완료, ${input_file}" 알려주세요.
EOF
            echo "✏️ 사용자 입력 필요: $input_file" >&2
        fi
    fi

    # 3. RESEARCH_NEEDED 파싱
    if [[ "$metadata" == *"[RESEARCH_NEEDED]"* ]]; then
        local research_section
        research_section=$(echo "$metadata" | sed -n '/\[RESEARCH_NEEDED\]/,/===METADATA_END===/p' | sed '1d;$d')

        if [[ "$research_section" != *"없음"* && -n "$(echo "$research_section" | tr -d '[:space:]')" ]]; then
            # 각 R1, R2... 항목 추출
            local count=1
            echo "$research_section" | grep -E "^- R[0-9]+:" | while read -r line; do
                local topic=$(echo "$line" | sed 's/^- R[0-9]*: //')

                # 다음 줄에서 질문 추출
                local question=""
                question=$(echo "$research_section" | grep -A1 "^- R${count}:" | tail -1 | sed 's/^[[:space:]]*질문: //')

                if [[ -n "$topic" ]]; then
                    local research_file="${research_prompts_dir}/${section_id}_research_${count}.md"
                    cat > "$research_file" <<EOF
# 심층 리서치 요청: ${topic}

## 섹션
${section_id}

## 리서치 주제
${topic}

## 질문
${question:-$topic에 대해 상세히 조사해주세요.}

## 요청사항
- 한국 시장 기준으로 조사
- 최신 데이터 (2023-2024년) 우선
- 출처를 반드시 명시
- 수치/통계 데이터 포함
EOF
                    echo "🔬 리서치 요청 생성: $research_file" >&2
                fi

                ((count++))
            done
        fi
    fi

    echo "" >&2
    echo "━━━ 파싱 완료: ${section_id} ━━━" >&2
}

# ══════════════════════════════════════════════════════════════
# Python 버전 (더 정확한 파싱)
# ══════════════════════════════════════════════════════════════
parse_response_python() {
    local response_file="$1"
    local section_id="$2"
    local project_dir="$3"

    python3 <<PYEOF
import re
import os

response = open('$response_file', 'r', encoding='utf-8').read()
section_id = '$section_id'
project_dir = '$project_dir'

drafts_dir = f"{project_dir}/drafts"
inputs_dir = f"{project_dir}/inputs"
research_dir = f"{project_dir}/research/prompts"

os.makedirs(drafts_dir, exist_ok=True)
os.makedirs(inputs_dir, exist_ok=True)
os.makedirs(research_dir, exist_ok=True)

# 메타데이터 분리
if '===METADATA_START===' in response:
    parts = response.split('===METADATA_START===')
    body = parts[0].strip()
    metadata = '===METADATA_START===' + parts[1] if len(parts) > 1 else ''
else:
    body = response
    metadata = ''

# 1. 본문 저장
draft_file = f"{drafts_dir}/{section_id}_v1.md"
with open(draft_file, 'w', encoding='utf-8') as f:
    f.write(body)
print(f"✅ 본문 저장: {draft_file}")

# 2. USER_INPUT_NEEDED 파싱
user_input_match = re.search(r'\[USER_INPUT_NEEDED\](.*?)(?=\[RESEARCH_NEEDED\]|===METADATA_END===)', metadata, re.DOTALL)
if user_input_match:
    user_input = user_input_match.group(1).strip()
    if user_input and '없음' not in user_input:
        input_file = f"{inputs_dir}/{section_id}_questions.md"
        with open(input_file, 'w', encoding='utf-8') as f:
            f.write(f"# {section_id} - 사용자 입력 필요 항목\n\n")
            f.write("아래 질문에 답변해주세요.\n\n")
            f.write(user_input)
            f.write(f"\n\n---\n답변 완료 후 \"입력 완료, {input_file}\" 알려주세요.\n")
        print(f"✏️ 사용자 입력 필요: {input_file}")

# 3. RESEARCH_NEEDED 파싱
research_match = re.search(r'\[RESEARCH_NEEDED\](.*?)(?====METADATA_END===)', metadata, re.DOTALL)
if research_match:
    research_section = research_match.group(1).strip()
    if research_section and '없음' not in research_section:
        # R1, R2... 패턴 추출
        items = re.findall(r'- R(\d+): (.+?)(?:\n\s*질문: (.+?))?(?=\n- R\d+:|\n*$)', research_section, re.DOTALL)

        for num, topic, question in items:
            topic = topic.strip()
            question = question.strip() if question else f"{topic}에 대해 상세히 조사해주세요."

            research_file = f"{research_dir}/{section_id}_research_{num}.md"
            with open(research_file, 'w', encoding='utf-8') as f:
                f.write(f"# 심층 리서치 요청: {topic}\n\n")
                f.write(f"## 섹션\n{section_id}\n\n")
                f.write(f"## 리서치 주제\n{topic}\n\n")
                f.write(f"## 질문\n{question}\n\n")
                f.write("## 요청사항\n")
                f.write("- 한국 시장 기준으로 조사\n")
                f.write("- 최신 데이터 (2023-2024년) 우선\n")
                f.write("- 출처를 반드시 명시\n")
                f.write("- 수치/통계 데이터 포함\n")
            print(f"🔬 리서치 요청 생성: {research_file}")

print()
print(f"━━━ 파싱 완료: {section_id} ━━━")
PYEOF
}

# ══════════════════════════════════════════════════════════════
# 명령어 처리
# ══════════════════════════════════════════════════════════════
case "${1:-help}" in
    parse)
        response_file="$2"
        section_id="$3"
        project_dir="${4:-.}"

        if [[ ! -f "$response_file" ]]; then
            echo "파일 없음: $response_file" >&2
            exit 1
        fi

        parse_response_python "$response_file" "$section_id" "$project_dir"
        ;;

    parse-stdin)
        section_id="$2"
        project_dir="${3:-.}"

        # stdin을 임시 파일로 저장
        tmp_file=$(mktemp)
        cat > "$tmp_file"

        parse_response_python "$tmp_file" "$section_id" "$project_dir"
        rm -f "$tmp_file"
        ;;

    *)
        echo "Response Parser - ChatGPT 응답 파싱"
        echo ""
        echo "사용법:"
        echo "  $0 parse <response_file> <section_id> <project_dir>"
        echo "  $0 parse-stdin <section_id> <project_dir>"
        echo ""
        echo "예시:"
        echo "  $0 parse response.md s1_2 projects/ai_court_auction"
        echo "  cat response.md | $0 parse-stdin s1_2 projects/ai_court_auction"
        echo ""
        echo "출력 파일:"
        echo "  drafts/{section_id}_v1.md           본문"
        echo "  inputs/{section_id}_questions.md   사용자 입력 필요"
        echo "  research/prompts/{section_id}_research_{n}.md  리서치 요청"
        ;;
esac
