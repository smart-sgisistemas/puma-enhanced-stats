#!/usr/bin/env bash
# Requisições em andamento por worker (enhanced-stats).
# Requer: curl, jq, PUMA_CONTROL_TOKEN no ambiente.

set -euo pipefail

curl -s "tcp://localhost:9393/enhanced-stats?token=${PUMA_CONTROL_TOKEN:-}" | jq -r '
  . as $root |
  [$root.workers[]?.requests.items[]?] as $items |

  (["elapsed"]
   + (["id", "started_at", "method", "path_info", "remote_ip"]
      + ($items | map(keys - ["session", "id", "started_at", "method", "path_info", "remote_ip"]) | add // [] | unique | sort))
   + ($items | map(.session // {} | keys) | add // [] | unique | sort | map("session." + .))
  ) as $cols |

  def elapsed($t):
    if ($t | type) != "string" or $t == "" then "-"
    else ((now - ($t | fromdateiso8601)) | floor | tostring) + "s"
    end;

  def val($item; $col):
    if $col == "elapsed" then elapsed($item.started_at)
    elif ($col | startswith("session.")) then ($item.session // {})[$col[8:]] // "-"
    else $item[$col] // "-"
    end;

  $root.workers[] as $w |
  "",
  "worker \($w.index)  pid=\($w.pid)  in_flight=\($w.requests.meta.count // 0)",
  ($cols | @tsv),
  (
    if ($w.requests.items // [] | length) == 0 then "(vazio)"
    else $w.requests.items[] | [$cols[] as $c | val(.; $c)] | @tsv
    end
  )
'
