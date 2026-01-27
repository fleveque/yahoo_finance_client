# frozen_string_literal: true

module YahooFinanceClient
  # Base error class for Yahoo Finance Client
  class Error < StandardError; end

  # Raised when authentication fails (invalid cookie/crumb)
  class AuthenticationError < Error; end

  # Raised when Yahoo Finance rate limits requests
  class RateLimitError < Error; end
end
