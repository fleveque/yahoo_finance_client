# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe YahooFinanceClient::Stock do
  describe ".get_quote" do
    let(:symbol) { "AAPL" }
    let(:base_url) { "https://query1.finance.yahoo.com" }
    let(:quote_url) { "#{base_url}/v7/finance/quote?symbols=#{symbol}&crumb=#{crumb}" }
    let(:cookie_url) { "https://fc.yahoo.com" }
    let(:crumb_url) { "https://query1.finance.yahoo.com/v1/test/getcrumb" }
    let(:cookie) { "test_cookie" }
    let(:crumb) { "test_crumb" }
    let(:cache_key) { "quote_#{symbol}" }
    let(:session) { YahooFinanceClient::Session.instance }

    before do
      described_class.instance_variable_set(:@cache, {}) # Clear the cache
      session.send(:reset!) # Reset session state
      stub_request(:get, cookie_url)
        .to_return(status: 200, headers: { "set-cookie" => cookie })
      stub_request(:get, crumb_url)
        .with(headers: { "Cookie" => cookie })
        .to_return(status: 200, body: crumb)
    end

    context "when the response is successful" do
      let(:response_body) do
        {
          "quoteResponse" => {
            "result" => [
              {
                "symbol" => "AAPL",
                "shortName" => "Apple Inc.",
                "regularMarketPrice" => 150.0,
                "regularMarketChange" => 1.5,
                "regularMarketChangePercent" => 1.0,
                "regularMarketVolume" => 100_000,
                "trailingPE" => 25.5,
                "epsTrailingTwelveMonths" => 5.88,
                "dividendRate" => 0.96,
                "fiftyDayAverage" => 148.5,
                "twoHundredDayAverage" => 145.0,
                "fiftyTwoWeekHigh" => 180.0,
                "fiftyTwoWeekLow" => 120.0,
                "exDividendDate" => 1_710_374_400
              }
            ]
          }
        }.to_json
      end

      let(:expected_quote) do
        {
          symbol: "AAPL",
          name: "Apple Inc.",
          price: 150.0,
          change: 1.5,
          percent_change: 1.0,
          volume: 100_000,
          pe_ratio: 25.5,
          eps: 5.88,
          dividend: 0.96,
          dividend_yield: 0.64,
          payout_ratio: 16.33,
          ma50: 148.5,
          ma200: 145.0,
          fifty_two_week_high: 180.0,
          fifty_two_week_low: 120.0,
          ex_dividend_date: Date.new(2024, 3, 14),
          dividend_date: nil
        }
      end

      before do
        stub_request(:get, quote_url)
          .to_return(status: 200, body: response_body)
      end

      it "returns the quote data" do
        result = described_class.get_quote(symbol)
        expect(result).to eq(expected_quote)
      end

      it "returns ex_dividend_date as a Date" do
        result = described_class.get_quote(symbol)
        expect(result[:ex_dividend_date]).to be_a(Date)
        expect(result[:ex_dividend_date]).to eq(Date.new(2024, 3, 14))
      end

      it "caches the quote data" do
        described_class.get_quote(symbol)
        cache = described_class.instance_variable_get(:@cache)
        expect(cache[cache_key][:data]).to eq(expected_quote)
      end
    end

    context "when the response is unsuccessful" do
      before do
        stub_request(:get, quote_url)
          .to_return(status: 500, body: "")
      end

      it "returns an error message" do
        result = described_class.get_quote(symbol)
        expect(result).to eq(error: "Yahoo Finance connection failed")
      end
    end

    context "when no data is found for the symbol" do
      let(:response_body) do
        {
          "quoteResponse" => {
            "result" => []
          }
        }.to_json
      end

      before do
        stub_request(:get, quote_url)
          .to_return(status: 200, body: response_body)
      end

      it "returns an error message" do
        result = described_class.get_quote(symbol)
        expect(result).to eq(error: "No data was found for #{symbol}")
      end
    end

    context "when the data is cached" do
      let(:cached_data) do
        {
          symbol: "AAPL",
          name: "Apple Inc.",
          price: 150.0,
          change: 1.5,
          percent_change: 1.0,
          volume: 100_000,
          pe_ratio: 25.5,
          eps: 5.88,
          dividend: 0.96,
          dividend_yield: 0.64,
          payout_ratio: 16.33,
          ma50: 148.5,
          ma200: 145.0,
          fifty_two_week_high: 180.0,
          fifty_two_week_low: 120.0,
          ex_dividend_date: Date.new(2024, 3, 14),
          dividend_date: nil
        }
      end

      before do
        described_class.instance_variable_set(
          :@cache,
          {
            cache_key => { data: cached_data, timestamp: Time.now }
          }
        )
      end

      it "returns the cached data" do
        result = described_class.get_quote(symbol)
        expect(result).to eq(cached_data)
      end
    end

    context "when the cached data is expired" do
      let(:cached_data) do
        {
          symbol: "AAPL",
          name: "Apple Inc.",
          price: 150.0,
          change: 1.5,
          percent_change: 1.0,
          volume: 100_000,
          pe_ratio: 25.5,
          eps: 5.88,
          dividend: 0.96,
          dividend_yield: 0.64,
          payout_ratio: 16.33,
          ma50: 148.5,
          ma200: 145.0,
          fifty_two_week_high: 180.0,
          fifty_two_week_low: 120.0,
          ex_dividend_date: Date.new(2024, 3, 14),
          dividend_date: nil
        }
      end

      let(:response_body) do
        {
          "quoteResponse" => {
            "result" => [
              {
                "symbol" => "AAPL",
                "shortName" => "Apple Inc.",
                "regularMarketPrice" => 155.0,
                "regularMarketChange" => 2.0,
                "regularMarketChangePercent" => 1.3,
                "regularMarketVolume" => 120_000,
                "trailingPE" => 26.0,
                "epsTrailingTwelveMonths" => 5.96,
                "dividendRate" => 0.96,
                "fiftyDayAverage" => 150.0,
                "twoHundredDayAverage" => 147.0,
                "fiftyTwoWeekHigh" => 185.0,
                "fiftyTwoWeekLow" => 125.0,
                "exDividendDate" => 1_710_374_400
              }
            ]
          }
        }.to_json
      end

      let(:expected_new_quote) do
        {
          symbol: "AAPL",
          name: "Apple Inc.",
          price: 155.0,
          change: 2.0,
          percent_change: 1.3,
          volume: 120_000,
          pe_ratio: 26.0,
          eps: 5.96,
          dividend: 0.96,
          dividend_yield: 0.62,
          payout_ratio: 16.11,
          ma50: 150.0,
          ma200: 147.0,
          fifty_two_week_high: 185.0,
          fifty_two_week_low: 125.0,
          ex_dividend_date: Date.new(2024, 3, 14),
          dividend_date: nil
        }
      end

      before do
        described_class.instance_variable_set(
          :@cache,
          {
            cache_key => { data: cached_data, timestamp: Time.now - (YahooFinanceClient::Stock::CACHE_TTL + 1) }
          }
        )
        stub_request(:get, quote_url)
          .to_return(status: 200, body: response_body)
      end

      it "fetches new data and updates the cache" do
        result = described_class.get_quote(symbol)
        expect(result).to eq(expected_new_quote)
        cache = described_class.instance_variable_get(:@cache)
        expect(cache[cache_key][:data]).to eq(expected_new_quote)
      end
    end

    context "when stock has no dividend data" do
      let(:response_body) do
        {
          "quoteResponse" => {
            "result" => [
              {
                "symbol" => "GOOG",
                "shortName" => "Alphabet Inc.",
                "regularMarketPrice" => 140.0,
                "regularMarketChange" => -0.5,
                "regularMarketChangePercent" => -0.36,
                "regularMarketVolume" => 50_000,
                "trailingPE" => 22.0,
                "epsTrailingTwelveMonths" => 6.36,
                "fiftyDayAverage" => 138.0,
                "twoHundredDayAverage" => 135.0,
                "fiftyTwoWeekHigh" => 160.0,
                "fiftyTwoWeekLow" => 110.0
              }
            ]
          }
        }.to_json
      end

      before do
        stub_request(:get, "#{base_url}/v7/finance/quote?symbols=GOOG&crumb=#{crumb}")
          .to_return(status: 200, body: response_body)
      end

      it "returns nil for dividend-related fields" do
        result = described_class.get_quote("GOOG")
        expect(result).to eq(
          symbol: "GOOG",
          name: "Alphabet Inc.",
          price: 140.0,
          change: -0.5,
          percent_change: -0.36,
          volume: 50_000,
          pe_ratio: 22.0,
          eps: 6.36,
          dividend: nil,
          dividend_yield: nil,
          payout_ratio: nil,
          ma50: 138.0,
          ma200: 135.0,
          fifty_two_week_high: 160.0,
          fifty_two_week_low: 110.0,
          ex_dividend_date: nil,
          dividend_date: nil
        )
      end

      it "returns nil for ex_dividend_date when exDividendDate is missing" do
        result = described_class.get_quote("GOOG")
        expect(result[:ex_dividend_date]).to be_nil
      end
    end

    context "when exDividendDate is zero" do
      let(:response_body) do
        {
          "quoteResponse" => {
            "result" => [
              {
                "symbol" => "TEST",
                "shortName" => "Test Inc.",
                "regularMarketPrice" => 100.0,
                "regularMarketChange" => 0,
                "regularMarketChangePercent" => 0,
                "regularMarketVolume" => 10_000,
                "trailingPE" => nil,
                "epsTrailingTwelveMonths" => nil,
                "exDividendDate" => 0
              }
            ]
          }
        }.to_json
      end

      before do
        stub_request(:get, "#{base_url}/v7/finance/quote?symbols=TEST&crumb=#{crumb}")
          .to_return(status: 200, body: response_body)
      end

      it "returns nil for ex_dividend_date" do
        result = described_class.get_quote("TEST")
        expect(result[:ex_dividend_date]).to be_nil
      end
    end

    context "when stock has negative EPS" do
      let(:response_body) do
        {
          "quoteResponse" => {
            "result" => [
              {
                "symbol" => "TSLA",
                "shortName" => "Tesla Inc.",
                "regularMarketPrice" => 200.0,
                "regularMarketChange" => 5.0,
                "regularMarketChangePercent" => 2.56,
                "regularMarketVolume" => 80_000,
                "trailingPE" => nil,
                "epsTrailingTwelveMonths" => -1.5,
                "dividendRate" => 0.0,
                "fiftyDayAverage" => 195.0,
                "twoHundredDayAverage" => 180.0,
                "fiftyTwoWeekHigh" => 250.0,
                "fiftyTwoWeekLow" => 150.0
              }
            ]
          }
        }.to_json
      end

      before do
        stub_request(:get, "#{base_url}/v7/finance/quote?symbols=TSLA&crumb=#{crumb}")
          .to_return(status: 200, body: response_body)
      end

      it "returns nil for payout ratio when EPS is negative" do
        result = described_class.get_quote("TSLA")
        expect(result).to eq(
          symbol: "TSLA",
          name: "Tesla Inc.",
          price: 200.0,
          change: 5.0,
          percent_change: 2.56,
          volume: 80_000,
          pe_ratio: nil,
          eps: -1.5,
          dividend: 0.0,
          dividend_yield: 0.0,
          payout_ratio: nil,
          ma50: 195.0,
          ma200: 180.0,
          fifty_two_week_high: 250.0,
          fifty_two_week_low: 150.0,
          ex_dividend_date: nil,
          dividend_date: nil
        )
      end
    end

    context "when authentication fails and retries succeed" do
      let(:response_body) do
        {
          "quoteResponse" => {
            "result" => [
              {
                "symbol" => "AAPL",
                "shortName" => "Apple Inc.",
                "regularMarketPrice" => 150.0,
                "regularMarketChange" => 1.5,
                "regularMarketChangePercent" => 1.0,
                "regularMarketVolume" => 100_000,
                "trailingPE" => 25.5,
                "epsTrailingTwelveMonths" => 5.88,
                "dividendRate" => 0.96,
                "fiftyDayAverage" => 148.5,
                "twoHundredDayAverage" => 145.0,
                "fiftyTwoWeekHigh" => 180.0,
                "fiftyTwoWeekLow" => 120.0,
                "exDividendDate" => 1_710_374_400
              }
            ]
          }
        }.to_json
      end

      before do
        # First request returns auth error, second succeeds
        stub_request(:get, quote_url)
          .to_return(
            { status: 200, body: '{"error": "Invalid Cookie"}' },
            { status: 200, body: response_body }
          )
      end

      it "retries and returns the quote data" do
        result = described_class.get_quote(symbol)
        expect(result).to eq(
          symbol: "AAPL",
          name: "Apple Inc.",
          price: 150.0,
          change: 1.5,
          percent_change: 1.0,
          volume: 100_000,
          pe_ratio: 25.5,
          eps: 5.88,
          dividend: 0.96,
          dividend_yield: 0.64,
          payout_ratio: 16.33,
          ma50: 148.5,
          ma200: 145.0,
          fifty_two_week_high: 180.0,
          fifty_two_week_low: 120.0,
          ex_dividend_date: Date.new(2024, 3, 14),
          dividend_date: nil
        )
      end
    end

    context "when authentication fails after max retries" do
      before do
        stub_request(:get, quote_url)
          .to_return(status: 401, body: "Unauthorized")
      end

      it "returns an authentication error message" do
        result = described_class.get_quote(symbol)
        expect(result).to eq(error: "Authentication failed after 2 retries")
      end
    end

    context "when response contains 'invalid crumb' error" do
      let(:response_body) do
        {
          "quoteResponse" => {
            "result" => [
              {
                "symbol" => "AAPL",
                "shortName" => "Apple Inc.",
                "regularMarketPrice" => 150.0,
                "regularMarketChange" => 1.5,
                "regularMarketChangePercent" => 1.0,
                "regularMarketVolume" => 100_000,
                "trailingPE" => 25.5,
                "epsTrailingTwelveMonths" => 5.88,
                "dividendRate" => 0.96,
                "fiftyDayAverage" => 148.5,
                "twoHundredDayAverage" => 145.0,
                "fiftyTwoWeekHigh" => 180.0,
                "fiftyTwoWeekLow" => 120.0,
                "exDividendDate" => 1_710_374_400
              }
            ]
          }
        }.to_json
      end

      before do
        # First two requests return crumb error, third succeeds
        stub_request(:get, quote_url)
          .to_return(
            { status: 200, body: '{"error": "Invalid Crumb"}' },
            { status: 200, body: '{"error": "Invalid Crumb"}' },
            { status: 200, body: response_body }
          )
      end

      it "retries on invalid crumb errors" do
        result = described_class.get_quote(symbol)
        expect(result).to eq(
          symbol: "AAPL",
          name: "Apple Inc.",
          price: 150.0,
          change: 1.5,
          percent_change: 1.0,
          volume: 100_000,
          pe_ratio: 25.5,
          eps: 5.88,
          dividend: 0.96,
          dividend_yield: 0.64,
          payout_ratio: 16.33,
          ma50: 148.5,
          ma200: 145.0,
          fifty_two_week_high: 180.0,
          fifty_two_week_low: 120.0,
          ex_dividend_date: Date.new(2024, 3, 14),
          dividend_date: nil
        )
      end
    end
  end

  describe ".get_quotes" do
    let(:base_url) { "https://query1.finance.yahoo.com" }
    let(:cookie_url) { "https://fc.yahoo.com" }
    let(:crumb_url) { "https://query1.finance.yahoo.com/v1/test/getcrumb" }
    let(:cookie) { "test_cookie" }
    let(:crumb) { "test_crumb" }
    let(:session) { YahooFinanceClient::Session.instance }

    before do
      described_class.instance_variable_set(:@cache, {})
      session.send(:reset!)
      stub_request(:get, cookie_url)
        .to_return(status: 200, headers: { "set-cookie" => cookie })
      stub_request(:get, crumb_url)
        .with(headers: { "Cookie" => cookie })
        .to_return(status: 200, body: crumb)
    end

    context "when fetching multiple symbols successfully" do
      let(:symbols) { %w[AAPL MSFT] }
      let(:batch_url) { "#{base_url}/v7/finance/quote?symbols=AAPL,MSFT&crumb=#{crumb}" }
      let(:response_body) do
        {
          "quoteResponse" => {
            "result" => [
              {
                "symbol" => "AAPL", "shortName" => "Apple Inc.",
                "regularMarketPrice" => 150.0, "regularMarketChange" => 1.5,
                "regularMarketChangePercent" => 1.0, "regularMarketVolume" => 100_000,
                "trailingPE" => 25.5, "epsTrailingTwelveMonths" => 5.88,
                "dividendRate" => 0.96, "fiftyDayAverage" => 148.5,
                "twoHundredDayAverage" => 145.0, "fiftyTwoWeekHigh" => 180.0,
                "fiftyTwoWeekLow" => 120.0, "exDividendDate" => 1_710_374_400
              },
              {
                "symbol" => "MSFT", "shortName" => "Microsoft Corp.",
                "regularMarketPrice" => 380.0, "regularMarketChange" => 2.0,
                "regularMarketChangePercent" => 0.53, "regularMarketVolume" => 90_000,
                "trailingPE" => 35.0, "epsTrailingTwelveMonths" => 10.86,
                "dividendRate" => 3.0, "fiftyDayAverage" => 375.0,
                "twoHundredDayAverage" => 360.0, "fiftyTwoWeekHigh" => 420.0,
                "fiftyTwoWeekLow" => 310.0, "exDividendDate" => 1_715_644_800
              }
            ]
          }
        }.to_json
      end

      before do
        stub_request(:get, batch_url)
          .to_return(status: 200, body: response_body)
      end

      it "returns a hash of quotes keyed by symbol" do
        result = described_class.get_quotes(symbols)
        expect(result.keys).to match_array(%w[AAPL MSFT])
        expect(result["AAPL"][:price]).to eq(150.0)
        expect(result["MSFT"][:price]).to eq(380.0)
      end

      it "caches each symbol individually" do
        described_class.get_quotes(symbols)
        cache = described_class.instance_variable_get(:@cache)
        expect(cache["quote_AAPL"][:data][:price]).to eq(150.0)
        expect(cache["quote_MSFT"][:data][:price]).to eq(380.0)
      end
    end

    context "when one symbol is not found" do
      let(:symbols) { %w[AAPL INVALID] }
      let(:batch_url) { "#{base_url}/v7/finance/quote?symbols=AAPL,INVALID&crumb=#{crumb}" }
      let(:response_body) do
        {
          "quoteResponse" => {
            "result" => [
              {
                "symbol" => "AAPL", "shortName" => "Apple Inc.",
                "regularMarketPrice" => 150.0, "regularMarketChange" => 1.5,
                "regularMarketChangePercent" => 1.0, "regularMarketVolume" => 100_000,
                "trailingPE" => 25.5, "epsTrailingTwelveMonths" => 5.88,
                "dividendRate" => 0.96, "fiftyDayAverage" => 148.5,
                "twoHundredDayAverage" => 145.0, "fiftyTwoWeekHigh" => 180.0,
                "fiftyTwoWeekLow" => 120.0, "exDividendDate" => 1_710_374_400
              }
            ]
          }
        }.to_json
      end

      before do
        stub_request(:get, batch_url)
          .to_return(status: 200, body: response_body)
      end

      it "returns data for found symbols and errors for missing ones" do
        result = described_class.get_quotes(symbols)
        expect(result["AAPL"][:price]).to eq(150.0)
        expect(result["INVALID"]).to eq(error: "No data was found for INVALID")
      end
    end

    context "when some symbols are cached" do
      let(:symbols) { %w[AAPL MSFT] }
      let(:batch_url) { "#{base_url}/v7/finance/quote?symbols=MSFT&crumb=#{crumb}" }
      let(:cached_aapl) do
        { symbol: "AAPL", name: "Apple Inc.", price: 150.0, change: 1.5,
          percent_change: 1.0, volume: 100_000, pe_ratio: 25.5, eps: 5.88,
          dividend: 0.96, dividend_yield: 0.64, payout_ratio: 16.33,
          ma50: 148.5, ma200: 145.0, fifty_two_week_high: 180.0, fifty_two_week_low: 120.0,
          ex_dividend_date: Date.new(2024, 3, 14), dividend_date: nil }
      end
      let(:response_body) do
        {
          "quoteResponse" => {
            "result" => [
              {
                "symbol" => "MSFT", "shortName" => "Microsoft Corp.",
                "regularMarketPrice" => 380.0, "regularMarketChange" => 2.0,
                "regularMarketChangePercent" => 0.53, "regularMarketVolume" => 90_000,
                "trailingPE" => 35.0, "epsTrailingTwelveMonths" => 10.86,
                "dividendRate" => 3.0, "fiftyDayAverage" => 375.0,
                "twoHundredDayAverage" => 360.0, "fiftyTwoWeekHigh" => 420.0,
                "fiftyTwoWeekLow" => 310.0, "exDividendDate" => 1_715_644_800
              }
            ]
          }
        }.to_json
      end

      before do
        described_class.instance_variable_set(
          :@cache,
          { "quote_AAPL" => { data: cached_aapl, timestamp: Time.now } }
        )
        stub_request(:get, batch_url)
          .to_return(status: 200, body: response_body)
      end

      it "uses cache for cached symbols and fetches only uncached ones" do
        result = described_class.get_quotes(symbols)
        expect(result["AAPL"]).to eq(cached_aapl)
        expect(result["MSFT"][:price]).to eq(380.0)
      end
    end

    context "when symbols exceed BATCH_SIZE" do
      let(:symbols) { (1..55).map { |i| "SYM#{i}" } }

      before do
        batch1_symbols = symbols[0...50].join(",")
        batch2_symbols = symbols[50...55].join(",")

        batch1_results = symbols[0...50].map do |sym|
          { "symbol" => sym, "shortName" => sym, "regularMarketPrice" => 100.0,
            "regularMarketChange" => 0, "regularMarketChangePercent" => 0,
            "regularMarketVolume" => 1000, "trailingPE" => nil,
            "epsTrailingTwelveMonths" => nil, "fiftyDayAverage" => nil,
            "twoHundredDayAverage" => nil }
        end

        batch2_results = symbols[50...55].map do |sym|
          { "symbol" => sym, "shortName" => sym, "regularMarketPrice" => 200.0,
            "regularMarketChange" => 0, "regularMarketChangePercent" => 0,
            "regularMarketVolume" => 1000, "trailingPE" => nil,
            "epsTrailingTwelveMonths" => nil, "fiftyDayAverage" => nil,
            "twoHundredDayAverage" => nil }
        end

        stub_request(:get, "#{base_url}/v7/finance/quote?symbols=#{batch1_symbols}&crumb=#{crumb}")
          .to_return(status: 200, body: { "quoteResponse" => { "result" => batch1_results } }.to_json)
        stub_request(:get, "#{base_url}/v7/finance/quote?symbols=#{batch2_symbols}&crumb=#{crumb}")
          .to_return(status: 200, body: { "quoteResponse" => { "result" => batch2_results } }.to_json)
      end

      it "splits into multiple batches" do
        result = described_class.get_quotes(symbols)
        expect(result.size).to eq(55)
        expect(result["SYM1"][:price]).to eq(100.0)
        expect(result["SYM51"][:price]).to eq(200.0)
      end
    end

    context "when symbols is empty" do
      it "returns an empty hash" do
        expect(described_class.get_quotes([])).to eq({})
      end
    end

    context "when symbols is nil" do
      it "returns an empty hash" do
        expect(described_class.get_quotes(nil)).to eq({})
      end
    end

    context "when authentication fails and retries succeed" do
      let(:symbols) { %w[AAPL] }
      let(:batch_url) { "#{base_url}/v7/finance/quote?symbols=AAPL&crumb=#{crumb}" }
      let(:response_body) do
        {
          "quoteResponse" => {
            "result" => [
              {
                "symbol" => "AAPL", "shortName" => "Apple Inc.",
                "regularMarketPrice" => 150.0, "regularMarketChange" => 1.5,
                "regularMarketChangePercent" => 1.0, "regularMarketVolume" => 100_000,
                "trailingPE" => 25.5, "epsTrailingTwelveMonths" => 5.88,
                "dividendRate" => 0.96, "fiftyDayAverage" => 148.5,
                "twoHundredDayAverage" => 145.0, "fiftyTwoWeekHigh" => 180.0,
                "fiftyTwoWeekLow" => 120.0, "exDividendDate" => 1_710_374_400
              }
            ]
          }
        }.to_json
      end

      before do
        stub_request(:get, batch_url)
          .to_return(
            { status: 200, body: '{"error": "Invalid Cookie"}' },
            { status: 200, body: response_body }
          )
      end

      it "retries and returns the quote data" do
        result = described_class.get_quotes(symbols)
        expect(result["AAPL"][:price]).to eq(150.0)
      end
    end

    context "when authentication fails after max retries" do
      let(:symbols) { %w[AAPL MSFT] }
      let(:batch_url) { "#{base_url}/v7/finance/quote?symbols=AAPL,MSFT&crumb=#{crumb}" }

      before do
        stub_request(:get, batch_url)
          .to_return(status: 401, body: "Unauthorized")
      end

      it "returns error for all symbols" do
        result = described_class.get_quotes(symbols)
        expect(result["AAPL"]).to eq(error: "Authentication failed after 2 retries")
        expect(result["MSFT"]).to eq(error: "Authentication failed after 2 retries")
      end
    end
  end

  describe ".get_dividend_history" do
    let(:symbol) { "AAPL" }
    let(:base_url) { "https://query1.finance.yahoo.com" }
    let(:chart_url) { "#{base_url}/v8/finance/chart/#{symbol}?range=2y&interval=1mo&events=div&crumb=#{crumb}" }
    let(:cookie_url) { "https://fc.yahoo.com" }
    let(:crumb_url) { "https://query1.finance.yahoo.com/v1/test/getcrumb" }
    let(:cookie) { "test_cookie" }
    let(:crumb) { "test_crumb" }
    let(:session) { YahooFinanceClient::Session.instance }

    before do
      described_class.instance_variable_set(:@cache, {})
      session.send(:reset!)
      stub_request(:get, cookie_url)
        .to_return(status: 200, headers: { "set-cookie" => cookie })
      stub_request(:get, crumb_url)
        .with(headers: { "Cookie" => cookie })
        .to_return(status: 200, body: crumb)
    end

    context "when dividends exist" do
      let(:response_body) do
        {
          "chart" => {
            "result" => [
              {
                "events" => {
                  "dividends" => {
                    "1707955200" => { "date" => 1_707_955_200, "amount" => 0.24 },
                    "1715644800" => { "date" => 1_715_644_800, "amount" => 0.25 },
                    "1723420800" => { "date" => 1_723_420_800, "amount" => 0.25 },
                    "1731196800" => { "date" => 1_731_196_800, "amount" => 0.25 }
                  }
                }
              }
            ]
          }
        }.to_json
      end

      before do
        stub_request(:get, chart_url)
          .to_return(status: 200, body: response_body)
      end

      it "returns sorted array of dividend events" do
        result = described_class.get_dividend_history(symbol)
        expect(result).to be_an(Array)
        expect(result.size).to eq(4)
        expect(result.first[:date]).to be_a(Date)
        expect(result.first[:amount]).to eq(0.24)
        expect(result.last[:amount]).to eq(0.25)
      end

      it "returns dates sorted chronologically" do
        result = described_class.get_dividend_history(symbol)
        dates = result.map { |d| d[:date] }
        expect(dates).to eq(dates.sort)
      end

      it "caches the result" do
        described_class.get_dividend_history(symbol)
        cache = described_class.instance_variable_get(:@cache)
        expect(cache["div_history_#{symbol}_2y"]).not_to be_nil
      end
    end

    context "when no dividends exist" do
      let(:response_body) do
        {
          "chart" => {
            "result" => [
              {
                "events" => {}
              }
            ]
          }
        }.to_json
      end

      before do
        stub_request(:get, chart_url)
          .to_return(status: 200, body: response_body)
      end

      it "returns empty array" do
        result = described_class.get_dividend_history(symbol)
        expect(result).to eq([])
      end
    end

    context "when API returns error" do
      before do
        stub_request(:get, chart_url)
          .to_return(status: 500, body: "")
      end

      it "returns empty array" do
        result = described_class.get_dividend_history(symbol)
        expect(result).to eq([])
      end
    end

    context "when authentication fails after max retries" do
      before do
        stub_request(:get, chart_url)
          .to_return(status: 401, body: "Unauthorized")
      end

      it "returns empty array" do
        result = described_class.get_dividend_history(symbol)
        expect(result).to eq([])
      end
    end

    context "with custom range parameter" do
      let(:chart_url_1y) { "#{base_url}/v8/finance/chart/#{symbol}?range=1y&interval=1mo&events=div&crumb=#{crumb}" }
      let(:response_body) do
        {
          "chart" => {
            "result" => [
              {
                "events" => {
                  "dividends" => {
                    "1715644800" => { "date" => 1_715_644_800, "amount" => 0.25 }
                  }
                }
              }
            ]
          }
        }.to_json
      end

      before do
        stub_request(:get, chart_url_1y)
          .to_return(status: 200, body: response_body)
      end

      it "uses the specified range" do
        result = described_class.get_dividend_history(symbol, range: "1y")
        expect(result.size).to eq(1)
      end
    end
  end
end
