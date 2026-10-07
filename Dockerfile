FROM ubuntu:22.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 procps \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www

COPY script.sh /usr/local/bin/script.sh
COPY start-service.sh /usr/local/bin/start-service.sh
RUN chmod +x /usr/local/bin/script.sh /usr/local/bin/start-service.sh

EXPOSE 8080

CMD ["/usr/local/bin/start-service.sh"]
