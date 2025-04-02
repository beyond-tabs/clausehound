FROM swipl:latest

RUN apt-get update && apt-get install -y wget unixodbc libodbc1 && \
    rm -rf /var/lib/apt/lists/*

RUN wget https://dev.mysql.com/get/Downloads/Connector-ODBC/9.2/mysql-connector-odbc_9.2.0-1debian12_amd64.deb && \
    dpkg -i mysql-connector-odbc_9.2.0-1debian12_amd64.deb && \
    rm mysql-connector-odbc_9.2.0-1debian12_amd64.deb

RUN echo "[MySQL ODBC 9.2 Unicode Driver]\n\
Description=ODBC for MySQL\n\
Driver=/usr/lib/x86_64-linux-gnu/odbc/libmyodbc9w.so" \
> /etc/odbcinst.ini

COPY odbc.ini /etc/odbc.ini

COPY matching_ranking.pl /app/

WORKDIR /app

EXPOSE 8081

CMD swipl -g "start_server" -t "halt" -f matching_ranking.pl
