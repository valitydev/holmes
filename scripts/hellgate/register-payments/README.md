# Регистрация платежей из CSV

Скрипт для автоматизации создания инвойсов и регистрации платежей для использования в рекуррентных платежах.

## Быстрый старт

```bash
# Запускаем из рута проекта
cd /path/to/holmes

# Тест с dry-run
./scripts/hellgate/register-payments/register-payments-from-csv.py payments.csv --dry-run -v

# Реальное выполнение
./scripts/hellgate/register-payments/register-payments-from-csv.py payments.csv -v
```

## Что делает скрипт

Реализует рецепт регистрации платежей для использования как родительских платежей для рекуррентов:

1. **Создает Invoice** через `Invoicing Create`
2. **Регистрирует Payment** через `Invoicing RegisterPayment` с рекуррентным токеном

## Формат CSV

### Обязательные колонки

**Для Invoice:**
- `invoice_id` - ID инвойса
- `party_id` - ID партии
- `shop_id` - ID магазина  
- `product` - Описание продукта

**Для Payment:**
- `amount` - Сумма в минорных единицах (10000 = 100.00)
- `currency` - Код валюты (RUB, USD, EUR)
- `provider_id` - ID провайдера (integer)
- `terminal_id` - ID терминала (integer)
- `provider_transaction_id` - ID транзакции от провайдера
- `card_token` - Токен карты
- `card_bin` - Первые 6 цифр карты
- `card_last_digits` - Последние 4 цифры карты
- `card_payment_system` - Платежная система (VISA, MASTERCARD, MAESTRO)
- `recurrent_token` - Рекуррентный токен

### Опциональные колонки

- `payment_id` - ID платежа (автогенерация если не указан)
- `external_id` - Внешний ID инвойса
- `cardholder_name` - Имя держателя карты
- `card_exp_month` - Месяц окончания (1-12)
- `card_exp_year` - Год окончания (2025, 2026...)
- `contact_email` - Email плательщика
- `contact_phone` - Телефон плательщика
- `due` - Срок оплаты (ISO 8601, по умолчанию: 2030-12-31T23:59:59Z)
- `context_type` - Тип контекста (по умолчанию: "empty")
- `context_data` - Данные контекста в base64

## Примеры использования

```bash
# Базовое использование
./scripts/hellgate/register-payments/register-payments-from-csv.py payments.csv

# С подробным выводом
./scripts/hellgate/register-payments/register-payments-from-csv.py payments.csv -v

# Dry-run для проверки
./scripts/hellgate/register-payments/register-payments-from-csv.py payments.csv --dry-run -v

# Инвойсы уже созданы, только регистрация платежей
./scripts/hellgate/register-payments/register-payments-from-csv.py payments.csv --skip-invoice-creation

# Кастомный хост Hellgate
./scripts/hellgate/register-payments/register-payments-from-csv.py payments.csv --hellgate-host my-hellgate --hellgate-port 8080

# Указать путь к proto файлу
./scripts/hellgate/register-payments/register-payments-from-csv.py payments.csv --damsel-proto /path/to/damsel/proto/payment_processing.thrift
```

## Опции

- `--hellgate-host HOST` - Хост Hellgate (по умолчанию: HELLGATE env или "hellgate")
- `--hellgate-port PORT` - Порт Hellgate (по умолчанию: 8022)
- `--damsel-proto PATH` - Путь к proto файлу (автоопределение по умолчанию)
- `--dry-run` - Показать команды без выполнения
- `--skip-invoice-creation` - Пропустить создание инвойсов
- `--verbose, -v` - Подробный вывод

## Пример CSV

```csv
invoice_id,party_id,shop_id,product,amount,currency,provider_id,terminal_id,provider_transaction_id,recurrent_token,card_token,card_bin,card_last_digits,card_payment_system,cardholder_name,card_exp_month,card_exp_year,contact_email,contact_phone,external_id,payment_id
INV-001,party123,shop456,Подписка Premium,99900,RUB,1,100,TRX-001,token_001,card_tok_001,400000,1234,visa,IVAN PETROV,12,2026,ivan@example.com,+79001234567,EXT-001,1
INV-002,party123,shop456,Месячная подписка,49900,RUB,1,100,TRX-002,token_002,card_tok_002,540000,5678,mastercard,MARIA IVANOVA,06,2027,maria@example.com,+79009876543,EXT-002,1
```

См. `register-payments-template.csv` и `register-payments-template-minimal.csv` для готовых шаблонов.

## Обработка ошибок

- Скрипт валидирует каждую строку перед обработкой
- При ошибке в строке - логируется и продолжается обработка
- В конце выводится сводка успешных/провальных операций
- Используйте `-v` для детального вывода ошибок

## Переменные окружения

- `HELLGATE` - Хост Hellgate по умолчанию
- `HELLGATE_PORT` - Порт Hellgate по умолчанию

## Конфигурация woorl

Скрипт поддерживает файл `woorlrc` в текущей директории:

```bash
# Пример woorlrc
WOORL=(woorl -v --deadline 30s)
```

Если файл не найден, используется `woorl` по умолчанию.

## Решение проблем

### Ошибка: proto file not found

**Причина:** Скрипт не может найти `damsel/proto/payment_processing.thrift`.

**Решение:**
- Запускайте скрипт из рута проекта (где находится папка `damsel`)
- Или укажите путь явно: `--damsel-proto /path/to/damsel/proto/payment_processing.thrift`

### Connection refused

**Причина:** Hellgate недоступен.

**Решение:**
- Проверьте что Hellgate запущен
- Укажите правильный хост/порт: `--hellgate-host <host> --hellgate-port <port>`

### Invalid request errors

**Проверьте:**
- Все обязательные колонки присутствуют
- `provider_id` и `terminal_id` - целые числа
- `card_bin` - 6 цифр, `card_last_digits` - 4 цифры
- `amount` - целое число в минорных единицах
- `card_exp_month` - число от 1 до 12
- `card_exp_year` - корректный год

## Связанная документация

- [Damsel Payment Processing](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift)
- [Damsel Domain](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift)
