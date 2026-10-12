# Capybara::Session / Node — the P0 DSL subset of capybara 3.40.0 on
# top of ChromiumDriver. Locators follow the gem's semantics where P0
# needs them: links/buttons match id, exact text, aria-label (with a
# substring fallback), fill_in matches a label's for-target or the
# field's id/name/placeholder. Nodes are pinned through an internal
# data attribute (deviation: the gem uses backend node handles; DOM
# identity is preserved either way).

module Capybara
  class Node
    getter driver : ChromiumDriver
    getter pin : String # value of data-capybara-node

    def initialize(@driver : ChromiumDriver, @pin : String)
    end

    private def pinned : String
      "[data-capybara-node=\"#{@pin}\"]"
    end

    def text : String
      @driver.evaluate("document.querySelector(#{pinned.to_json}).innerText")
        .try(&.as_s?) || ""
    end

    def [](attribute : String) : String?
      @driver.evaluate(
        "document.querySelector(#{pinned.to_json}).getAttribute(#{attribute.to_json})"
      ).try(&.as_s?)
    end

    # Deviation (P0): JS .click() — not trusted input events
    # (Input.dispatchMouseEvent). Regular onclick handlers and link/
    # button navigation behave the same.
    def click : Nil
      Session.click_and_settle(@driver,
        "document.querySelector(#{pinned.to_json}).click()")
    end

    # fill_in on a located field: sets the value and fires input/change.
    def set(value : String) : Nil
      @driver.evaluate(<<-JS)
        (() => {
          const el = document.querySelector(#{pinned.to_json});
          el.value = #{value.to_json};
          el.dispatchEvent(new Event('input', {bubbles: true}));
          el.dispatchEvent(new Event('change', {bubbles: true}));
        })()
      JS
    end
  end

  class Session
    getter driver : ChromiumDriver
    # Capybara.app_host analog: visit("/foo") resolves against it.
    property base_url : String

    def initialize(@driver : ChromiumDriver, @base_url = "")
    end

    def visit(path : String) : Nil
      url = path.starts_with?("http://") || path.starts_with?("https://") ? path : "#{@base_url}#{path}"
      @driver.visit(url)
    end

    def current_url : String
      @driver.evaluate("location.href").try(&.as_s?) || ""
    end

    def current_path : String
      URI.parse(current_url).path
    end

    def title : String
      @driver.evaluate("document.title").try(&.as_s?) || ""
    end

    # --- queries -----------------------------------------------------------

    def find(selector : String, wait : Time::Span = Capybara.default_wait_time) : Node
      deadline = Time.monotonic + wait
      loop do
        if pin = pin_element(selector)
          return Node.new(@driver, pin)
        end
        raise ElementNotFoundError.new(selector) if Time.monotonic > deadline
        sleep 50.milliseconds
      end
    end

    def all(selector : String) : Array(Node)
      pins = pin_all(selector)
      pins.map { |pin| Node.new(@driver, pin) }
    end

    def has_content?(text : String, wait : Time::Span = Capybara.default_wait_time) : Bool
      wait_until(wait) { body_includes?(text) }
    end

    def has_no_content?(text : String, wait : Time::Span = Capybara.default_wait_time) : Bool
      !wait_until(wait) { body_includes?(text) }
    end

    def has_selector?(selector : String, wait : Time::Span = Capybara.default_wait_time) : Bool
      wait_until(wait) { count(selector) > 0 }
    end

    def count(selector : String) : Int32
      @driver.evaluate("document.querySelectorAll(#{selector.to_json}).length")
        .try(&.as_i?) || 0
    end

    # --- actions ------------------------------------------------------------

    # click_link "Go next" / click_link "next-link"
    def click_link(locator : String) : Nil
      click_matching("a[href]", locator)
    end

    def click_button(locator : String) : Nil
      click_matching("button, input[type=submit], input[type=button]", locator)
    end

    # fill_in "Name", with: "Crystal" — by label text (label[for]),
    # field id, name or placeholder, like the gem's field selector.
    def fill_in(locator : String, with value : String) : Nil
      js = <<-JS
        (() => {
          const l = #{locator.to_json};
          let field = null;
          for (const lab of document.querySelectorAll('label')) {
            if ((lab.textContent || '').trim() === l && lab.htmlFor) {
              field = document.getElementById(lab.htmlFor);
              if (field) break;
            }
          }
          if (!field) {
            for (const f of document.querySelectorAll('input, textarea, select')) {
              if (f.id === l || f.name === l || f.getAttribute('placeholder') === l) {
                field = f;
                break;
              }
            }
          }
          if (!field) return null;
          field.value = #{value.to_json};
          field.dispatchEvent(new Event('input', {bubbles: true}));
          field.dispatchEvent(new Event('change', {bubbles: true}));
          return true;
        })()
      JS
      result = @driver.evaluate(js).try(&.as_bool?)
      raise ElementNotFoundError.new("field \"#{locator}\"") unless result
    end

    def evaluate_script(script : String) : JSON::Any?
      @driver.evaluate(script)
    end

    def execute_script(script : String) : Nil
      @driver.execute_script(script)
    end

    def go_back(wait : Time::Span = Capybara.default_wait_time) : Nil
      travel_history("history.back()", wait)
    end

    def go_forward(wait : Time::Span = Capybara.default_wait_time) : Nil
      travel_history("history.forward()", wait)
    end

    def save_screenshot(path : String) : Nil
      @driver.screenshot(path)
    end

    # --- internals -----------------------------------------------------------

    # Click via JS, then wait a bounded moment for a navigation to
    # start (path change) and for the document to settle. Buttons that
    # only run JS (no navigation) fall through after the settle window.
    def self.click_and_settle(driver : ChromiumDriver, click_js : String) : Nil
      before = driver.evaluate("location.href").try(&.as_s?)
      driver.evaluate(click_js)
      deadline = Time.monotonic + 500.milliseconds
      loop do
        after = driver.evaluate("location.href").try(&.as_s?)
        break if after != before || Time.monotonic > deadline
        sleep 25.milliseconds
      end
      driver.wait_for_load
    end

    private def click_matching(selector : String, locator : String) : Nil
      js = <<-JS
        (() => {
          const l = #{locator.to_json};
          const els = Array.from(document.querySelectorAll(#{selector.to_json}));
          let el = els.find(e => e.id === l || (e.textContent || '').trim() === l ||
                                       (e.getAttribute('aria-label') || '') === l);
          if (!el) el = els.find(e => (e.textContent || '').includes(l));
          if (!el) return null;
          const id = (window.__capybaraNodeCounter = (window.__capybaraNodeCounter || 0) + 1);
          el.setAttribute('data-capybara-node', 'n' + id);
          return 'n' + id;
        })()
      JS
      pin = @driver.evaluate(js).try(&.as_s?)
      raise ElementNotFoundError.new("#{selector} #{locator}") unless pin
      Node.new(@driver, pin).click
    end

    private def pin_element(selector : String) : String?
      js = <<-JS
        (() => {
          const el = document.querySelector(#{selector.to_json});
          if (!el) return null;
          const id = (window.__capybaraNodeCounter = (window.__capybaraNodeCounter || 0) + 1);
          el.setAttribute('data-capybara-node', 'n' + id);
          return 'n' + id;
        })()
      JS
      @driver.evaluate(js).try(&.as_s?)
    end

    private def pin_all(selector : String) : Array(String)
      js = <<-JS
        (() => {
          const pins = [];
          let n = (window.__capybaraNodeCounter || 0);
          for (const el of document.querySelectorAll(#{selector.to_json})) {
            n += 1;
            el.setAttribute('data-capybara-node', 'n' + n);
            pins.push('n' + n);
          }
          window.__capybaraNodeCounter = n;
          return pins;
        })()
      JS
      (@driver.evaluate(js).try(&.as_a?) || [] of JSON::Any).map(&.as_s)
    end

    private def body_includes?(text : String) : Bool
      js = "((document.body ? document.body.innerText : '').indexOf(#{text.to_json}) !== -1)"
      @driver.evaluate(js).try(&.as_bool?) == true
    end

    def wait_until(wait : Time::Span = Capybara.default_wait_time, &block : -> Bool) : Bool
      deadline = Time.monotonic + wait
      loop do
        return true if block.call
        return false if Time.monotonic > deadline
        sleep 50.milliseconds
      end
    end

    private def travel_history(js : String, wait : Time::Span) : Nil
      before = current_url
      @driver.evaluate(js)
      deadline = Time.monotonic + wait
      until current_url != before || Time.monotonic > deadline
        sleep 25.milliseconds
      end
      @driver.wait_for_load
    end
  end
end
