# steamcmd/steamcmd is legacy and unpinned (amd64 only); see the README for the
# possible move to the Debian + SteamCMD base used by images/valheim.
FROM steamcmd/steamcmd
LABEL org.opencontainers.image.source="https://github.com/dtandersen/dockerfiles/tree/main/images/stationeers"

RUN apt-get update && \
  apt-get install -y pwgen gosu

ENV STEAMCMD=/usr/bin/steamcmd \
    APP_DIR=/opt/stationeers \
    PROFILE_DIR=/var/opt/stationeers \
    AUTOSAVEINTERVAL=600 \
    WORLDNAME=Stationeers \
    WORLDTYPE=Mars
#    LOG_DIR=$STATE_DIR/logs
#    SAVE_DIR=$STATE_DIR/saves

ENV BRANCH=public
COPY docker-entrypoint.sh /

#RUN mkdir -p /home/steam/stationeers && \
#    touch /home/steam/stationeers/default.ini && \
#    touch /home/steam/stationeers/blocked.txt
#VOLUME /home/steam/stationeers
VOLUME $PROFILE_DIR

EXPOSE 27500/udp 27500/tcp 27015/udp

WORKDIR $APP_DIR

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD [ "rocketstation_DedicatedServer.x86_64" ]
