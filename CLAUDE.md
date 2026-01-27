# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

YahooFinanceClient is a Ruby gem providing a client for the Yahoo! Finance API. It fetches stock quotes with built-in caching (5-minute TTL) and handles Yahoo's authentication flow (cookies + CSRF crumb tokens).

**Note**: Yahoo! may have disabled API access - this project is in a work-in-progress state.

## Commands

| Command | Purpose |
|---------|---------|
| `rake` | Run tests and linting (default task) |
| `rake spec` | Run RSpec tests only |
| `rake rubocop` | Run RuboCop linter only |
| `bundle exec rspec spec/yahoo_finance_client/stock_spec.rb` | Run single test file |
| `bundle exec rake install` | Install gem locally |
| `bin/console` | Interactive Ruby console for experimentation |

## Architecture

```
lib/
├── yahoo_finance_client.rb           # Main module entry point
└── yahoo_finance_client/
    ├── stock.rb                      # Core API client (class methods)
    └── version.rb                    # Version constant
```

**YahooFinanceClient::Stock** is the main class with a single public interface:
- `Stock.get_quote(symbol)` - Returns hash with `symbol`, `price`, `change`, `percent_change`, `volume`

The class handles Yahoo's auth flow internally: fetch cookie → get crumb token → make authenticated API request. Results are cached in a class-level hash with 300-second expiration.

## Testing

Uses RSpec with WebMock for HTTP stubbing. Tests clear the cache before each example. Key test patterns:
- Stub HTTP requests, don't hit real API
- Test cache behavior via instance variable inspection (`@quotes_cache`)
- Contexts organize success/failure/cache scenarios

## Code Style

- Ruby 3.4 target
- Max line length: 120
- Double quotes for strings
- Frozen string literals enabled
