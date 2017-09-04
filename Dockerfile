FROM alpine
MAINTAINER Marios Andreopoulos <marios@landoop.com>

# Update, install tooling and some basic setup
RUN apk add --no-cache \
        bash coreutils \
        bash-completion \
        wget curl \
        openjdk8-jre-base \
        tar gzip bzip2 \
        supervisor \
        sqlite \
        libstdc++ \
        openssl \
    && echo "progress = dot:giga" | tee /etc/wgetrc \
    && mkdir /opt \
    && wget https://gitlab.com/andmarios/checkport/uploads/3903dcaeae16cd2d6156213d22f23509/checkport -O /usr/local/bin/checkport \
    && chmod +x /usr/local/bin/checkport \
    && mkdir /extra-connect-jars /connectors \
    && mkdir /etc/supervisord.d

# Create Landoop configuration directory
RUN mkdir /usr/share/landoop

# Add Confluent Distribution
ENV CP_VERSION="3.3.0" KAFKA_VERSION="0.11.0.0"
ARG CP_URL="https://packages.confluent.io/archive/3.3/confluent-oss-${CP_VERSION}-2.11.tar.gz"
RUN wget "$CP_URL" -O /opt/confluent.tar.gz \
    && mkdir -p /opt/confluent \
    && tar --no-same-owner --strip-components 1 -xzf /opt/confluent.tar.gz -C /opt/confluent \
    && mkdir /opt/confluent/logs && chmod 1777 /opt/confluent/logs \
    && rm -rf /opt/confluent.tar.gz \
    && ln -s /opt/confluent "/opt/confluent-${CP_VERSION}"


# Add Stream Reactor and Elastic Search (for elastic connector)
ARG STREAM_REACTOR_URL=https://archive.landoop.com/third-party/stream-reactor/stream-reactor-0.3.0_3.3.0.tar.gz
RUN wget "${STREAM_REACTOR_URL}" -O stream-reactor.tar.gz \
    && mkdir -p /opt/connectors \
    && tar -xzf stream-reactor.tar.gz --no-same-owner --strip-components=1 -C /opt/connectors \
    && rm /stream-reactor.tar.gz \
    && wget https://download.elastic.co/elasticsearch/release/org/elasticsearch/distribution/tar/elasticsearch/2.4.1/elasticsearch-2.4.1.tar.gz \
    && tar xf /elasticsearch-2.4.1.tar.gz --no-same-owner \
    && mv /elasticsearch-2.4.1/lib/*.jar /opt/connectors/kafka-connect-elastic/ \
    && rm -rf /elasticsearch-2.4.1* \
    && echo "plugin.path=/opt/connectors,/extra-connect-jars,/connectors" >> /opt/confluent/etc/schema-registry/connect-avro-distributed.properties

#ADD lenses-interceptor-1.0.jar /extra-connect-jars/
ADD /kafka-lenses/ /kafka-lenses/

# Create system symlinks to Confluent's binaries
ADD binaries /opt/confluent/bin-install
RUN bash -c 'for i in $(find /opt/confluent/bin-install); do ln -s $i /usr/local/bin/$(echo $i | sed -e "s>.*/>>"); done' \
    && cd /opt/confluent/bin \
    && ln -s kafka-run-class kafka-run-class.sh

# Configure Confluent
RUN echo "access.control.allow.methods=GET,POST,PUT,DELETE,OPTIONS" >> /opt/confluent/etc/schema-registry/schema-registry.properties \
    && echo 'access.control.allow.origin=*' >> /opt/confluent/etc/schema-registry/schema-registry.properties \
    && echo "access.control.allow.methods=GET,POST,PUT,DELETE,OPTIONS" >> /opt/confluent/etc/kafka-rest/kafka-rest.properties \
    && echo 'access.control.allow.origin=*' >> /opt/confluent/etc/kafka-rest/kafka-rest.properties \
    && echo "access.control.allow.methods=GET,POST,PUT,DELETE,OPTIONS" >> /opt/confluent/etc/schema-registry/connect-avro-distributed.properties \
    && echo 'access.control.allow.origin=*' >> /opt/confluent/etc/schema-registry/connect-avro-distributed.properties

