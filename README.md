# STIMUL Mini App — deployment-ready package

Готовый пакет для публикации в **GitHub + Render** или **GitHub + Railway**.

## Что внутри
- Node.js + Express
- PostgreSQL
- Пользователи в БД (`app_users`)
- bcrypt-хеширование паролей
- Роли `admin / editor / viewer`
- Excel-export `.xlsx`
- Карточка педагога с печатью
- Журнал действий (`audit_log`)

## Быстрый старт локально
```bash
npm install
cp .env.example .env
npm start
```

## Переменные окружения
Основной вариант для облака — использовать `DATABASE_URL`.

Обязательные:
- `DATABASE_URL`
- `INITIAL_ADMIN_USERNAME`
- `INITIAL_ADMIN_PASSWORD`
- `INITIAL_ADMIN_FULL_NAME`

Опционально:
- `PORT`

Приложение поддерживает оба варианта:
1. `DATABASE_URL`
2. отдельные `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`

## GitHub
1. Создайте новый репозиторий.
2. Загрузите содержимое этого пакета в репозиторий.
3. Не загружайте `.env` — только `.env.example`.

## Deploy в Render
1. Создайте репозиторий на GitHub и загрузите код.
2. В Render выберите **New + Blueprint** или создайте сервис вручную.
3. Если используете Blueprint, Render прочитает `render.yaml`.
4. Укажите секреты:
   - `INITIAL_ADMIN_USERNAME`
   - `INITIAL_ADMIN_PASSWORD`
   - `INITIAL_ADMIN_FULL_NAME`
5. Render сам создаст Web Service и PostgreSQL из `render.yaml`.
6. После деплоя откройте публичную ссылку и войдите под первым администратором.

## Deploy в Railway
1. Создайте проект в Railway.
2. Выберите **Deploy from GitHub repo**.
3. Подключите этот репозиторий.
4. Добавьте PostgreSQL в тот же проект.
5. В Variables веб-приложения задайте:
   - `DATABASE_URL` = reference на PostgreSQL
   - `INITIAL_ADMIN_USERNAME`
   - `INITIAL_ADMIN_PASSWORD`
   - `INITIAL_ADMIN_FULL_NAME`
6. Railway сам передаст `PORT` приложению.
7. После деплоя откройте выданный Railway URL.

## Важно
- Первый администратор создаётся автоматически в таблице `app_users`, если такого логина ещё нет.
- Если пользователь уже создан, переменные `INITIAL_ADMIN_*` не перезапишут его.
- Для Render и Railway рекомендуется использовать именно `DATABASE_URL`.

## Проверка после деплоя
1. Открывается страница логина.
2. Вход под первым администратором работает.
3. Загружается dashboard.
4. Открываются разделы `Результаты`, `Сводка`, `Пользователи`, `Журнал`.
5. Работает экспорт XLSX.
6. Создаётся пользователь и отображается в списке.

## Примечание по базе
В проекте предполагается, что основная схема предметных таблиц (`students`, `teachers`, `student_results`, `teacher_calculations` и т.д.) уже создана вашей миграцией `migration.sql`.

Если хотите, следующим шагом можно сделать отдельный SQL bootstrap-файл под облачную БД, чтобы развёртывание было полностью автоматическим.
