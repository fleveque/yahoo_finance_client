# frozen_string_literal: true

require "httparty"
require "json"

module YahooFinanceClient
  # This class provides methods to interact with Yahoo Finance API for stock data.
  class Stock
    BASE_URL = "https://query1.finance.yahoo.com/v7/finance/quote"

    def self.get_quote(symbol)
      url = build_url(symbol)
      response = HTTParty.get(url)

      if response.success?
        parse_response(response.body, symbol)
      else
        { error: "Yahoo Finance connection failed" }
      end
    end

    def self.build_url(symbol)
      "#{BASE_URL}?symbols=#{symbol}"
    end

    def self.parse_response(body, symbol)
      data = JSON.parse(body)
      quote = data.dig("quoteResponse", "result", 0)

      if quote
        format_quote(quote)
      else
        { error: "No data was found for #{symbol}" }
      end
    end

    def self.format_quote(quote)
      {
        symbol: quote["symbol"],
        price: quote["regularMarketPrice"],
        change: quote["regularMarketChange"],
        percent_change: quote["regularMarketChangePercent"],
        volume: quote["regularMarketVolume"]
      }
    end
  end
end
