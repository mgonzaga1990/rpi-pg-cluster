FROM postgres:10

RUN ln -s /home/postgres/repmgr.conf /etc/repmgr.conf
 
# override this on secondary nodes
ENV PRIMARY_NODE=localhost

RUN apt-get update \
	&& apt-get install curl net-tools -y

#install repmgr-common
RUN curl -k -O -L http://ftp.br.debian.org/debian/pool/main/r/repmgr/repmgr-common_5.0.0-4_all.deb \
	&& apt install ./repmgr-common_5.0.0-4_all.deb

RUN curl -k -O -L http://ports.ubuntu.com/pool/universe/r/repmgr/postgresql-10-repmgr_4.0.3-1_arm64.deb
RUN apt install ./postgresql-10-repmgr_4.0.3-1_arm64.deb

RUN apt-get install iputils-ping -y

RUN mkdir -p /home/postgres/; chown postgres:postgres /home/postgres/

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

EXPOSE 5432

CMD [ "postgres", "-c", "config_file=/etc/postgresql/postgresql.conf" ]
