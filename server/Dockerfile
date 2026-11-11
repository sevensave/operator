# Выделенный сервер «Оператора». Бинарь собирается заранее: tools/build_server.sh
FROM debian:bookworm-slim
RUN useradd -m -u 1000 op
WORKDIR /app
COPY operator-server.x86_64 /app/operator-server
RUN chmod +x /app/operator-server
USER op
ENV OPERATOR_PORT=27630
EXPOSE 27630/udp
CMD ["/app/operator-server", "--headless", "--", "--server"]
