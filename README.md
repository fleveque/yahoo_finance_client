# YahooFinanceClient

A basic client to query Yahoo! Finance API.

Work in process, it might work, or not. It seems that Yahoo! disabled that kind of API access lately.

It was created to support https://github.com/fleveque/dividend-portfolio pet project.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add yahoo_finance_client
```

or add this line to your application's Gemfile:
```bash
gem "yahoo_finance_client"
```

And then execute:
```bash
$ bundle install
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install yahoo_finance_client
```

## Usage

### Single Quote

Fetch stock data by passing a ticker symbol:
```ruby
YahooFinanceClient::Stock.get_quote("AAPL")
# => {
#   symbol: "AAPL", name: "Apple Inc.", price: 182.52,
#   change: 1.25, percent_change: 0.69, volume: 48123456,
#   pe_ratio: 28.5, eps: 6.40,
#   dividend: 0.96, dividend_yield: 0.53, payout_ratio: 15.0,
#   ma50: 178.30, ma200: 172.15,
#   ex_dividend_date: #<Date: 2025-02-07>, dividend_date: #<Date: 2025-02-15>
# }
```

### Bulk Quotes

Fetch multiple quotes at once (batched in groups of 50):
```ruby
YahooFinanceClient::Stock.get_quotes(["AAPL", "MSFT", "GOOG"])
# => { "AAPL" => { symbol: "AAPL", ... }, "MSFT" => { ... }, "GOOG" => { ... } }
```

### Dividend History

Fetch historical dividend payments via the chart API:
```ruby
YahooFinanceClient::Stock.get_dividend_history("AAPL")
# => [{ date: #<Date: 2024-02-09>, amount: 0.24 }, ...]
```

The default range is `"2y"`. You can pass a different range:
```ruby
YahooFinanceClient::Stock.get_dividend_history("AAPL", range: "5y")
```

### Caching

All responses are cached for 5 minutes (300 seconds). The cache is shared across `get_quote`, `get_quotes`, and `get_dividend_history`.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

RuboCop is used as linter and can be run using `rake rubocop`

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/fleveque/yahoo_finance_client.

## License

This gem is licensed under the GNU General Public License v3.0. See the LICENSE.txt file for details.
