# capybara.cr — порт capybara 3.40.0 (P0) + system-тесты для CRails

> Закрывает пробел «аналога ActionDispatch::IntegrationTest и
> Capybara/system-tests нет»: request-уровень —
> `ActionDispatch::IntegrationSession`/`IntegrationTest` в
> `~/rails.cr/railties.cr/src/testing/integration.cr` (см. статус в
> railties.cr/PLAN.md), браузерный уровень — этот шард.

Оригинал: capybara 3.40.0 (`~/.rvm/gems/ruby-3.4.5/gems/capybara-3.40.0`).

## Что вошло (P0)

- `Capybara::ChromiumDriver` — собственный минимальный CDP-клиент
  (Chrome DevTools Protocol) поверх stdlib `HTTP::WebSocket`, без
  внешних зависимостей (замена selenium-webdriver):
  - запуск headless-Chromium (`--headless=new --remote-debugging-port=0`,
    throwaway user-data-dir; бинарник — `CHROMIUM_BIN` или автопоиск
    chromium/chromium-browser/google-chrome[-stable]),
  - page-target через `PUT /json/new`, `Page.navigate`,
    `Runtime.evaluate` (returnByValue + awaitPromise),
    `Page.captureScreenshot`; готовность страницы — поллинг
    `document.readyState == "complete"`.
- `Capybara::Session` — DSL-подмножество гема:
  `visit`/`current_path`/`current_url`/`title`,
  `click_link`/`click_button` (id / точный текст / aria-label,
  fallback на подстроку), `fill_in(locator, with:)` (label[for] →
  id/name/placeholder поля), `find`/`all` → `Node` (`.text`,
  `[](attr)`, `.click`, `.set`), `has_content?`/`has_no_content?`/
  `has_selector?`, `evaluate_script`/`execute_script`,
  `go_back`/`go_forward`, `save_screenshot`.
  Wait-семантика: `has_*`/`find` поллят до
  `Capybara.default_wait_time` (2с), как `default_max_wait_time` гема.
- `base_url` у сессии — аналог `Capybara.app_host`: `visit("/path")`
  навигирует браузер на реальный HTTP-сервер приложения.

## Oracle

`oracle/capybara_cases.rb`: мини-Rack-приложение с фиксированным HTML
(корень с формой/ссылкой/JS-кнопкой reveal, /next, /greet) прогоняется
настоящей capybara 3.40.0 + selenium-webdriver (headless Chrome) —
10 кейсов: visit→title/path, click_link, fill_in+submit, has_content
(true/false), число .item, href-атрибут, evaluate_script, **wait**
(контент появляется через setTimeout 300мс), go_back/go_forward,
скриншот. Регенерация:

```
PATH=/usr/bin:/bin ruby oracle/capybara_cases.rb \
  > oracle/capybara_expected.yml
```

(PATH обрезан, чтобы Selenium Manager взял chromedriver под
установленный google-chrome, а не устаревший из ~/.local/bin;
Ruby — rvm 3.4.5, где стоят capybara/selenium-webdriver.)

Зеркало: `spec/capybara_spec.cr` — CRails-приложение (railties по
path-dep) на `127.0.0.1:0` с байт-идентичным HTML, те же case-ID,
ожидания байт-в-байт. 10/10 `crystal spec`. Без chromium-бинарника
спек корректно скипается (как SSH_ORACLE_LIVE в net_ssh.cr).

## Отклонения от гема (P1)

- Клик — JS `el.click()`, не доверенные события
  (`Input.dispatchMouseEvent`): onclick/навигация работают,
  слушатели сырых mouse-events — нет.
- Ноды пинятся через внутренний data-атрибут
  `data-capybara-node`, а не через backend-хендлы RemoteObject.
- Нет rack_test-драйвера: request-уровень без браузера закрывает
  `ActionDispatch::IntegrationSession` (railties.cr).
- Нет: `select`/`check`/`uncheck`/`attach_file`, `within`,
  окна/iframe, `match`/`text`-опции локаторов, модальные диалоги,
  `save_and_open_page`, JS-ошибки как исключения в has_*.

## Заметки по сборке

- Зависимость `railties_cr` нужна только спекам (демо-приложение);
  сам порт — чистый stdlib.
- Транзитивные path-зависимости railties резолвятся от корня myshards
  (`../action_view.cr` и т.п.) — в корне лежат симлинки
  action_view.cr/action_pack.cr/importmap.cr → `../rails.cr/*`
  (как уже существующий active_support.cr).
- Хитрость спека: драйвер/сессия/адрес — константы (suite спека
  исполняется из at_exit, локальные переменные к этому моменту
  собираются GC → websocket умирал между top-level и примерами).
