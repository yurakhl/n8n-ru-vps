# n8n на VPS: Docker Compose + PostgreSQL + резервные копии

Готовые файлы для запуска своего [n8n](https://n8n.io/) на VPS в России: n8n, база PostgreSQL с проверкой готовности, HTTPS через Nginx на самом сервере, скрипты резервного копирования и восстановления.

Репозиторий ведёт автор сайта 1Connector. Это шаблон конфигурации, а не готовый сервис: прочитайте файлы перед запуском и проверьте их на тестовом поддомене.

Подробнее: [подробный разбор с ценами серверов](https://1connector.ru/n8n-vps/?utm_source=github&utm_medium=repo&utm_campaign=sprint_202611).

## Что внутри

| Файл | Назначение |
|---|---|
| `compose.yaml` | n8n + PostgreSQL 16, именованные тома, `restart: unless-stopped` |
| `.env.example` | все переменные с комментариями (скопируйте в `.env`) |
| `backup.sh` | дамп PostgreSQL + архив тома n8n, хранит последние N копий |
| `restore.sh` | восстановление из копии с подтверждением |

Схема: Nginx на сервере (порты 80/443) -> `127.0.0.1:5678` -> контейнер n8n -> контейнер PostgreSQL. Порт n8n наружу не открыт, база наружу не публикуется.

## Минимальный сервер

Ориентир для небольшого стенда: 2 vCPU, 4 ГБ RAM, от 30 ГБ диска. Linux с SSH-доступом, отдельный поддомен (например `n8n.example.ru`), порты 80 и 443 открыты. Ресурсы подбирайте под свои нагрузки; это не результат замеров.

## Установка

1. **DNS.** Создайте A-запись поддомена на публичный IP сервера и дождитесь обновления (`dig +short n8n.example.ru`).
2. **Docker.** Установите актуальные Docker Engine и плагин Compose по [официальной инструкции](https://docs.docker.com/engine/install/). Проверка: `docker compose version`.
3. **Клонирование.**
   ```bash
   git clone https://github.com/yurakhl/n8n-ru-vps.git
   cd n8n-ru-vps
   chmod +x backup.sh restore.sh
   ```
4. **Настройка `.env`.**
   ```bash
   cp .env.example .env
   openssl rand -hex 32   # вставьте в N8N_ENCRYPTION_KEY
   openssl rand -hex 24   # вставьте в POSTGRES_PASSWORD
   nano .env              # укажите N8N_HOST
   chmod 600 .env
   ```
5. **Запуск.**
   ```bash
   docker compose config --quiet
   docker compose up -d
   docker compose logs --tail=50 n8n
   curl --fail http://127.0.0.1:5678/healthz
   ```
6. **HTTPS через Nginx.** Сохраните как `/etc/nginx/sites-available/my-n8n` (замените домен):
   ```nginx
   server {
       listen 80;
       server_name n8n.example.ru;

       location / {
           proxy_pass http://127.0.0.1:5678;
           proxy_http_version 1.1;
           proxy_set_header Host $host;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Host $host;
           proxy_set_header X-Forwarded-Proto $scheme;
           proxy_set_header Upgrade $http_upgrade;
           proxy_set_header Connection "upgrade";
           proxy_read_timeout 300s;
           proxy_buffering off;
       }
   }
   ```
   Ubuntu:
   ```bash
   sudo apt-get update
   sudo apt-get install -y nginx certbot python3-certbot-nginx
   sudo ln -s /etc/nginx/sites-available/my-n8n /etc/nginx/sites-enabled/my-n8n
   sudo nginx -t && sudo systemctl reload nginx
   sudo certbot --nginx -d n8n.example.ru --redirect
   sudo certbot renew --dry-run
   curl --fail https://n8n.example.ru/healthz
   ```
   Если Nginx уже обслуживает другие проекты, добавьте отдельный server block и не трогайте существующие.
7. Откройте `https://n8n.example.ru` и создайте аккаунт владельца.

## Версия образа

В `.env` задаётся `N8N_VERSION` - конкретный тег, а не `latest`, чтобы обновление было вашим осознанным решением. На момент подготовки репозитория документация n8n называет стабильной версию 2.47.3; перед установкой сверьтесь со [страницей Docker Compose в документации](https://docs.n8n.io/hosting/installation/server-setups/docker-compose/) и берите стабильную, а не beta.

## Обновление

1. Сделайте резервную копию: `./backup.sh`.
2. Прочитайте заметки к выпускам n8n между вашей и новой версией.
3. Поменяйте `N8N_VERSION` в `.env`.
4. `docker compose pull && docker compose up -d`, затем `docker compose logs --tail=50 n8n`.

Версию PostgreSQL (`postgres:16-alpine`) не меняйте на следующую мажорную без отдельной миграции данных.

## Резервные копии

```bash
./backup.sh
```

Создаётся каталог `backups/<дата-UTC>/` с файлами:
- `n8n.dump` - дамп PostgreSQL (формат `pg_dump -Fc`);
- `n8n-data.tar.gz` - том n8n (`/home/node/.n8n`, там конфигурация и ключ шифрования);
- `env.backup` - копия `.env` (содержит секреты).

Хранится последние 7 копий (`KEEP_BACKUPS=14 ./backup.sh` - чтобы изменить). Каталог `BACKUP_DIR` можно переопределить. Cron, ежедневно в 03:15:

```cron
15 3 * * * cd /root/n8n-ru-vps && ./backup.sh >> backups/cron.log 2>&1
```

Копии содержат секреты: храните их вне исходного сервера в доверенном хранилище. Скрипт не копирует их сам.

### Восстановление

```bash
./restore.sh backups/20261110T031500Z
```

Скрипт спросит подтверждение (нужно ввести `YES`), остановит n8n, заменит базу и содержимое тома и запустит сервисы. В `.env` должен быть тот же `N8N_ENCRYPTION_KEY`. Хотя бы раз проверьте восстановление на тестовом сервере: копия, которую не пробовали восстановить, ничего не гарантирует.

## Частые ошибки

- **Домен показывает чужую страницу.** Проверьте A-запись и `server_name`; убедитесь, что конфиг есть в `sites-enabled`.
- **502 от Nginx.** `docker compose ps`, `docker compose logs n8n`, `curl http://127.0.0.1:5678/healthz`; проверьте `proxy_pass`.
- **n8n не стартует, ругается на переменную.** Заполнены ли `N8N_HOST`, `N8N_VERSION`, `N8N_ENCRYPTION_KEY`, `POSTGRES_PASSWORD` в `.env`?
- **Webhook показывает localhost или http.** Проверьте `N8N_HOST` и `.env`, примените `docker compose up -d`. У некоторых интеграций callback нужно зарегистрировать заново.
- **Не удаётся войти в сохранённые подключения после переноса.** Ключ `N8N_ENCRYPTION_KEY` не совпадает с прежним.
- **Пропали данные.** Не выполняйте `docker compose down -v`: флаг `-v` удаляет тома.
- **Пароль PostgreSQL изменён в `.env` после первого запуска.** Он применяется только при создании базы; смените его внутри PostgreSQL или пересоздайте том (после копии).

## Лицензии

Файлы этого репозитория распространяются по лицензии MIT (см. `LICENSE`). Сам n8n выпускается по [Sustainable Use License](https://docs.n8n.io/sustainable-use-license/) - ознакомьтесь с её ограничениями, особенно если планируете коммерческое использование.
