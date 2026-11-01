FROM debian:13-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132

RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      lib32gcc-s1 \
      lib32stdc++6 \
      libatomic1 \
      libgcc-s1 \
      libpulse0 \
      libstdc++6 \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --gid 568 steam \
 && useradd --uid 568 --gid 568 --create-home \
      --home-dir /home/steam --shell /usr/sbin/nologin steam \
 && mkdir -p /opt/steamcmd /data \
 && chown -R 568:568 /opt/steamcmd /data \
 && ln -s /opt/steamcmd/steamcmd.sh /usr/local/bin/steamcmd

# The SteamCMD app to install is 896660 (set by the entrypoint). Steam's
# backend expects the game id instead, so the image sets that here.
ENV HOME=/home/steam \
    LANG=C.UTF-8 \
    SteamAppId=892970

USER 568

# Valve's bootstrap installer has not changed since 2018; it self-updates into
# /opt/steamcmd on first run, so the hash stays valid.
ARG STEAMCMD_SHA256=cebf0046bfd08cf45da6bc094ae47aa39ebf4155e5ede41373b579b8f1071e7c
RUN curl -fsSL -o /tmp/steamcmd.tar.gz \
      https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
 && echo "${STEAMCMD_SHA256}  /tmp/steamcmd.tar.gz" | sha256sum -c - \
 && tar -xzf /tmp/steamcmd.tar.gz -C /opt/steamcmd \
 && rm /tmp/steamcmd.tar.gz \
 && /opt/steamcmd/steamcmd.sh +quit

COPY entrypoint.sh /usr/local/bin/valheim-entrypoint

WORKDIR /data

ENTRYPOINT ["/bin/bash", "/usr/local/bin/valheim-entrypoint"]
