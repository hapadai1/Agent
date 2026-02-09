#!/bin/bash
# create-project.sh - 대화형 프로젝트 생성 CLI
# 사용법: ./create-project.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECTS_DIR="${AGENT_ROOT}/projects"

# 라이브러리 로드
source "${SCRIPT_DIR}/lib/prompts.sh"
source "${SCRIPT_DIR}/lib/generator.sh"
source "${SCRIPT_DIR}/lib/validator.sh"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  📦 새 프로젝트 생성${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ✅ 프로젝트 생성 완료!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  경로: ${YELLOW}projects/$1/${NC}"
    echo ""
    echo "  다음 단계:"
    echo "  1. cd projects/$1"
    echo "  2. config/sections.yaml 에서 flow 상세 정의"
    echo "  3. prompts/ 에 프롬프트 템플릿 작성"
    echo ""
}

main() {
    print_header

    # 1. 기본 정보 수집
    echo -e "${YELLOW}[1/3] 기본 정보${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━"

    local project_name
    project_name=$(prompt_project_name)

    # 검증
    if ! validate_project_name "$project_name"; then
        echo -e "${RED}오류: 유효하지 않은 프로젝트 이름${NC}" >&2
        exit 1
    fi

    # 중복 체크
    if [[ -d "${PROJECTS_DIR}/${project_name}" ]]; then
        echo -e "${RED}오류: 이미 존재하는 프로젝트: ${project_name}${NC}" >&2
        exit 1
    fi

    local display_name
    display_name=$(prompt_display_name)

    local description
    description=$(prompt_description)

    echo ""

    # 2. Flow(Step) 정의
    echo -e "${YELLOW}[2/3] Flow(Step) 정의${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━"
    echo "각 Step 이름을 입력하세요. 빈 값 입력 시 완료."
    echo ""

    local sections=()
    local section_num=1

    while true; do
        local step_name
        read -rp "  Step ${section_num} 이름: " step_name

        if [[ -z "$step_name" ]]; then
            break
        fi

        sections+=("$step_name")
        ((section_num++))
    done

    if [[ ${#sections[@]} -eq 0 ]]; then
        echo -e "${YELLOW}경고: Step이 정의되지 않음. 기본 템플릿으로 생성합니다.${NC}"
        sections=("Step 1" "Step 2" "Step 3")
    fi

    echo ""
    echo -e "  등록된 Step: ${GREEN}${#sections[@]}개${NC}"
    echo ""

    # 3. 확인
    echo -e "${YELLOW}[3/3] 확인${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━"
    echo "  프로젝트명: $project_name"
    echo "  표시 이름: $display_name"
    echo "  설명: $description"
    echo "  Step 수: ${#sections[@]}"
    echo ""

    read -rp "이대로 생성하시겠습니까? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "취소되었습니다."
        exit 0
    fi

    # 4. 생성
    echo ""
    echo "프로젝트 생성 중..."

    generate_project "$project_name" "$display_name" "$description" "${sections[@]}"

    print_success "$project_name"
}

main "$@"
