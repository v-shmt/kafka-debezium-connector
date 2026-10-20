FROM confluentinc/cp-kafka-connect:7.6.0

USER root

# Install the Debezium Postgres connector plugin
RUN mkdir -p /usr/share/confluent-hub-components/debezium-connector-postgres && \
    curl -sL -o /tmp/debezium-connector-postgres.tar.gz \
        "https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.6.2.Final/debezium-connector-postgres-2.6.2.Final-plugin.tar.gz" && \
    tar -xzf /tmp/debezium-connector-postgres.tar.gz \
        -C /usr/share/confluent-hub-components/debezium-connector-postgres \
        --strip-components=1 && \
    rm /tmp/debezium-connector-postgres.tar.gz

USER 1001
