#!/usr/bin/env bash
# Generic audit logger for Copilot hook events.
# Usage (from .github/hooks/factory.json): bash log.sh <eventName>   (payload JSON on stdin)
# Never blocks the agent: always exits 0 and prints nothing.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$here/common.sh"

event="${1:-unknown}"
payload="$(cat)"
factory_context
factory_log "$event" "$payload" || true
exit 0
