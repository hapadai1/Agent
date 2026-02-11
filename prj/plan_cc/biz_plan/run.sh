#!/bin/bash
# prj/plan_cc/biz_plan/run.sh
# 신규서비스기획: AI기반 마이디지털정보 오남용 알림 서비스

set -e

export PROJECT_NAME="biz_plan"
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
