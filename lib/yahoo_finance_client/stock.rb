# frozen_string_literal: true

require "httparty"
require "json"
require "uri"

module YahooFinanceClient
  # This class provides methods to interact with Yahoo Finance API for stock data.
  class Stock
    QUOTE_PATH = "/v7/finance/quote"
    CHART_PATH = "/v8/finance/chart"
    SEARCH_PATH = "/v1/finance/search"
    SEARCH_BASE_URL = "https://query1.finance.yahoo.com"
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

      def get_dividend_history(symbol, range: "2y")
        cache_key = "div_history_#{symbol}_#{range}"
        fetch_from_cache(cache_key) || fetch_and_cache_dividend_history(cache_key, symbol, range)
      end

      # Fetch the current FX rate between two ISO 4217 currency codes via Yahoo's
      # `<FROM><TO>=X` quote symbol. Returns 1.0 for identity pairs without hitting the API.
      #
      # @param from [String] source currency code (e.g. "EUR")
      # @param to [String] target currency code (e.g. "USD")
      # @return [Float, nil] one unit of `from` expressed in `to`, or nil on error
      def get_fx_rate(from, to)
        return 1.0 if from == to

        cache_key = "fx_#{from}_#{to}"
        fetch_from_cache(cache_key) || fetch_and_cache_fx_rate(cache_key, from, to)
      end

      # Search the Yahoo Finance autocomplete index for matching symbols.
      #
      # @param query [String] free-text query (ticker or company name)
      # @param count [Integer] max number of results to return
      # @return [Array<Hash>] each entry has symbol, name, exchange, type, type_display
      def search(query, count: 10)
        normalized = query.to_s.strip
        return [] if normalized.empty?

        cache_key = "search_#{normalized.downcase}_#{count}"
        fetch_from_cache(cache_key) || fetch_and_cache_search(cache_key, normalized, count)
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
          symbol: quote["symbol"], name: quote["shortName"], price: price, currency: quote["currency"],
          change: quote["regularMarketChange"], percent_change: quote["regularMarketChangePercent"],
          volume: quote["regularMarketVolume"], pe_ratio: quote["trailingPE"], eps: eps,
          dividend: dividend, dividend_yield: calculate_yield(dividend, price),
          payout_ratio: calculate_payout(dividend, eps),
          ma50: quote["fiftyDayAverage"], ma200: quote["twoHundredDayAverage"],
          fifty_two_week_high: quote["fiftyTwoWeekHigh"], fifty_two_week_low: quote["fiftyTwoWeekLow"],
          ex_dividend_date: parse_unix_date(quote["exDividendDate"]),
          dividend_date: parse_unix_date(quote["dividendDate"])
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

      def parse_unix_date(value)
        return nil unless value.is_a?(Numeric) && value.positive?

        Time.at(value).utc.to_date
      end

      def fetch_and_cache_fx_rate(cache_key, from, to)
        rate = fetch_fx_rate_data("#{from}#{to}=X")
        store_in_cache(cache_key, rate) if rate
        rate
      end

      def fetch_fx_rate_data(symbol)
        retries = 0
        begin
          parse_fx_response(make_authenticated_request(symbol))
        rescue AuthenticationError
          retries += 1
          retry if retries <= MAX_RETRIES
          nil
        end
      end

      def parse_fx_response(response)
        if auth_error?(response)
          Session.instance.invalidate!
          raise AuthenticationError, "Authentication failed"
        end
        return nil unless response.success?

        rate = JSON.parse(response.body).dig("quoteResponse", "result", 0, "regularMarketPrice")
        rate&.to_f
      rescue JSON::ParserError
        nil
      end

      def fetch_and_cache_dividend_history(cache_key, symbol, range)
        data = fetch_dividend_history_data(symbol, range)
        store_in_cache(cache_key, data) unless data.empty?
        data
      end

      def fetch_dividend_history_data(symbol, range)
        retries = 0
        begin
          response = make_chart_request(symbol, range)
          parse_dividend_history(response)
        rescue AuthenticationError
          retries += 1
          retry if retries <= MAX_RETRIES
          []
        end
      end

      def make_chart_request(symbol, range)
        session = Session.instance
        session.ensure_authenticated
        url = "#{session.base_url}#{CHART_PATH}/#{symbol}?range=#{range}&interval=1mo&events=div&crumb=#{session.crumb}"
        HTTParty.get(url, headers: { "User-Agent" => Session::USER_AGENT, "Cookie" => session.cookie })
      end

      def parse_dividend_history(response)
        raise_if_auth_error(response)
        return [] unless response.success?

        dividends = JSON.parse(response.body).dig("chart", "result", 0, "events", "dividends")
        return [] unless dividends

        build_dividend_entries(dividends)
      end

      def raise_if_auth_error(response)
        return unless auth_error?(response)

        Session.instance.invalidate!
        raise AuthenticationError, "Authentication failed"
      end

      def build_dividend_entries(dividends)
        entries = dividends.values.filter_map { |entry| parse_dividend_entry(entry) }
        entries.sort_by { |d| d[:date] }
      end

      def parse_dividend_entry(entry)
        date = parse_unix_date(entry["date"])
        amount = entry["amount"]
        return unless date && amount&.positive?

        { date: date, amount: amount.round(4) }
      end

      def fetch_and_cache_search(cache_key, query, count)
        data = fetch_search_data(query, count)
        store_in_cache(cache_key, data) unless data.empty?
        data
      end

      # Try an unauthenticated request first — the v1/finance/search endpoint is historically
      # public and does not validate the crumb. Only fall through to the cookie+crumb flow if
      # Yahoo actually returns an auth error.
      def fetch_search_data(query, count)
        url = build_search_url(query, count)
        response = HTTParty.get(url, headers: { "User-Agent" => Session::USER_AGENT })

        return fetch_authenticated_search(query, count) if auth_error?(response)
        return [] unless response.success?

        parse_search_response(response.body)
      rescue StandardError
        []
      end

      def fetch_authenticated_search(query, count)
        retries = 0
        begin
          handle_authenticated_search_response(make_authenticated_search_request(query, count))
        rescue AuthenticationError
          retries += 1
          retry if retries <= MAX_RETRIES
          []
        end
      end

      def handle_authenticated_search_response(response)
        if auth_error?(response)
          Session.instance.invalidate!
          raise AuthenticationError, "Authentication failed"
        end
        response.success? ? parse_search_response(response.body) : []
      end

      def make_authenticated_search_request(query, count)
        session = Session.instance
        session.ensure_authenticated
        url = "#{build_search_url(query, count)}&crumb=#{session.crumb}"
        HTTParty.get(url, headers: { "User-Agent" => Session::USER_AGENT, "Cookie" => session.cookie })
      end

      def build_search_url(query, count)
        "#{SEARCH_BASE_URL}#{SEARCH_PATH}?q=#{URI.encode_www_form_component(query)}" \
          "&quotesCount=#{count}&newsCount=0"
      end

      def parse_search_response(body)
        quotes = JSON.parse(body)["quotes"] || []
        quotes.filter_map { |q| format_search_quote(q) }
      rescue JSON::ParserError
        []
      end

      def format_search_quote(quote)
        symbol = quote["symbol"].to_s
        return nil if symbol.empty?

        {
          symbol: symbol,
          name: pick_search_name(symbol, quote["shortname"], quote["longname"]),
          exchange: quote["exchDisp"] || quote["exchange"],
          type: quote["quoteType"],
          type_display: quote["typeDisp"]
        }
      end

      # Mutual funds and some foreign listings report the symbol code as their `shortname`
      # (e.g. Baelo Dividendo Creciente comes back with shortname="0P0001QYEF.F"); prefer the
      # longname when shortname is missing or just echoes the symbol.
      def pick_search_name(symbol, shortname, longname)
        [shortname, longname, symbol].find { |n| !n.to_s.empty? && n != symbol } || symbol
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
