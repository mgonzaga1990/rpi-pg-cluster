FROM postgres:10

MAINTAINER Jayson Gonzaga <markjayson.gonzaga1990@gmail.com>
 
RUN apt-get update \
	&& apt-get install curl net-tools iputils-ping -y

#install repmgr-common
RUN curl -k -O -L http://ftp.br.debian.org/debian/pool/main/r/repmgr/repmgr-common_5.0.0-4_all.deb \
	&& apt install ./repmgr-common_5.0.0-4_all.deb \
        && rm ./repmgr-common_5.0.0-4_all.deb

RUN curl -k -O -L http://ports.ubuntu.com/pool/universe/r/repmgr/postgresql-10-repmgr_4.0.3-1_arm64.deb \
        && apt install ./postgresql-10-repmgr_4.0.3-1_arm64.deb \
        && rm ./postgresql-10-repmgr_4.0.3-1_arm64.deb

RUN mkdir -p /home/postgres/; chown postgres:postgres /home/postgres/

RUN ln -s /home/postgres/repmgr.conf /etc/repmgr.conf

COPY postgresql.conf /etc/postgresql/
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

COPY scripts/*.sh /docker-entrypoint-initdb.d/
RUN chmod +x /docker-entrypoint-initdb.d/*.sh

VOLUME /home/postgres/
VOLUME /var/lib/postgresql/data/

ENV REPMGR_USER=repmgr
ENV REPMGR_DB=repmgr
ENV REPMGR_PASSWORD=repmgr
ENV PRIMARY_NODE=localhost
ENV MAX_SERVERS=10

EXPOSE 5432

CMD [ "postgres", "-c", "config_file=/etc/postgresql/postgresql.conf" ]
