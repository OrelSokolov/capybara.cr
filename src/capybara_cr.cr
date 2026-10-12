# Capybara P0 port (capybara 3.40.0): system-test DSL on top of a
# minimal CDP (Chrome DevTools Protocol) client. See shard.yml for the
# covered subset and PLAN.md for deviations.

module Capybara
  # Capybara.default_max_wait_time analog: how long has_*? / find poll
  # for the condition before giving up.
  class_property default_wait_time : Time::Span = 2.seconds

  def self.browser_binary : String?
    ENV["CHROMIUM_BIN"]? || {"chromium", "chromium-browser", "google-chrome",
                             "google-chrome-stable"}.find do |name|
      Process.find_executable(name)
    end
  end

  class ElementNotFoundError < Exception
    def initialize(selector : String)
      super("Unable to find visible element matching \"#{selector}\"")
    end
  end
end

require "./capybara/chromium_driver"
require "./capybara/session"
