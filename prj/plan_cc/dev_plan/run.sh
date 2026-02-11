#!/bin/bash
# prj/plan_cc/dev_plan/run.sh
# 개발 계획 프로젝트

set -e

export PROJECT_NAME="dev_plan"
export PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
export CORE_DIR="$(cd "$PROJECT_DIR/../../_core" && pwd)"

source "$CORE_DIR/base.sh"

if [[ -f "$CONFIG_DIR/settings.sh" ]]; then
    source "$CONFIG_DIR/settings.sh"
fi

main() {
    init_project || return 1
    log_info "Starting $PROJECT_NAME project"
    log_info "Using CORE_DIR: $CORE_DIR"
    load_core_lib suite_runner || return 1
    "$CORE_DIR/scripts/section_runner.sh" "$@"
}

main "$@"
