# Security

Enhanced stats expose operational data about running workers and in-flight HTTP requests. Treat the control app and JSON payload as **sensitive**.

## Control app exposure

Enhanced stats are served only through Puma's **control app**, not the public Rails port.

```ruby
# config/puma.rb
activate_control_app "tcp://127.0.0.1:9293", { auth_token: "long-random-secret" }
```

### Recommendations

| Practice | Why |
|----------|-----|
| Bind to `127.0.0.1` or a private network interface | Prevents public internet access |
| Use a strong random `auth_token` | Token is required on every request |
| Do not log full control URLs | Token appears in query strings (`?token=...`) |
| Restrict who can run `pumactl` on the host | State file grants control access |

Requests without a valid token receive **403 Forbidden** (see [Status](../lib/puma/enhanced/stats/status.rb)).

## Authentication model

Authentication follows Puma's native control app rules:

```bash
curl "http://127.0.0.1:9293/enhanced-stats?token=SECRET"
bundle exec pumactl -S tmp/puma.state enhanced-stats
```

The token in query parameters may appear in:

- Shell history
- Reverse-proxy access logs
- Application monitoring tools

Prefer local access and locked-down logging where possible.

## Data exposed by default

Built-in **request** fields (zero-config):

| Field | Source | Risk |
|-------|--------|------|
| `remote_ip` | `action_dispatch.remote_ip` or `REMOTE_ADDR` | Client network identity |
| `method` | `REQUEST_METHOD` | Low |
| `path_info` | `SCRIPT_NAME` + `PATH_INFO` | URL structure, may include identifiers |

Built-in **session** fields are disabled unless you add them in the DSL.

## Session and custom extractors

The `session` and `request` DSL directives run at request registration time and copy values into the JSON payload visible to anyone with control-app access.

### Do not expose

- Passwords, tokens, API keys, JWTs
- Full session blobs or `_session_id` unless required
- Credit card or government ID fields
- Internal-only secrets used for authorization

### Safer patterns

```ruby
enhanced_stats do
  # Prefer opaque identifiers
  session :user_id

  # Avoid dumping entire objects
  session :tenant_slug do |session|
    session.dig("current_tenant", "slug")
  end

  # Keep paths coarse if PII is a concern
  request :path_info  # default — includes full path
end
```

Use `max_field_length` and avoid extractors that return large objects. Extractors that raise are swallowed by the registry (request still succeeds; field may be missing with no loud error — test extractors in staging).

## Multi-tenant and compliance

- In-flight entries may include **personal data** if you configure session fields.
- JSON is stored in memory on the master (cluster) between pings and returned on demand.
- Retention is **not** persistent — data exists only while requests are in-flight and in the latest worker snapshot cache.
- You are responsible for GDPR/HIPAA/etc. implications of fields you choose to extract.

## Threat model summary

| Threat | Mitigation |
|--------|------------|
| Unauthenticated stats leak | `auth_token` + bind address |
| PII in JSON | Minimal session fields; review DSL |
| DoS via repeated `/enhanced-stats` | Network ACL; rate limit at proxy (not built into gem) |
| Token in logs | Avoid logging query strings; use local access |

## Reporting issues

Report security concerns privately to the maintainers via GitHub Security Advisories on the [project repository](https://github.com/smart-sgisistemas/puma-enhanced-stats).
