# Change Log

## [0.7.0] - 2026-05-16

- Add `Stock.get_fx_rate(from, to)` returning the current FX rate between two ISO 4217 currency codes via Yahoo's `<FROM><TO>=X` quote symbol. Returns `1.0` for identity pairs without hitting the API; returns `nil` on error.

## [0.6.0] - 2026-05-16

- Expose Yahoo's `currency` field in `get_quote` / `get_quotes` results so callers can support multi-currency portfolios

## [0.5.0] - 2026-05-15

- Add `Stock.search(query, count:)` returning matching tickers from Yahoo's `v1/finance/search` autocomplete endpoint

## [0.4.1] - 2026-02-13

- Add `fifty_two_week_high` and `fifty_two_week_low` fields to quote data

## [0.4.0] - 2026-02-12

- Add dividend history fetching via chart API (`get_dividend_history`)
- Update README with bulk quotes, dividend history, and caching docs

## [0.3.1] - 2026-02-12

- Add `ex_dividend_date` and `dividend_date` fields to quote data

## [0.3.0] - 2026-02-10

- Add bulk quotes support with `get_quotes` method

## [0.2.1] - 2026-01-29

- Add extended stock information fields (EPS, PE ratio, dividend data, moving averages)

## [0.2.0] - 2026-01-27

- Add multi-strategy authentication with retry logic
- Add CLAUDE.md with project instructions

## [0.1.6] - 2025-02-18

- Adding a simple cache

## [0.1.5] - 2025-02-18

- Change User Agent so Yahoo requests work

## [0.1.4] - 2025-02-18

- Fix version & Gemfile.lock issues

## [0.1.3] - 2025-02-18

- Minor changes on doc

## [0.1.2] - 2025-02-18

- Fix dependencies

## [0.1.1] - 2025-02-18

- Get cookie & crumb to be able to get Y! data

## [0.1.0] - 2025-02-18

- Initial release
