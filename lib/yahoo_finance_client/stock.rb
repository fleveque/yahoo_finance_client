# frozen_string_literal: true

require "httparty"
require "json"

module YahooFinanceClient
  # This class provides methods to interact with Yahoo Finance API for stock data.
  class Stock
    BASE_URL = "https://query1.finance.yahoo.com/v7/finance/quote"
    COOKIE_URL = "https://fc.yahoo.com"
    CRUMB_URL = "https://query1.finance.yahoo.com/v1/test/getcrumb"

    USER_AGENT = "YahooFinanceClient/#{YahooFinanceClient::VERSION}".freeze

    def self.get_quote(symbol)
      cookie = fetch_cookie
      crumb = fetch_crumb(cookie)
      url = build_url(symbol, crumb)
      response = HTTParty.get(url, headers: { "User-Agent" => USER_AGENT })

      if response.success?
        parse_response(response.body, symbol)
      else
        { error: "Yahoo Finance connection failed" }
      end
    end

    def self.build_url(symbol, crumb)
      "#{BASE_URL}?symbols=#{symbol}&crumb=#{crumb}"
    end

    def self.fetch_cookie
      response = HTTParty.get(COOKIE_URL, headers: { "User-Agent" => USER_AGENT })
      response.headers["set-cookie"]
    end

    def self.fetch_crumb(cookie)
      response = HTTParty.get(CRUMB_URL, headers: { "User-Agent" => USER_AGENT, "Cookie" => cookie })
      response.body
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
