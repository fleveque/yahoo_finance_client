# frozen_string_literal: true

require "spec_helper"
require "webmock/rspec"

RSpec.describe YahooFinanceClient::Session do
  let(:session) { described_class.instance }
  let(:cookie) { "A1=abc123; path=/;" }
  let(:crumb) { "validCrumb123" }

  before do
    # Reset singleton state before each test
    session.send(:reset!)
  end

  describe "#ensure_authenticated" do
    context "when strategy 1 (fc.yahoo.com + query1) succeeds" do
      before do
        stub_request(:get, "https://fc.yahoo.com")
          .to_return(status: 200, headers: { "set-cookie" => cookie })
        stub_request(:get, "https://query1.finance.yahoo.com/v1/test/getcrumb")
          .with(headers: { "Cookie" => cookie })
          .to_return(status: 200, body: crumb)
      end

      it "authenticates successfully" do
        session.ensure_authenticated
        expect(session.cookie).to eq(cookie)
        expect(session.crumb).to eq(crumb)
        expect(session.base_url).to eq("https://query1.finance.yahoo.com")
      end

      it "sets a valid session" do
        session.ensure_authenticated
        expect(session.valid_session?).to be true
      end
    end

    context "when strategy 1 fails but strategy 2 (homepage scraping) succeeds" do
      before do
        # Strategy 1 fails
        stub_request(:get, "https://fc.yahoo.com")
          .to_return(status: 200, headers: { "set-cookie" => cookie })
        stub_request(:get, "https://query1.finance.yahoo.com/v1/test/getcrumb")
          .with(headers: { "Cookie" => cookie })
          .to_return(status: 401, body: "Unauthorized")

        # Strategy 2 succeeds
        homepage_html = '<script>window.config = {"crumb":"homepageCrumb456"};</script>'
        stub_request(:get, "https://finance.yahoo.com")
          .to_return(status: 200, body: homepage_html, headers: { "set-cookie" => "homepage_cookie" })
      end

      it "falls back to homepage scraping" do
        session.ensure_authenticated
        expect(session.cookie).to eq("homepage_cookie")
        expect(session.crumb).to eq("homepageCrumb456")
      end
    end

    context "when strategies 1 and 2 fail but strategy 3 (query2) succeeds" do
      before do
        # Strategy 1 fails - crumb request fails
        stub_request(:get, "https://fc.yahoo.com")
          .to_return(status: 200, headers: { "set-cookie" => cookie })
        stub_request(:get, "https://query1.finance.yahoo.com/v1/test/getcrumb")
          .to_return(status: 401, body: "Unauthorized")

        # Strategy 2 fails - homepage doesn't have crumb
        stub_request(:get, "https://finance.yahoo.com")
          .to_return(status: 200, body: "<html>no crumb here</html>", headers: { "set-cookie" => "homepage_cookie" })

        # Strategy 3 succeeds
        stub_request(:get, "https://query2.finance.yahoo.com/v1/test/getcrumb")
          .to_return(status: 200, body: crumb)
      end

      it "falls back to query2 domain" do
        session.ensure_authenticated
        expect(session.base_url).to eq("https://query2.finance.yahoo.com")
        expect(session.crumb).to eq(crumb)
      end
    end

    context "when all strategies fail" do
      before do
        stub_request(:get, "https://fc.yahoo.com")
          .to_return(status: 200, headers: {})
        stub_request(:get, "https://finance.yahoo.com")
          .to_return(status: 500, body: "")
        stub_request(:get, "https://query2.finance.yahoo.com/v1/test/getcrumb")
          .to_return(status: 401, body: "Unauthorized")
      end

      it "raises AuthenticationError" do
        expect { session.ensure_authenticated }.to raise_error(YahooFinanceClient::AuthenticationError)
      end
    end
  end

  describe "#valid_session?" do
    context "when not authenticated" do
      it "returns false" do
        expect(session.valid_session?).to be false
      end
    end

    context "when authenticated" do
      before do
        stub_request(:get, "https://fc.yahoo.com")
          .to_return(status: 200, headers: { "set-cookie" => cookie })
        stub_request(:get, "https://query1.finance.yahoo.com/v1/test/getcrumb")
          .with(headers: { "Cookie" => cookie })
          .to_return(status: 200, body: crumb)
        session.ensure_authenticated
      end

      it "returns true" do
        expect(session.valid_session?).to be true
      end
    end

    context "when session has expired" do
      before do
        stub_request(:get, "https://fc.yahoo.com")
          .to_return(status: 200, headers: { "set-cookie" => cookie })
        stub_request(:get, "https://query1.finance.yahoo.com/v1/test/getcrumb")
          .with(headers: { "Cookie" => cookie })
          .to_return(status: 200, body: crumb)
        session.ensure_authenticated

        # Simulate time passing beyond SESSION_TTL
        session.instance_variable_set(:@authenticated_at, Time.now - (described_class::SESSION_TTL + 1))
      end

      it "returns false" do
        expect(session.valid_session?).to be false
      end
    end
  end

  describe "#invalidate!" do
    before do
      stub_request(:get, "https://fc.yahoo.com")
        .to_return(status: 200, headers: { "set-cookie" => cookie })
      stub_request(:get, "https://query1.finance.yahoo.com/v1/test/getcrumb")
        .with(headers: { "Cookie" => cookie })
        .to_return(status: 200, body: crumb)
      session.ensure_authenticated
    end

    it "clears the session" do
      expect(session.valid_session?).to be true
      session.invalidate!
      expect(session.valid_session?).to be false
      expect(session.cookie).to be_nil
      expect(session.crumb).to be_nil
    end
  end

  describe "crumb extraction from homepage" do
    let(:homepage_cookie) { "homepage_session=xyz" }

    before do
      # Strategy 1 fails
      stub_request(:get, "https://fc.yahoo.com")
        .to_return(status: 200, headers: { "set-cookie" => cookie })
      stub_request(:get, "https://query1.finance.yahoo.com/v1/test/getcrumb")
        .to_return(status: 401, body: "Unauthorized")
    end

    context "with standard crumb format" do
      let(:html) { '<script>{"crumb":"abc123def"}</script>' }

      before do
        stub_request(:get, "https://finance.yahoo.com")
          .to_return(status: 200, body: html, headers: { "set-cookie" => homepage_cookie })
      end

      it "extracts the crumb" do
        session.ensure_authenticated
        expect(session.crumb).to eq("abc123def")
      end
    end

    context "with unicode-escaped crumb" do
      let(:html) { '<script>{"crumb":"abc\\u002Fdef\\u002Fghi"}</script>' }

      before do
        stub_request(:get, "https://finance.yahoo.com")
          .to_return(status: 200, body: html, headers: { "set-cookie" => homepage_cookie })
      end

      it "decodes unicode escapes" do
        session.ensure_authenticated
        expect(session.crumb).to eq("abc/def/ghi")
      end
    end
  end
end
