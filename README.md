# capybara.cr

A Crystal port of **Capybara 3.40.0** (P0 scope) — browser-level system
testing for CRails applications, built on a minimal homegrown CDP client
(Chrome DevTools Protocol) over the stdlib `HTTP::WebSocket`, with no
external dependencies (a replacement for selenium-webdriver). Request-
level testing without a browser is covered separately by
`ActionDispatch::IntegrationSession` in railties.cr.

> ⚠️ EXPERIMENTAL — DO NOT USE IN PRODUCTION YET.

## Installation

```yaml
dependencies:
  capybara_cr:
    github: OrelSokolov/capybara.cr
```

```sh
shards install
```

The port itself is pure stdlib; `railties_cr` is needed only by the
specs (demo app).

## Usage

```crystal
session = Capybara::Session.new(
  Capybara::ChromiumDriver.new,
  base_url: "http://127.0.0.1:3000"
)

session.visit "/posts"
session.click_link "New Post"
session.fill_in "Title", with: "Hello"
session.click_button "Create"
session.has_content?("Post was successfully created") # => true (waits)
session.save_screenshot("tmp/screenshot.png")
```

Chromium binary: `CHROMIUM_BIN` or auto-detection of
chromium/chromium-browser/google-chrome[-stable]; launched headless
(`--headless=new --remote-debugging-port=0`, throwaway user-data-dir).

## Feature comparison vs capybara 3.40.0

| Feature | Original (capybara) | Port (capybara.cr) | Status |
|---|---|---|---|
| Drivers: rack_test | ✅ | Not ported — request-level is `ActionDispatch::IntegrationSession` (railties.cr) | ❌ (equivalent: integration session) |
| Drivers: selenium | ✅ | `Capybara::ChromiumDriver` — own CDP client: page target, `Page.navigate`, `Runtime.evaluate` (returnByValue + awaitPromise), `Page.captureScreenshot`, readiness polling on `document.readyState` | 🔶 |
| `visit` / `current_path` / `current_url` / `title` | ✅ | Same | ✅ |
| `click_link` / `click_button` (id / exact text / aria-label, substring fallback) | ✅ | Click is a JS `el.click()`, not trusted `Input.dispatchMouseEvent` events | 🔶 |
| `fill_in(locator, with:)` (label[for] → id/name/placeholder) | ✅ | Same | ✅ |
| `find` / `all` → `Node` (`.text`, `[](attr)`, `.click`, `.set`) | ✅ | Nodes pinned via an internal `data-capybara-node` attribute instead of backend RemoteObject handles | 🔶 |
| `has_content?` / `has_no_content?` / `has_selector?` with waiting | ✅ | Polling up to `Capybara.default_wait_time` (2 s), like the gem's `default_max_wait_time` | ✅ |
| `evaluate_script` / `execute_script` | ✅ | Same | ✅ |
| `go_back` / `go_forward` | ✅ | Same | ✅ |
| `save_screenshot` | ✅ | Same | ✅ |
| `Capybara.app_host` | ✅ | `base_url` on the session; `visit("/path")` navigates the browser to the real HTTP server | 🔶 |
| `select` / `check` / `uncheck` / `attach_file`, `within`, windows/iframes, `match`/text locator options, modal dialogs, `save_and_open_page`, JS errors raised in `has_*` | ✅ | Not ported | ⬜ |

## Deviations & Crystal-specific notes

- No external shards: CDP over stdlib websockets; chromedriver is not
  used at all.
- `has_*`/`find` wait semantics match the gem; non-waiting assertions
  (`has_content?` in the gem's non-waiting form) always poll.

## Testing

```sh
crystal spec
```

Oracle: `oracle/capybara_cases.rb` runs a mini Rack app with fixed HTML
through the real capybara 3.40.0 + selenium-webdriver (headless Chrome) —
10 cases (visit, click_link, fill_in+submit, has_content true/false,
item count, href attribute, evaluate_script, async content appearing
after 300 ms, go_back/forward, screenshot). The mirror
`spec/capybara_spec.cr` runs a CRails app with byte-identical HTML —
10/10. The spec skips cleanly when no chromium binary is available.
Regenerate the oracle with
`PATH=/usr/bin:/bin ruby oracle/capybara_cases.rb > oracle/capybara_expected.yml`.
