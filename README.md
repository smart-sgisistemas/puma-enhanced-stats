# Puma::Enhanced::Stats

Gem to collect, enrich, and expose extended statistics from Puma's `control_app`.

## Installation

Add the gem to your Gemfile:

```ruby
gem "puma-enhanced-stats", github: "smart-sgisistemas/puma-enhanced-stats"
```

Then run:

```bash
bundle install
```

## Usage

```ruby
require "puma/enhanced/stats"

Puma::Enhanced::Stats::VERSION
```

## Development

Clone the repository and install dependencies:

```bash
bin/setup
bundle exec rake
```

Or use Docker:

```bash
docker build -t puma-enhanced-stats:dev .
docker run --rm -v "$(pwd):/app" -w /app puma-enhanced-stats:dev bundle exec rake
```

Interactive console:

```bash
bin/console
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/smart-sgisistemas/puma-enhanced-stats.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
