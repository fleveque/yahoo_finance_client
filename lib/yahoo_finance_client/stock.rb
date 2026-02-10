# frozen_string_literal: true

require "httparty"
require "json"

module YahooFinanceClient
  # This class provides methods to interact with Yahoo Finance API for stock data.
  class Stock
    QUOTE_PATH = "/v7/finance/quote"
    CACHE_TTL = 300
    MAX_RETRIES = 2
    BATCH_SIZE = 50
    AUTH_ERROR_PATTERNS = [/invalid cookie/i, /invalid crumb/i, /unauthorized/i].freeze

    @cache = {}

    class << self
      def get_quote(symbol)
        cache_key = "quote_#{symbol}"
        fetch_from_cache(cache_key) || fetch_and_cache(cache_key, symbol)
      end

      def get_quotes(symbols)
        return {} if symbols.nil? || symbols.empty?

        results, uncached = partition_cached(symbols)
        fetch_uncached_quotes(uncached, results)
        results
      end

      private

      def partition_cached(symbols)
        results = {}
        uncached = []
        symbols.each do |symbol|
          cached = fetch_from_cache("quote_#{symbol}")
          cached ? results[symbol] = cached : uncached << symbol
        end
        [results, uncached]
      end

      def fetch_uncached_quotes(uncached, results)
        uncached.each_slice(BATCH_SIZE) do |batch|
          fetch_quotes_data(batch).each do |sym, data|
            store_in_cache("quote_#{sym}", data)
            results[sym] = data
          end
        end
      end

      def fetch_and_cache(cache_key, symbol)
        data = fetch_quote_data(symbol)
        store_in_cache(cache_key, data) if data[:error].nil?
        data
      end

      def fetch_quote_data(symbol)
        retries = 0
        begin
          response = make_authenticated_request(symbol)
          handle_response(response, symbol)
        rescue AuthenticationError
          retries += 1
          retry if retries <= MAX_RETRIES
          { error: "Authentication failed after #{MAX_RETRIES} retries" }
        end
      end

      def fetch_quotes_data(symbols)
        retries = 0
        symbols_param = symbols.join(",")
        begin
          response = make_authenticated_request(symbols_param)
          handle_batch_response(response, symbols)
        rescue AuthenticationError
          retries += 1
          retry if retries <= MAX_RETRIES
          symbols.each_with_object({}) { |s, h| h[s] = { error: "Authentication failed after #{MAX_RETRIES} retries" } }
        end
      end

      def make_authenticated_request(symbol)
        session = Session.instance
        session.ensure_authenticated
        url = "#{session.base_url}#{QUOTE_PATH}?symbols=#{symbol}&crumb=#{session.crumb}"
        HTTParty.get(url, headers: { "User-Agent" => Session::USER_AGENT, "Cookie" => session.cookie })
      end

      def handle_response(response, symbol)
        if auth_error?(response)
          Session.instance.invalidate!
          raise AuthenticationError, "Authentication failed"
        end
        response.success? ? parse_response(response.body, symbol) : { error: "Yahoo Finance connection failed" }
      end

      def handle_batch_response(response, symbols)
        if auth_error?(response)
          Session.instance.invalidate!
          raise AuthenticationError, "Authentication failed"
        end
        unless response.success?
          return symbols.each_with_object({}) do |s, h|
            h[s] = { error: "Yahoo Finance connection failed" }
          end
        end

        parse_batch_response(response.body, symbols)
      end

      def auth_error?(response)
        response.code == 401 || AUTH_ERROR_PATTERNS.any? { |p| response.body.to_s.match?(p) }
      end

      def parse_response(body, symbol)
        quote = JSON.parse(body).dig("quoteResponse", "result", 0)
        quote ? format_quote(quote) : { error: "No data was found for #{symbol}" }
      end

      def parse_batch_response(body, symbols)
        results = JSON.parse(body).dig("quoteResponse", "result") || []
        found = results.each_with_object({}) do |quote, hash|
          formatted = format_quote(quote)
          hash[formatted[:symbol]] = formatted
        end

        symbols.each_with_object(found) do |symbol, hash|
          hash[symbol] ||= { error: "No data was found for #{symbol}" }
        end
      end

      def format_quote(quote)
        price = quote["regularMarketPrice"]
        dividend = quote["dividendRate"]
        eps = quote["epsTrailingTwelveMonths"]

        build_quote_hash(quote, price, dividend, eps)
      end

      def build_quote_hash(quote, price, dividend, eps)
        {
          symbol: quote["symbol"], name: quote["shortName"], price: price,
          change: quote["regularMarketChange"], percent_change: quote["regularMarketChangePercent"],
          volume: quote["regularMarketVolume"], pe_ratio: quote["trailingPE"], eps: eps,
          dividend: dividend, dividend_yield: calculate_yield(dividend, price),
          payout_ratio: calculate_payout(dividend, eps),
          ma50: quote["fiftyDayAverage"], ma200: quote["twoHundredDayAverage"]
        }
      end

      def calculate_yield(dividend, price)
        return nil unless dividend && price&.positive?

        (dividend / price * 100).round(2)
      end

      def calculate_payout(dividend, eps)
        return nil unless dividend && eps&.positive?

        (dividend / eps * 100).round(2)
      end

      def fetch_from_cache(key)
        cached_entry = @cache[key]
        return unless cached_entry && Time.now - cached_entry[:timestamp] < CACHE_TTL

        cached_entry[:data]
      end

      def store_in_cache(key, data)
        @cache.delete_if { |_, v| Time.now - v[:timestamp] >= CACHE_TTL } if @cache.size > 100
        @cache[key] = { data: data, timestamp: Time.now }
      end
    end
  end
end
