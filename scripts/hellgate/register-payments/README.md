# Регистрация платежей из CSV

Этот скрипт автоматизирует процесс создания инвойсов и регистрации платежей для использования в рекуррентных платежах.

## Назначение

Скрипт следует рецепту регистрации платежей, которые будут использоваться как родительские платежи для рекуррентных платежей. Он выполняет две операции:

1. **Create Invoice** - Создает инвойс через сервис Invoicing
2. **Register Payment** - Регистрирует платеж с рекуррентным токеном для будущего использования

## Требования

- `woorl` должен быть установлен и доступен в PATH
- Доступ к сервису Hellgate (по умолчанию: `http://hellgate:8022`)
- CSV файл с необходимыми данными платежей

## Использование

**Важно:** Скрипт запускается из рута проекта, как и все остальные скрипты.

```bash
# Из рута проекта
cd holmes
./scripts/hellgate/register-payments/register-payments-from-csv.py <csv_file> [опции]
```

### Опции

- `--hellgate-host HOST` - Хост Hellgate (по умолчанию: из переменной окружения HELLGATE или "hellgate")
- `--hellgate-port PORT` - Порт Hellgate (по умолчанию: 8022)
- `--damsel-proto PATH` - Путь к директории proto damsel
- `--dry-run` - Показать запросы без их выполнения
- `--skip-invoice-creation` - Пропустить создание инвойсов, только регистрировать платежи
- `--verbose, -v` - Подробный вывод

### Примеры

```bash
# Базовое использование
./scripts/hellgate/register-payments/register-payments-from-csv.py payments.csv

# Dry run для проверки что будет выполнено
./scripts/hellgate/register-payments/register-payments-from-csv.py payments.csv --dry-run

# С подробным выводом
./scripts/hellgate/register-payments/register-payments-from-csv.py payments.csv --verbose

# Пропустить создание инвойсов (инвойсы уже существуют)
./scripts/hellgate/register-payments/register-payments-from-csv.py payments.csv --skip-invoice-creation

# Кастомный хост Hellgate
./scripts/hellgate/register-payments/register-payments-from-csv.py payments.csv --hellgate-host hellgate.example.com --hellgate-port 8080
```

## Формат CSV

### Обязательные колонки

#### Для создания Invoice:
- `invoice_id` - Уникальный ID инвойса (string)
- `party_id` - ID партии (string)
- `shop_id` - ID магазина (string)
- `product` - Описание продукта (string)

#### Для регистрации Payment:
- `amount` - Сумма платежа в минорных единицах валюты (integer, например, 10000 для 100.00)
- `currency` - Код валюты (string, например, "RUB", "USD")
- `provider_id` - ID провайдера для роутинга (integer)
- `terminal_id` - ID терминала для роутинга (integer)
- `provider_transaction_id` - ID транзакции от провайдера (string)
- `card_token` - Токен банковской карты (string)
- `card_bin` - Первые 6 цифр номера карты (string)
- `card_last_digits` - Последние 4 цифры номера карты (string)

### Опциональные колонки

- `recurrent_token` - Рекуррентный токен для будущих платежей (string)
- `payment_id` - ID платежа (string, генерируется автоматически если не указан)
- `external_id` - Внешний ID инвойса (string)
- `due` - Срок оплаты инвойса (временная метка ISO 8601, по умолчанию: "2030-12-31T23:59:59Z")
- `context_type` - Тип контекста (string, по умолчанию: "empty")
- `context_data` - Данные контекста в base64 (string)
- `card_payment_system` - Платежная система (string, например, "visa", "mastercard")
- `cardholder_name` - Имя на карте (string)
- `card_exp_month` - Месяц окончания срока действия 1-12 (integer)
- `card_exp_year` - Год окончания срока действия (integer, например, 2025)
- `contact_email` - Email плательщика (string)
- `contact_phone` - Телефон плательщика (string)

### Пример CSV

См. `scripts/hellgate/register-payments/register-payments-template.csv` для полного примера:

```csv
invoice_id,party_id,shop_id,product,amount,currency,provider_id,terminal_id,provider_transaction_id,recurrent_token,card_token,card_bin,card_last_digits,card_payment_system,cardholder_name,card_exp_month,card_exp_year,contact_email,contact_phone
INV-001,party123,shop456,Тестовый продукт,10000,RUB,1,1,TRX-123456,recurrent_token_abc123,card_token_xyz789,411111,1111,visa,IVAN IVANOV,12,2025,test@example.com,+79001234567
```

