#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${PUMA_VERSION:-}" ]]; then
  bundle lock --update puma
  bundle install
fi

exec "$@"
