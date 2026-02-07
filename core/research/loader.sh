#!/bin/bash
# research/loader.sh - 리서치 결과 검색 및 로드
# 섹션별 리서치 결과를 찾아서 프롬프트에 주입할 텍스트 반환
#
# 사용법:
#   source loader.sh
#   research_load <research_type> <project_dir>
#
# 예시:
#   research_load market_size /path/to/project
#   → research/responses/market_size_*.{pdf,md} 파일들의 내용을 합쳐서 반환

RESEARCH_LOADER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ══════════════════════════════════════════════════════════════
# 리서치 결과 검색
# ══════════════════════════════════════════════════════════════
# 사용법: research_find <research_type> <project_dir>
# 결과: 찾은 파일 경로들 (줄바꿈으로 구분)
research_find() {
    local research_type="$1"
    local project_dir="$2"
    local response_dir="${project_dir}/research/responses"

    if [[ ! -d "$response_dir" ]]; then
        return 1
    fi

    # 패턴에 맞는 파일 검색 (pdf, md)
    local files=""
    files=$(find "$response_dir" -type f \( -name "${research_type}_*.pdf" -o -name "${research_type}_*.md" \) 2>/dev/null | sort)

    if [[ -z "$files" ]]; then
        return 1
    fi

    echo "$files"
}

# ══════════════════════════════════════════════════════════════
# 리서치 결과 개수 확인
# ══════════════════════════════════════════════════════════════
research_count() {
    local research_type="$1"
    local project_dir="$2"

    local files
    files=$(research_find "$research_type" "$project_dir")

    if [[ -z "$files" ]]; then
        echo "0"
    else
        echo "$files" | wc -l | tr -d ' '
    fi
}

# ══════════════════════════════════════════════════════════════
# 리서치 결과 존재 여부 확인
# ══════════════════════════════════════════════════════════════
research_exists() {
    local research_type="$1"
    local project_dir="$2"

    local count
    count=$(research_count "$research_type" "$project_dir")

    [[ "$count" -gt 0 ]]
}

# ══════════════════════════════════════════════════════════════
# PDF에서 텍스트 추출 (OCR)
# ══════════════════════════════════════════════════════════════
_research_extract_pdf() {
    local pdf_path="$1"
    local text=""

    # 방법 1: pdftotext (poppler)
    if command -v pdftotext &>/dev/null; then
        text=$(pdftotext -layout "$pdf_path" - 2>/dev/null)
        if [[ -n "$text" ]]; then
            echo "$text"
            return 0
        fi
    fi

    # 방법 2: Python + PyMuPDF
    if command -v python3 &>/dev/null; then
        text=$(python3 -c "
import sys
try:
    import fitz  # PyMuPDF
    doc = fitz.open('$pdf_path')
    text = ''
    for page in doc:
        text += page.get_text()
    print(text)
except ImportError:
    pass
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
" 2>/dev/null)
        if [[ -n "$text" ]]; then
            echo "$text"
            return 0
        fi
    fi

    # 방법 3: Python + pdfplumber
    if command -v python3 &>/dev/null; then
        text=$(python3 -c "
import sys
try:
    import pdfplumber
    with pdfplumber.open('$pdf_path') as pdf:
        text = ''
        for page in pdf.pages:
            text += page.extract_text() or ''
    print(text)
except ImportError:
    pass
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
" 2>/dev/null)
        if [[ -n "$text" ]]; then
            echo "$text"
            return 0
        fi
    fi

    # 실패 시 안내 메시지
    echo "[PDF 텍스트 추출 실패: $(basename "$pdf_path")]"
    echo "pdftotext, PyMuPDF, 또는 pdfplumber 설치 필요"
    echo "또는 해당 PDF를 .md 파일로 변환해주세요."
    return 1
}

# ══════════════════════════════════════════════════════════════
# 단일 파일 내용 로드
# ══════════════════════════════════════════════════════════════
_research_load_file() {
    local file_path="$1"
    local filename
    filename=$(basename "$file_path")
    local ext="${filename##*.}"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📄 ${filename}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    case "$ext" in
        md|txt)
            cat "$file_path"
            ;;
        pdf)
            _research_extract_pdf "$file_path"
            ;;
        *)
            echo "[지원하지 않는 파일 형식: $ext]"
            return 1
            ;;
    esac
}

