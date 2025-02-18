# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe YahooFinanceClient::Stock do
  describe ".get_quote" do
    let(:symbol) { "AAPL" }
    let(:quote_url) { "https://query1.finance.yahoo.com/v7/finance/quote?symbols=#{symbol}&crumb=test_crumb" }
    let(:cookie_url) { "https://fc.yahoo.com" }
    let(:crumb_url) { "https://query1.finance.yahoo.com/v1/test/getcrumb" }
    let(:cookie) { "test_cookie" }
    let(:crumb) { "test_crumb" }
    let(:cache_key) { "quote_#{symbol}" }

    before do
      described_class.instance_variable_set(:@cache, {}) # Clear the cache
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
                "regularMarketPrice" => 150.0,
                "regularMarketChange" => 1.5,
                "regularMarketChangePercent" => 1.0,
                "regularMarketVolume" => 100_000
              }
            ]
          }
        }.to_json
      end

      before do
        stub_request(:get, quote_url)
          .to_return(status: 200, body: response_body)
      end

      it "returns the quote data" do
        result = described_class.get_quote(symbol)
        expect(result).to eq(
          symbol: "AAPL",
          price: 150.0,
          change: 1.5,
          percent_change: 1.0,
          volume: 100_000
        )
      end

      it "caches the quote data" do
        described_class.get_quote(symbol)
        cache = described_class.instance_variable_get(:@cache)
        expect(cache[cache_key][:data]).to eq(
          symbol: "AAPL",
          price: 150.0,
          change: 1.5,
          percent_change: 1.0,
          volume: 100_000
        )
      end
    end

    context "when the response is unsuccessful" do
      before do
        stub_request(:get, quote_url)
          .with(headers: { "User-Agent" => YahooFinanceClient::Stock::USER_AGENT })
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
          price: 150.0,
          change: 1.5,
          percent_change: 1.0,
          volume: 100_000
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
          price: 150.0,
          change: 1.5,
          percent_change: 1.0,
          volume: 100_000
        }
      end

      let(:response_body) do
        {
          "quoteResponse" => {
            "result" => [
              {
                "symbol" => "AAPL",
                "regularMarketPrice" => 150.0,
                "regularMarketChange" => 1.5,
                "regularMarketChangePercent" => 1.0,
                "regularMarketVolume" => 100_000
              }
            ]
          }
        }.to_json
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
        expect(result).to eq(
          symbol: "AAPL",
          price: 150.0,
          change: 1.5,
          percent_change: 1.0,
          volume: 100_000
        )
        cache = described_class.instance_variable_get(:@cache)
        expect(cache[cache_key][:data]).to eq(
          symbol: "AAPL",
          price: 150.0,
          change: 1.5,
          percent_change: 1.0,
          volume: 100_000
        )
      end
    end
  end
end
