# Mirror of oracle/capybara_expected.yml (captured from the real
# capybara 3.40.0 + selenium-webdriver headless Chrome via
# oracle/capybara_cases.rb against a fixed Rack demo app). Same case
# IDs, same expectations, no edits on either side. The CRails demo app
# below serves the same routes and byte-identical HTML as the oracle's
# Rack app; the port drives it through Capybara::ChromiumDriver (CDP).
#
# Skips gracefully when no Chromium binary is present (like the
# SSH_ORACLE_LIVE gating in net_ssh.cr): set CHROMIUM_BIN to override.

require "spec"
require "../src/capybara_cr"
require "railties_cr"

CAPYBARA_EXPECTED = begin
  hash = {} of String => String
  File.read("#{__DIR__}/../oracle/capybara_expected.yml").each_line do |line|
    next unless line.includes?('\t')
    id, value = line.split('\t', 2)
    hash[id] = value.chomp
  end
  hash
end

# --- the demo app (byte-identical HTML to the oracle's Rack app) ------

HOME_HTML = <<-HTML
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

NEXT_HTML = <<-HTML
<!doctype html>
<html>
  <head><title>Next page</title></head>
  <body>
    <h1>Next page</h1>
    <a id="back-link" href="/">Go back</a>
  </body>
</html>
HTML

def greet_html(name : String) : String
  String.build do |io|
    io << "<!doctype html>\n"
    io << "<html>\n"
    io << "  <head><title>Greeting</title></head>\n"
    io << "  <body>\n"
    io << "    <h1>Hello, #{name}!</h1>\n"
    io << "  </body>\n"
    io << "</html>\n"
  end
end

class DemoController < ActionController::Base
  def home
    render html: HOME_HTML
  end

  def next_page
    render html: NEXT_HTML
  end

  def greet
    render html: greet_html(params["name"].to_s)
  end
end

APP_CAPYBARA = CRails::Application.new.tap do |app|
  app.routes.draw do
    get "/", to: "demo#home"
    get "/next", to: "demo#next_page"
    get "/greet", to: "demo#greet"
  end
end

unless Capybara::ChromiumDriver.available?
  STDERR.puts "Skipping capybara oracle mirror: no chromium binary (set CHROMIUM_BIN)"
  exit 0
end

# Constants keep the driver/socket rooted while the spec suite (which
# runs from its own at_exit handler) executes, and after_suite closes
# everything explicitly.
module SpecEnv
  class_property server : HTTP::Server?
end

ADDR = begin
  server = HTTP::Server.new { |ctx| APP_CAPYBARA.call(ctx) }
  address = server.bind_tcp("127.0.0.1", 0)
  spawn { server.listen }
  sleep 50.milliseconds
  SpecEnv.server = server
  address
end

DRIVER = Capybara::ChromiumDriver.new
PAGE = Capybara::Session.new(DRIVER, "http://#{ADDR}")

Spec.after_suite do
  DRIVER.close
  SpecEnv.server.try &.close
end

describe "capybara port (capybara 3.40.0 oracle)" do
  it "visit_root" do
    PAGE.visit "/"
    "#{URI.parse(PAGE.current_url).path}|#{PAGE.title}|#{PAGE.find("h1").text}"
      .should eq CAPYBARA_EXPECTED["visit_root"]
  end

  it "click_link" do
    PAGE.visit "/"
    PAGE.click_link "Go next"
    "#{URI.parse(PAGE.current_url).path}|#{PAGE.title}|#{PAGE.find("h1").text}"
      .should eq CAPYBARA_EXPECTED["click_link"]
  end

  it "fill_in_submit" do
    PAGE.visit "/"
    PAGE.fill_in "Name", with: "Crystal"
    PAGE.click_button "Submit"
    "#{URI.parse(PAGE.current_url).path}|#{PAGE.find("h1").text}"
      .should eq CAPYBARA_EXPECTED["fill_in_submit"]
  end

  it "has_content" do
    PAGE.visit "/"
    "#{PAGE.has_content?("Welcome")},#{PAGE.has_content?("Nope")}"
      .should eq CAPYBARA_EXPECTED["has_content"]
  end

  it "selector_count" do
    PAGE.visit "/"
    PAGE.all(".item").size.to_s.should eq CAPYBARA_EXPECTED["selector_count"]
  end

  it "attribute" do
    PAGE.visit "/"
    URI.parse(PAGE.find("#next-link")["href"].to_s).path
      .should eq CAPYBARA_EXPECTED["attribute"]
  end

  it "evaluate_script" do
    PAGE.visit "/"
    PAGE.evaluate_script("2 + 2").to_s.should eq CAPYBARA_EXPECTED["evaluate_script"]
  end

  it "wait_reveal" do
    PAGE.visit "/"
    PAGE.click_button "Reveal"
    PAGE.has_content?("appeared").to_s.should eq CAPYBARA_EXPECTED["wait_reveal"]
  end

  it "go_back_forward" do
    PAGE.visit "/"
    PAGE.click_link "Go next"
    PAGE.go_back
    back = "#{URI.parse(PAGE.current_url).path}|#{PAGE.find("h1").text}"
    PAGE.go_forward
    "#{back}||#{URI.parse(PAGE.current_url).path}|#{PAGE.find("h1").text}"
      .should eq CAPYBARA_EXPECTED["go_back_forward"]
  end

  it "screenshot" do
    PAGE.visit "/"
    path = "/tmp/capybara_mirror_screenshot.png"
    File.delete(path) if File.exists?(path)
    PAGE.save_screenshot(path)
    result = File.exists?(path) && File.size(path) > 0 ? "present" : "missing"
    result.should eq CAPYBARA_EXPECTED["screenshot"]
  end
end

