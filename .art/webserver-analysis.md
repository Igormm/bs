# BS как основа HTTP-сервера — анализ

> Оценка возможности построить веб-сервер на BS-фреймворке: что уже есть,
> какие архитектуры реализуемы в bash, чего не хватает и какой потолок.

## 1. Что уже есть в фреймворке

| Ресурс | Статус | Значение для сервера |
|---|---|---|
| `lib/integration/http.sh` | есть | HTTP **клиент** (curl/wget backend) — не сервер, но пригодится для health-check'ов и проксирования |
| `lib/tui/tui.sh` | есть | буферный рендерер, виджеты — база для **терминальной панели** сервера, не для HTML |
| `lib/data/dataprocessor.sh` | есть | JSON/XML/CSV/YAML (через `jq`) — форматирование API-ответов |
| `lib/rfc/uri.sh`, `lib/rfc/csv.sh` | есть | разбор URI/запросов-ответов RFC-форматов |
| `lib/io/streams.sh` | есть | FD-операции, `wait_readable` (poll-аналог), pipe — основа event-loop |
| `lib/io/process.sh` | есть | `guard`/`background`/`detach`, страсс-диагностика — демоны и воркеры |
| `lib/system/services.sh` | есть | systemd-юниты — деплой сервера как сервиса |
| `lib/ui/presentation.sh` | есть | markdown-подобный вывод — документация/рендер |
| `lib/status/ps1status.sh`, `lib/audit/*` | есть | статус/аудит — observability |
| `lib/math`, `lib/data/lsp` | есть | вычисления, парсинг кода |

Отсутствует (ключевой gap):
- **нет слушателя сокетов** в чистом bash (`/dev/tcp` только для клиента);
- **нет парсера HTTP/1.1 запросов**;
- **нет роутинга/статик-раздачи/сессий**;
- `nc/socat` не в обязательных зависимостях (политика «zero external deps»
  нарушается — см. §4).

## 2. Реализуемые архитектуры

### Вариант A — `bash /dev/tcp` + со-процессы (чистый bash, без зависимостей)
Не подходит: `/dev/tcp` — только исходящие соединения. Принимать входящие
bash сам не может. ❌

### Вариант B — внешний однострочный слушатель + BS-обработчик
```bash
socat TCP-LISTEN:8080,reuseaddr,fork 'EXEC:"bs run ./handler.sh" ,ptys'
# или netcat-цикл, или systemd socket activation
```
`handler.sh` читает запрос из stdin (`io::streams::read_line`), разбирает
request-line и заголовки (`lib/rfc/uri`), роутит и пишет ответ в stdout.
- Плюсы: 100% bash-логика в BS, минимум кода, каждый запрос = новый процесс
  (изоляция краха). systemd `Accept=no` socket-activation убирает even socat
  из критического пути на «дефолтном» путя.
- Минусы: зависимость от `socat`/`ncat` (одна бинарная, probe-able — вписуется
  в capability-вектор); пер-запуск bash на запрос = ~5–15 мс (для внутреннего
  тулинга — приемлемо).

### Вариант C — `coproc` + FIFO-очередь (полный event-loop в одном процессе)
bash слушает FIFO, в него складывает запросы внешний приемщик; один долгий
`bs`-процесс держит состояние (сессии, keep-alive). Сложно, выигрыш мал. ⚠️

### Вариант D — FFI/модуль-мост к `busybox httpd` или `tcc`-компилируемому
mini-listener'у, собираемому `install.sh` при наличии. Максимальная
производительность, но вне «zero deps at runtime». ⚠️

**Рекомендация: B** (с fallback-цепочкой слушателей
`socat → ncat → busybox httpd`, по образцу probe-цепочек `__http::backend`).

## 3. Что даёт BS-фреймворк «из коробки» серверу

- **Конфигурация** — `core/config.sh` + `core/args.sh` (декларативные флаги,
  авто-help): `--port`, `--root`, `--route` из одного источника.
- **Логирование** — `core/logger.sh` (text/json/structured) → access/err log
  в JSON для последующего парсинга (`dataprocessor`).
- **Структура модуля** — `bs::guard`, `bs::source_relative`, `@depends`:
  сервер становится обычным модулем `lib/net/server` с тестами.
- **Безопасность** — `lib/system/safety.sh`, `permissions`, `users`
  (drop-privileges), `errorhandler` (аккуратные 4xx/5xx вместо падения).
- **Форматы** — `dataprocessor` (JSON/XML/CSV/YAML) + `rfc/csv` + `rfc/uri`
  для контента.
- **Тестируемость** — тестовые хуки (`SERVER_ROOT_PATH`, `SERVER_PORT`),
  интеграционные тесты гоняют реальный `http::get` против поднятого в
  временном каталоге сервера (см. `tests/integration/`).
- **Сборка/доставка** — `bs build` упаковывает сервер в standalone-артефакт;
  `lib/system/services.sh` ставит systemd-юнитом.

## 4. Риски и ограничения

1. **Производительность** — bash-обработчик: десятки rps максимум. Это
   «сервер для тулинга/внутренних API/статик-раздачи/вебхуков», не продакшн
   highload. Честно декларировать ярус в README.
2. **Zero-dependency-политика** — listener требует внешнюю бинарную
   зависимость; она должна быть probe'ом с явной деградацией (как curl/wget
   в `http.sh`), не жёстким требованием.
3. **Инъекции** — заголовки/пути приходят от сети: обязательный whitelist
   `lib/rfc/uri`-парсинг, запрет `eval` на пользовательском вводе, канонизация
   путей (`io/files` + `realpath` probe), отсутствие shell-подстановок в
   путях к статике.
4. **Конкурентность keep-alive/_big bodies_** — per-connection-процесс
   решает, но требует `Timeout`/`LimitNOFILE` в юните.
5. **Отсутствие TLS** — терминировать снаружи (socat OPENSSL / nginx /
   systemd TLS-socket), в ядре не тащить openssl-пarsing.

## 5. Минимальный MVP (оценка: 1–2 дня, 3 модуля)

1. `lib/net/request.sh` — парсер HTTP/1.1 request-line + заголовков →
   map-структура (`map::*`, `str::*`, тесты на golden-запросы).
2. `lib/net/server.sh` — route table (prefix → handler), статика из `--root`,
   `text/plain|html|json` ответы, `404/500`; слушатель через probe-цепочку
   `socat → ncat`; демонизация `io::process::guard`, лог `core/logger`.
3. `examples/webserver_example.sh` + `tests/integration/testwebserver.sh`
   (поднять на `SERVER_PORT=0`→ephemeral, проверить `http::get`'ом 200/404/
   statik/api-json, убить).

Это ровно тот путь, который фреймворк уже протоптал для клиента
(`integration/http.sh`) и устройств (`system/sensor.sh`): маленький модуль,
probe-цепочка бэкендов, тестовые хуки, полный набор валидаторов.