# # Add and setup Kafka Manager
# RUN wget https://archive.landoop.com/third-party/kafka-manager/kafka-manager-1.3.2.1.zip \
#          -O /kafka-manager-1.3.2.1.zip \
#     && unzip /kafka-manager-1.3.2.1.zip -d /opt \
#     && rm -rf /kafka-manager-1.3.2.1.zip

# # Add Twitter Connector
# ARG TWITTER_CONNECTOR_URL="https://archive.landoop.com/third-party/kafka-connect-twitter/kafka-connect-twitter-0.1-master-af63e4c-cp3.2.2-jar-with-dependencies.jar"
# RUN mkdir -p /opt/confluent/share/java/kafka-connect-twitter \
#     && wget "$TWITTER_CONNECTOR_URL" -P /opt/confluent/share/java/kafka-connect-twitter

# Add dumb init and quickcert
RUN wget https://github.com/Yelp/dumb-init/releases/download/v1.2.0/dumb-init_1.2.0_amd64 -O /usr/local/bin/dumb-init \
    && wget https://github.com/andmarios/quickcert/releases/download/1.0/quickcert-1.0-linux-amd64-alpine -O /usr/local/bin/quickcert \
    && chmod 0755 /usr/local/bin/dumb-init /usr/local/bin/quickcert

# Add Coyote and tests
ADD integration-tests/kafka-tests.yml /usr/share/landoop
ADD integration-tests/smoke-tests.sh /usr/local/bin
RUN wget https://github.com/Landoop/coyote/releases/download/v1.1/coyote-1.1-linux-amd64 -O /usr/local/bin/coyote \
    && chmod +x /usr/local/bin/coyote /usr/local/bin/smoke-tests.sh \
    && mkdir -p /var/www/coyote-tests
ADD integration-tests/index.html integration-tests/results /var/www/coyote-tests/

# Add fast-data-dev UI
COPY web/index.html web/env.js web/env-webonly.js /var/www/
COPY web/img /var/www/img
RUN ln -s /var/log /var/www/logs

# Add sample data and install normcat
ARG NORMCAT_URL=https://github.com/andmarios/normcat/releases/download/1.0/normcat-1.0-linux-amd64.tar.gz
RUN wget "$NORMCAT_URL" -O /normcat.tgz \
    && tar xf /normcat.tgz -C /usr/local/bin \
    && rm /normcat.tgz
COPY sample-data /usr/share/landoop/sample-data

# Add executables, settings and configuration
ADD extras/ /usr/share/landoop/
ADD supervisord.conf /etc/supervisord.conf
ADD setup-and-run.sh logs-to-kafka.sh /usr/local/bin/
ADD https://github.com/Landoop/kafka-autocomplete/releases/download/0.2/kafka /usr/share/landoop/kafka-completion
RUN chmod +x /usr/local/bin/setup-and-run.sh /usr/local/bin/logs-to-kafka.sh \
    && ln -s /usr/share/landoop/bashrc /root/.bashrc

ARG BUILD_BRANCH
ARG BUILD_COMMIT
ARG BUILD_TIME
ARG DOCKER_REPO=local
RUN echo "BUILD_BRANCH=${BUILD_BRANCH}"      | tee /build.info \
    && echo "BUILD_COMMIT=${BUILD_COMMIT}"   | tee -a /build.info \
    && echo "BUILD_TIME=${BUILD_TIME}"       | tee -a /build.info \
    && echo "DOCKER_REPO=${DOCKER_REPO}"     | tee -a /build.info \
    && echo "KAFKA_VERSION=${KAFKA_VERSION}" | tee -a /build.info \
    && echo "CP_VERSION=${CP_VERSION}"       | tee -a /build.info

EXPOSE 2181 3030 3031 8081 8082 8083 9092
ENTRYPOINT ["/usr/local/bin/dumb-init", "--"]
CMD ["/usr/local/bin/setup-and-run.sh"]
