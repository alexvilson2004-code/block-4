# Учёт заявок клиентов на получение кредита

Backend на Delphi 10.2: WebBroker ISAPI, IIS, MS SQL Server и FireDAC.

## Требования

- Delphi 10.2 Tokyo с компонентами WebBroker и FireDAC;
- IIS с поддержкой ISAPI;
- MS SQL Server;
- установленный и доступный FireDAC-драйвер MSSQL.

## Сборка

1. Откройте `src/LoanApi.dpr` в Delphi.
2. Выберите конфигурацию Release и платформу Win32 или Win64.
3. Соберите проект как ISAPI DLL.
4. Разместите DLL в каталоге сайта IIS.
5. Скопируйте `deploy/api.ini.example` рядом с DLL под именем `api.ini`.
6. Выполните `database/schema.sql` в SQL Server Management Studio.
7. Настройте IIS на запуск ISAPI DLL и выдайте приложению права доступа к каталогу с DLL и `api.ini`.

Платформа DLL должна совпадать с разрядностью пула приложений IIS.

## API

### Список заявок

`GET /api/applications`

### Получить заявку

`GET /api/applications/{id}`

### Создать заявку

`POST /api/applications`

Пример тела:

```json
{
  "fullName": "Иван Иванов",
  "phone": "+79990000000",
  "email": "ivan@example.com",
  "requestedAmount": 250000.00,
  "termMonths": 36,
  "purpose": "Покупка автомобиля"
}
