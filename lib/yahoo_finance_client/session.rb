# frozen_string_literal: true

require "httparty"
require "singleton"

module YahooFinanceClient
  # Handles Yahoo Finance authentication with multiple fallback strategies
  class Session
    include Singleton

    SESSION_TTL = 60
    USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0"
    COOKIE_URL = "https://fc.yahoo.com"
    CRUMB_URL_QUERY1 = "https://query1.finance.yahoo.com/v1/test/getcrumb"
    CRUMB_URL_QUERY2 = "https://query2.finance.yahoo.com/v1/test/getcrumb"
    HOMEPAGE_URL = "https://finance.yahoo.com"
    CRUMB_PATTERNS = [/"crumb"\s*:\s*"([^"]+)"/, /"CrsrfToken"\s*:\s*"([^"]+)"/, /crumb=([a-zA-Z0-9_.~-]+)/].freeze

    attr_reader :cookie, :crumb, :base_url

    def initialize
      reset!
    end

    def ensure_authenticated
      return if valid_session?

      authenticate!
    end

    def invalidate!
      reset!
    end

    def valid_session?
      return false unless @cookie && @crumb && @authenticated_at

      Time.now - @authenticated_at < SESSION_TTL
    end

    private

    def reset!
      @cookie = nil
      @crumb = nil
      @authenticated_at = nil
      @base_url = "https://query1.finance.yahoo.com"
    end

    def authenticate!
      strategies = %i[strategy_fc_cookie_query1 strategy_homepage_scrape strategy_fc_cookie_query2]
      strategies.each { |s| return @authenticated_at = Time.now if send(s) rescue nil } # rubocop:disable Style/RescueModifier
      raise AuthenticationError, "All authentication strategies failed"
    end

    def strategy_fc_cookie_query1
      apply_crumb_strategy(fetch_cookie_from_fc, CRUMB_URL_QUERY1, "https://query1.finance.yahoo.com")
    end

    def strategy_fc_cookie_query2
      apply_crumb_strategy(fetch_cookie_from_fc, CRUMB_URL_QUERY2, "https://query2.finance.yahoo.com")
    end

    def apply_crumb_strategy(cookie, crumb_url, base)
      return false unless cookie

      crumb = fetch_crumb(cookie, crumb_url)
      return false unless valid_crumb?(crumb)

      @cookie = cookie
      @crumb = crumb
      @base_url = base
      true
    end

    def strategy_homepage_scrape
      response = HTTParty.get(HOMEPAGE_URL, headers: request_headers, follow_redirects: true)
      return false unless response.success?

      cookie = extract_cookie(response)
      crumb = extract_crumb_from_html(response.body)
      return false unless cookie && crumb

      @cookie = cookie
      @crumb = crumb
      @base_url = "https://query1.finance.yahoo.com"
      true
    end

    def fetch_cookie_from_fc
      extract_cookie(HTTParty.get(COOKIE_URL, headers: request_headers))
    end

    def fetch_crumb(cookie, crumb_url)
      response = HTTParty.get(crumb_url, headers: request_headers.merge("Cookie" => cookie))
      response.success? ? response.body.strip : nil
    end

    def extract_cookie(response)
      response.headers["set-cookie"]&.to_s
    end

    def extract_crumb_from_html(html)
      CRUMB_PATTERNS.each { |p| (m = html.match(p)) && (return unescape_crumb(m[1])) }
      nil
    end

    def unescape_crumb(crumb)
      crumb.gsub(/\\u([0-9a-fA-F]{4})/) { [::Regexp.last_match(1).to_i(16)].pack("U") }
    end

    def valid_crumb?(crumb)
      crumb && !crumb.empty? && !crumb.include?("<") && !crumb.include?("Unauthorized")
    end

    def request_headers
      { "User-Agent" => USER_AGENT, "Accept" => "text/html,*/*;q=0.8", "Accept-Language" => "en-US,en;q=0.5" }
    end
  end
end
