# frozen_string_literal: true

require "httparty"
require "json"

module YahooFinanceClient
  # This class provides methods to interact with Yahoo Finance API for stock data.
  class Stock
    BASE_URL = "https://query1.finance.yahoo.com/v7/finance/quote"
    COOKIE_URL = "https://fc.yahoo.com"
    CRUMB_URL = "https://query1.finance.yahoo.com/v1/test/getcrumb"
    USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64)"
    CACHE_TTL = 300 # Cache time-to-live in seconds (e.g., 5 minutes)

    @cache = {}

    class << self
      def get_quote(symbol)
        cache_key = "quote_#{symbol}"
        cached_data = fetch_from_cache(cache_key)

        return cached_data if cached_data

        data = fetch_quote_data(symbol)
        store_in_cache(cache_key, data) if data[:error].nil?
        data
      end

      private

      def fetch_quote_data(symbol)
        cookie = fetch_cookie
        crumb = fetch_crumb(cookie)
        url = build_url(symbol, crumb)
        pp url
        response = HTTParty.get(url, headers: { "User-Agent" => USER_AGENT })

        if response.success?
          parse_response(response.body, symbol)
        else
          { error: "Yahoo Finance connection failed" }
        end
      end

      def build_url(symbol, crumb)
        "#{BASE_URL}?symbols=#{symbol}&crumb=#{crumb}"
      end

      def fetch_cookie
        response = HTTParty.get(COOKIE_URL, headers: { "User-Agent" => USER_AGENT })
        response.headers["set-cookie"]
      end

      def fetch_crumb(cookie)
        response = HTTParty.get(CRUMB_URL, headers: { "User-Agent" => USER_AGENT, "Cookie" => cookie })
        response.body
      end

      def parse_response(body, symbol)
        data = JSON.parse(body)
        quote = data.dig("quoteResponse", "result", 0)

        if quote
          format_quote(quote)
        else
          { error: "No data was found for #{symbol}" }
        end
      end

      def format_quote(quote)
        {
          symbol: quote["symbol"],
          price: quote["regularMarketPrice"],
          change: quote["regularMarketChange"],
          percent_change: quote["regularMarketChangePercent"],
          volume: quote["regularMarketVolume"]
        }
      end

      def fetch_from_cache(key)
        cached_entry = @cache[key]
        return unless cached_entry

        if Time.now - cached_entry[:timestamp] < CACHE_TTL
          cached_entry[:data]
        else
          @cache.delete(key)
          nil
        end
      end

      def store_in_cache(key, data)
        @cache[key] = { data: data, timestamp: Time.now }
      end
    end
  end
end
