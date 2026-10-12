# ChromiumDriver — minimal CDP client over the stdlib websocket: launches
# headless Chromium with a throwaway profile, opens one page target and
# speaks Runtime.evaluate / Page.navigate / Page.captureScreenshot.
# This replaces selenium-webdriver for the port (no external deps).

require "http"
require "json"
require "base64"

class Capybara::ChromiumDriver
  getter process : Process
  getter socket : HTTP::WebSocket
  getter user_data_dir : String

  @msg_id : Int32 = 0
  @inbox : Channel(JSON::Any)

  # Raises when no Chromium binary is installed (mirror specs skip on
  # this — set CHROMIUM_BIN to point at one explicitly).
  def self.available? : Bool
    !Capybara.browser_binary.nil?
  end

  def initialize(binary : String? = nil)
    bin = binary || Capybara.browser_binary
    raise "No Chromium binary found (chromium/google-chrome; or set CHROMIUM_BIN)" unless bin

    @user_data_dir = File.join(Dir.tempdir,
      "capybara-profile-#{Random::Secure.hex(8)}")
    Dir.mkdir_p(@user_data_dir)

    @process = Process.new(bin, [
      "--headless=new",
      "--remote-debugging-port=0", # ephemeral port, printed on stderr
      "--user-data-dir=#{@user_data_dir}",
      "--no-sandbox",
      "--disable-dev-shm-usage",
      "--disable-gpu",
      "--hide-scrollbars",
      "about:blank",
    ], output: Process::Redirect::Pipe, error: Process::Redirect::Pipe)

    browser_ws = wait_for_devtools
    page_ws = create_page_target(browser_ws)

    @socket = HTTP::WebSocket.new(URI.parse(page_ws))
    @inbox = Channel(JSON::Any).new
    spawn(name: "capybara-cdp-reader") do
      @socket.on_message do |message|
        @inbox.send(JSON.parse(message))
      end
      @socket.run
      @inbox.close
    end

    command("Runtime.enable")
    command("Page.enable")
  end

  def close : Nil
    @process.terminate rescue nil
  end

  # --- CDP surface used by Session -------------------------------------

  # Navigates and waits for the document to settle (readyState
  # complete) — Capybara's visit waits for load by default.
  def visit(url : String) : Nil
    command("Page.navigate", {"url" => url})
    wait_for_load
  end

  def wait_for_load(timeout : Time::Span = 10.seconds) : Nil
    deadline = Time.monotonic + timeout
    until ready_state_complete?
      raise "Page did not reach readyState=complete within #{timeout}" if Time.monotonic > deadline
      sleep 25.milliseconds
    end
  end

  # Runs `expression` and returns its JSON value (returnByValue +
  # awaitPromise — evaluate_script semantics of the gem).
  def evaluate(expression : String) : JSON::Any?
    result = command("Runtime.evaluate", {
      "expression"    => expression,
      "returnByValue" => true,
      "awaitPromise"  => true,
    })
    if details = result.dig?("exceptionDetails")
      raise "JS evaluation failed: #{details}"
    end
    result.dig?("result", "value") || JSON::Any.new(nil)
  end

  def execute_script(script : String) : Nil
    evaluate(script)
  end

  def screenshot(path : String) : Nil
    result = command("Page.captureScreenshot", {"format" => "png"})
    File.write(path, Base64.decode(result["data"].as_s))
  end

  # --- internals ---------------------------------------------------------

  private def ready_state_complete? : Bool
    evaluate("document.readyState").try(&.as_s?) == "complete"
  end

  # Blocks until Chromium reports its DevTools websocket endpoint.
  private def wait_for_devtools : String
    deadline = Time.monotonic + 15.seconds
    loop do
      line = @process.error.gets
      if line.nil? # chromium died
        raise "Chromium exited before exposing DevTools (exit code #{@process.wait.exit_code?})"
      end
      if pos = line.index("DevTools listening on ")
        return line[(pos + "DevTools listening on ".size)..].strip
      end
      raise "Chromium DevTools wait exceeded 15s" if Time.monotonic > deadline
    end
  end

  # /json/new creates a fresh page target; modern Chromium requires PUT.
  private def create_page_target(browser_ws : String) : String
    uri = URI.parse(browser_ws)
    response = HTTP::Client.new(uri.host.not_nil!, uri.port.not_nil!) do |client|
      client.put("/json/new")
    end
    raise "Failed to create CDP page target: #{response.status_code}" unless response.status.success?
    JSON.parse(response.body)["webSocketDebuggerUrl"].as_s
  end

  private def command(method : String, params : Hash(String, JSON::Any | String | Bool)? = nil) : JSON::Any
    @msg_id += 1
    id = @msg_id
    payload = {"id" => id, "method" => method}
    payload = payload.merge({"params" => params}) if params
    @socket.send(payload.to_json)
    loop do
      message = @inbox.receive
      next unless message["id"]?.try(&.as_i?) == id
      if error = message["error"]?
        raise "CDP error in #{method}: #{error["message"]?}"
      end
      return message["result"]? || JSON::Any.new(nil)
    end
  end
end