## Рабочий процесс

Для каждой строки в CSV скрипт:

1. **Валидирует** что строка содержит все обязательные поля
2. **Создает Invoice** (если не используется `--skip-invoice-creation`):
   ```
   Invoicing Create {
     "party_id": {"id": "<party_id>"},
     "shop_id": {"id": "<shop_id>"},
     "details": {"product": "<product>"},
     "due": "<due>",
     "cost": {
       "amount": <amount>,
       "currency": {"symbolic_code": "<currency>"}
     },
     "context": {"type": "<context_type>", "data": "<context_data>"},
     "id": "<invoice_id>"
   }
   ```

3. **Регистрирует Payment**:
   ```
   Invoicing RegisterPayment "<invoice_id>" {
     "payer_params": {
       "payment_resource": {
         "resource": {
           "payment_tool": {
             "bank_card": {
               "token": "<card_token>",
               "bin": "<card_bin>",
               "last_digits": "<card_last_digits>",
               "payment_system": {"id": "<card_payment_system>"},
               "cardholder_name": "<cardholder_name>",
               "exp_date": {"month": <month>, "year": <year>}
             }
           }
         },
         "contact_info": {
           "email": "<contact_email>",
           "phone_number": "<contact_phone>"
         }
       }
     },
     "route": {
       "provider": {"id": <provider_id>},
       "terminal": {"id": <terminal_id>}
     },
     "transaction_info": {
       "id": "<provider_transaction_id>",
       "extra": {}
     },
     "recurrent_token": "<recurrent_token>"
   }
   ```

## Обработка ошибок

- Скрипт валидирует каждую строку перед обработкой
- Если строка не прошла валидацию, записывается ошибка и продолжается обработка следующей строки
- В конце выводится сводка успешных и проваленных операций
- Используйте флаг `--verbose` для подробных сообщений об ошибках и stack traces

## Переменные окружения

- `HELLGATE` - Хост Hellgate по умолчанию (если не указан через `--hellgate-host`)
- `HELLGATE_PORT` - Порт Hellgate по умолчанию (если не указан через `--hellgate-port`)

## Решение проблем

### Скрипт не может найти woorl
Убедитесь, что `woorl` установлен и находится в вашем PATH, или создайте файл `woorlrc` в руте проекта.

### Connection refused
Проверьте, что сервис Hellgate запущен и доступен по указанному host/port.

### Ошибки Invalid request
- Проверьте, что все обязательные колонки CSV присутствуют и содержат валидные данные
- Убедитесь, что provider_id и terminal_id - корректные целые числа
- Проверьте, что card_bin состоит из 6 цифр, а card_last_digits из 4 цифр
- Убедитесь, что amount - положительное целое число в минорных единицах валюты

### Invoice уже существует
Если вы перезапускаете скрипт и инвойсы уже существуют, используйте флаг `--skip-invoice-creation`.

## Связанная документация

- [Damsel Payment Processing Thrift](https://github.com/valitydev/damsel/blob/master/proto/payment_processing.thrift)
- [Domain Thrift](https://github.com/valitydev/damsel/blob/master/proto/domain.thrift)

## Рецепт регистрации платежа для рекуррентов

Как мы регистрируем платеж для того чтобы использовать его как родительский для рекуррентов:

### 1. Создаем Invoice

```
Invoicing Create {
	"party_ref": {
		"id": "<party_id>"
	},
	"shop_ref": {
		"id": "<shop_id>"
	},
	"details": {
		"product": "<what_product>"
	},
	"due": "2016-03-22T06:12:27Z",
	"cost": {
		"amount": 123,
		"currency": {
			"id": "RUB"
		}
	},
	"context": {
		"type": "<type>",
		"data": "<binary>"
	},
	"id": "<InvoiceID>"
}
```

### 2. Регистрируем Payment

```
Invoicing RegisterPayment "<InvoiceID>" {
	"payer_params": {
		"payment_resource": {
			"resource":{
				"payment_tool": {
				<Вставить domain.PaymentTool, скорее всего domain.BankCard>
				}
			},
			"contact_info":{}
		}
	},
	"route": {
		"provider": {
			"id": "<provider_id>"
		},
		"terminal": {
			"id": "<terminal_id>"
		}
	},
	"transaction_info": {
		"id": "<provider_transaction_id>",
		"extra": {}
	},
	"recurrent_token": "<recurrent_token>"
}
```
