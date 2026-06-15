#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${PUMA_VERSION:-}" || -n "${RAILS_VERSION:-}" ]]; then
  lock_args=()
  [[ -n "${PUMA_VERSION:-}" ]] && lock_args+=(--update puma)
  [[ -n "${RAILS_VERSION:-}" ]] && lock_args+=(--update rails)
  bundle lock "${lock_args[@]}"
  bundle install
fi

exec "$@"
