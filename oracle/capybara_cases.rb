# Oracle cases for the Capybara port (capybara.cr): captured from the
# real capybara 3.40.0 gem driving headless Chrome via selenium-webdriver
# against a fixed inline Rack app. The same HTML is mirrored byte-for-
# byte by the CRails demo app in spec/capybara_spec.cr.
#
# Run (PATH pruned so Selenium Manager picks a chromedriver matching
# the installed google-chrome, not the stale one in ~/.local/bin):
#
#   PATH=/usr/bin:/bin ruby oracle/capybara_cases.rb \
#     > oracle/capybara_expected.yml
#
# Each line: "<case_id>\t<value>" (\n, \t, \r escaped in values).
# Mirrored 1:1 in spec/capybara_spec.cr (ChromiumDriver over CDP).

require "capybara"
abort "need capybara 3.40.0" unless Capybara::VERSION == "3.40.0"
require "capybara/dsl"
require "selenium-webdriver"
require "uri"

# --- the demo app (fixed HTML; the mirror serves the same bytes) -------

HOME_HTML = <<~HTML
  <!doctype html>
  <html>
    <head><title>Welcome</title></head>
    <body>
      <h1>Welcome</h1>
      <p>Stay a while</p>
      <ul>
        <li class="item">one</li>
        <li class="item">two</li>
        <li class="item">three</li>
      </ul>
      <a id="next-link" href="/next">Go next</a>
      <form action="/greet" method="get">
        <label for="name">Name</label>
        <input type="text" id="name" name="name">
        <button type="submit">Submit</button>
      </form>
      <button id="reveal" onclick="setTimeout(function(){document.getElementById('late').textContent='appeared'},300)">Reveal</button>
      <span id="late"></span>
    </body>
  </html>
HTML

NEXT_HTML = <<~HTML
  <!doctype html>
  <html>
    <head><title>Next page</title></head>
    <body>
      <h1>Next page</h1>
      <a id="back-link" href="/">Go back</a>
    </body>
  </html>
HTML

def greet_html(name)
  <<~HTML
    <!doctype html>
    <html>
      <head><title>Greeting</title></head>
      <body>
        <h1>Hello, #{name}!</h1>
      </body>
    </html>
  HTML
end

DEMO_APP = lambda do |env|
  name = Rack::Utils.unescape(env["QUERY_STRING"].to_s[/name=([^&]*)/, 1].to_s)
  body, status =
    case env["PATH_INFO"]
    when "/"      then [HOME_HTML, 200]
    when "/next"  then [NEXT_HTML, 200]
    when "/greet" then [greet_html(name), 200]
    else               ["Not found", 404]
    end
  [status, {"Content-Type" => "text/html"}, [body]]
end

# --- headless chrome ----------------------------------------------------

Capybara.register_driver :oracle_headless do |app|
  options = Selenium::WebDriver::Options.chrome(
    args: ["--headless=new", "--no-sandbox", "--disable-dev-shm-usage"]
  )
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.default_max_wait_time = 2
page = Capybara::Session.new(:oracle_headless, DEMO_APP)

def escape(value)
  value.to_s.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub("\t", "\\t").gsub("\r", "\\r")
end

def case_run(id)
  puts "#{id}\t#{escape(yield)}"
rescue StandardError => e
  puts "#{id}\traise:#{e.class}"
end

# --- transcript ---------------------------------------------------------

case_run("visit_root") do
  page.visit "/"
  "#{URI.parse(page.current_url).path}|#{page.title}|#{page.find("h1").text}"
end

case_run("click_link") do
  page.visit "/"
  page.click_link "Go next"
  "#{URI.parse(page.current_url).path}|#{page.title}|#{page.find("h1").text}"
end

case_run("fill_in_submit") do
  page.visit "/"
  page.fill_in "Name", with: "Crystal"
  page.click_button "Submit"
  "#{URI.parse(page.current_url).path}|#{page.find("h1").text}"
end

case_run("has_content") do
  page.visit "/"
  "#{page.has_content?("Welcome")},#{page.has_content?("Nope")}"
end

case_run("selector_count") do
  page.visit "/"
  page.all(".item").size.to_s
end

case_run("attribute") do
  page.visit "/"
  URI.parse(page.find("#next-link")[:href]).path
end

case_run("evaluate_script") do
  page.visit "/"
  page.evaluate_script("2 + 2").to_s
end

case_run("wait_reveal") do
  page.visit "/"
  page.click_button "Reveal"
  page.has_content?("appeared").to_s
end

case_run("go_back_forward") do
  page.visit "/"
  page.click_link "Go next"
  page.go_back
  back = "#{URI.parse(page.current_url).path}|#{page.find("h1").text}"
  page.go_forward
  "#{back}||#{URI.parse(page.current_url).path}|#{page.find("h1").text}"
end

case_run("screenshot") do
  page.visit "/"
  path = "/tmp/capybara_oracle_screenshot.png"
  page.save_screenshot(path)
  File.exist?(path) && File.size(path).positive? ? "present" : "missing"
end