# ══════════════════════════════════════════════════════════════
# 리서치 결과 전체 로드 (프롬프트 주입용)
# ══════════════════════════════════════════════════════════════
# 사용법: research_load <research_type> <project_dir>
# 결과: 모든 리서치 파일 내용을 합친 텍스트
research_load() {
    local research_type="$1"
    local project_dir="$2"

    local files
    files=$(research_find "$research_type" "$project_dir")

    if [[ -z "$files" ]]; then
        echo ""
        return 1
    fi

    local count
    count=$(echo "$files" | wc -l | tr -d ' ')

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  📊 리서치 결과 (${research_type}) - ${count}개 파일"
    echo "╚══════════════════════════════════════════════════════════════╝"

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        _research_load_file "$file"
    done <<< "$files"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 리서치 결과 끝"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ══════════════════════════════════════════════════════════════
# 섹션별 리서치 필요 여부 및 결과 확인
# ══════════════════════════════════════════════════════════════
# 사용법: research_check_section <section_id> <project_dir>
# 결과: JSON 형식의 상태 정보
research_check_section() {
    local section_id="$1"
    local project_dir="$2"
    local sections_yaml="${project_dir}/sections.yaml"

    if [[ ! -f "$sections_yaml" ]]; then
        echo '{"needs_research":false,"has_results":false}'
        return 1
    fi

    # sections.yaml에서 research_type 추출
    local research_type
    research_type=$(python3 -c "
import yaml
with open('$sections_yaml', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)
for section in data.get('sections', []):
    if section.get('id') == '$section_id':
        print(section.get('research_type', ''))
        break
" 2>/dev/null)

    if [[ -z "$research_type" ]]; then
        echo '{"needs_research":false,"has_results":false}'
        return 0
    fi

    local has_results="false"
    if research_exists "$research_type" "$project_dir"; then
        has_results="true"
    fi

    local count
    count=$(research_count "$research_type" "$project_dir")

    echo "{\"needs_research\":true,\"research_type\":\"${research_type}\",\"has_results\":${has_results},\"file_count\":${count}}"
}

# ══════════════════════════════════════════════════════════════
# 프롬프트에 리서치 결과 주입
# ══════════════════════════════════════════════════════════════
# 사용법: research_inject_prompt <prompt_content> <section_id> <project_dir>
# 결과: {research_block} 자리에 리서치 결과가 주입된 프롬프트
research_inject_prompt() {
    local prompt_content="$1"
    local section_id="$2"
    local project_dir="$3"

    # 리서치 타입 확인
    local check_result
    check_result=$(research_check_section "$section_id" "$project_dir")

    local needs_research
    needs_research=$(echo "$check_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('needs_research', False))" 2>/dev/null)

    if [[ "$needs_research" != "True" ]]; then
        # 리서치 불필요 → {research_block} 제거
        echo "${prompt_content//\{research_block\}/}"
        return 0
    fi

    local research_type
    research_type=$(echo "$check_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('research_type', ''))" 2>/dev/null)

    local has_results
    has_results=$(echo "$check_result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('has_results', False))" 2>/dev/null)

    if [[ "$has_results" != "True" ]]; then
        # 리서치 필요하지만 결과 없음 → 안내 메시지
        local notice="[제공 근거]\n리서치 결과가 아직 없습니다. (${research_type})\nresearch/responses/${research_type}_*.{pdf,md} 파일을 추가해주세요."
        echo "${prompt_content//\{research_block\}/$notice}"
        return 0
    fi

    # 리서치 결과 로드
    local research_content
    research_content=$(research_load "$research_type" "$project_dir")

    # {research_block} 치환
    # bash에서 변수에 줄바꿈이 있으면 치환이 복잡하므로 Python 사용
    python3 -c "
import sys
prompt = '''$prompt_content'''
research = '''$research_content'''
result = prompt.replace('{research_block}', '[제공 근거]\n' + research)
print(result)
" 2>/dev/null
}

# ══════════════════════════════════════════════════════════════
# 상태 출력 (디버그용)
# ══════════════════════════════════════════════════════════════
research_status() {
    local project_dir="$1"

    echo "━━━ 리서치 결과 현황 ━━━"
    echo "프로젝트: $project_dir"
    echo ""

    for research_type in market_size competitive customer_needs; do
        local count
        count=$(research_count "$research_type" "$project_dir")

        if [[ "$count" -gt 0 ]]; then
            echo "✅ ${research_type}: ${count}개 파일"
            research_find "$research_type" "$project_dir" | while read -r f; do
                echo "   - $(basename "$f")"
            done
        else
            echo "❌ ${research_type}: 없음"
        fi
    done
}

# ══════════════════════════════════════════════════════════════
# 직접 실행 시 도움말
# ══════════════════════════════════════════════════════════════
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Research Loader - 리서치 결과 검색 및 로드"
    echo ""
    echo "사용법:"
    echo "  source loader.sh"
    echo ""
    echo "함수:"
    echo "  research_find <type> <dir>     파일 검색"
    echo "  research_count <type> <dir>    파일 개수"
    echo "  research_exists <type> <dir>   존재 여부 (exit code)"
    echo "  research_load <type> <dir>     전체 내용 로드"
    echo "  research_check_section <id> <dir>  섹션별 상태 확인"
    echo "  research_inject_prompt <prompt> <id> <dir>  프롬프트 주입"
    echo "  research_status <dir>          현황 출력"
    echo ""
    echo "리서치 타입: market_size, competitive, customer_needs"
fi
