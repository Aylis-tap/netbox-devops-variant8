# DevOps Инфраструктура для NetBox (Вариант №8)

Проект автоматизированного развертывания, непрерывной интеграции (CI/CD) и мониторинга для системы учета сетевых ресурсов **NetBox v4.0.8**.

## Быстрый старт на чистой машине

```sh
git clone <URL_РЕПОЗИТОРИЯ> netbox-devops
cd netbox-devops
/bin/sh setup.sh
```

## Функциональное тестирование (Smoke Tests)

```sh
/bin/sh smoke_test.sh
```

## Запуск стека мониторинга и сбора логов

```sh
cd monitoring
docker compose -f docker-compose.monitoring.yml up -d
```
* **Grafana:** [http://localhost:3000](http://localhost:3000) (Логин: `admin` / Пароль: `admin`)
* **Prometheus:** [http://localhost:9090](http://localhost:9090)
* **Loki:** [http://localhost:3100](http://localhost:3100)
