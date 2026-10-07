# my-sysadmin-scripts

Скрипт раз в пять секунд записывает в `monitor.log` сведения о памяти, дисках и времени работы системы. В ДЗ2 он запускается в Docker-контейнере, а журнал доступен по HTTPS через Nginx.

## Запуск контейнера

```bash
docker build -t my-script .
docker run --rm -p 8080:8080 my-script
```

Для постоянного журнала используется Docker Compose и именованный том:

```bash
docker compose up -d --build
curl http://127.0.0.1:8080/monitor.log
docker compose down
```

## Полное развёртывание

`bootstrap.sh` устанавливает необходимые пакеты, создаёт RAID 1 и LVM на loop-устройствах, собирает контейнер, настраивает Nginx, самоподписанный сертификат и службу systemd.

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

После запуска сервис проверяется командами:

```bash
cat /proc/mdstat
sudo pvs && sudo vgs && sudo lvs
df -h /mnt/raid /mnt/logs
sudo nginx -t
curl -kI https://127.0.0.1/monitor.log
systemctl status my-app
journalctl -u my-app --no-pager -n 20
```

Сертификат учебный и самоподписанный, поэтому в проверочной команде `curl` используется ключ `-k`.
