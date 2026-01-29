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
                "twoHundredDayAverage" => 145.0
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
          ma200: 145.0
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
          ma200: 145.0
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
          ma200: 145.0
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
                "twoHundredDayAverage" => 147.0
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
          ma200: 147.0
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
                "twoHundredDayAverage" => 135.0
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
          ma200: 135.0
        )
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
                "twoHundredDayAverage" => 180.0
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
          ma200: 180.0
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
                "twoHundredDayAverage" => 145.0
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
          ma200: 145.0
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
                "twoHundredDayAverage" => 145.0
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
          ma200: 145.0
        )
      end
    end
  end
end
