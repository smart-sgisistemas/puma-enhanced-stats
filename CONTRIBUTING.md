# Contributing

Contributions are welcome on [GitHub](https://github.com/smart-sgisistemas/puma-enhanced-stats).

## Setup

```bash
bin/setup
bundle exec rake
```

Integration specs start a real Puma server and require more time:

```bash
bundle exec rspec --tag integration
# skip locally:
SKIP_INTEGRATION=1 bundle exec rake
```

Docker (matches CI):

```bash
docker build -t puma-enhanced-stats:dev .
docker run --rm puma-enhanced-stats:dev bundle exec rake
```

## Tests and coverage

| Command | Purpose |
|---------|---------|
| `bundle exec rake` | Default RSpec (unit + contract) |
| `bundle exec rspec --tag ~integration` | Unit specs only |
| `COVERAGE=true bundle exec rake spec:coverage` | 100% line + branch required |

Coverage report: `coverage/index.html`.

## JSON contract changes

Any change to the public JSON shape requires **all** of:

1. The active schema under [schema/](schema/) (currently [enhanced-stats-v1.json](schema/enhanced-stats-v1.json))
2. Matching fixture under [spec/fixtures/](spec/fixtures/)
3. Contract spec under [spec/contract/](spec/contract/)
4. [docs/json-contract.md](docs/json-contract.md) and [CHANGELOG.md](CHANGELOG.md)

Legacy schema files under `schema/` are retained only when a major contract revision ships; the active contract is [enhanced-stats-v1.json](schema/enhanced-stats-v1.json) (gem **v1.0.0**).

## Documentation

- User guides live in [docs/](docs/README.md)
- README is the entry point — keep it concise; move detail to `docs/`
- Update YARD comments in `lib/` for public API changes
- Run `bundle exec yard` before merging doc-heavy changes
- Update [sig/puma/enhanced/stats.rbs](sig/puma/enhanced/stats.rbs) when signatures change

## Code style

- Match existing patterns in surrounding files
- Keep the hot path fail-open (stats must not break requests)
- Prefer focused specs over trivial assertions
- `# frozen_string_literal: true` on Ruby files

## Pull requests

1. Branch from `main`
2. Keep changes scoped to the feature or fix
3. Ensure CI passes (Ruby/Rails matrix + Docker coverage job)
4. Describe JSON or DSL changes clearly in the PR body

## Security

Do not open public issues for security vulnerabilities. Use [GitHub Security Advisories](https://github.com/smart-sgisistemas/puma-enhanced-stats/security/advisories) on the repository.

See [docs/security.md](docs/security.md) for operational security guidance.
