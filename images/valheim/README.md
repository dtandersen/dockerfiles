# valheim

Valheim dedicated server image, published as `ghcr.io/dtandersen/valheim`.

It runs non-root (UID/GID 568, the TrueCharts default) and contains the
server's runtime libraries plus SteamCMD. The game itself is never baked in —
SteamCMD installs app `896660` into `/data` on start.

```console
$ docker run --rm -v valheim-data:/data -e SERVER_PW=changeme ghcr.io/dtandersen/valheim
```

## Entrypoint

1. Updates SteamCMD itself, refreshes Steam app metadata with
   `app_info_update 1`, then installs/updates app `896660` into `/data`, unless
   `STEAMCMD_UPDATE` is false. If `STEAMCMD_RESET_APP` is true, it first removes
   only that app's manifest (`steamapps/appmanifest_896660.acf`) plus its
   `downloading`/`temp` state to recover from stale/corrupt metadata.
   On update failure it prints matching `content_log.txt` entries when available.
   SteamCMD can exit 0 while still printing
   `Error! App '896660' state is 0x6/0x602 after update job`, so the script
   treats that output as failure too and exits instead of starting a stale server.
   `0x6` (no connection to content servers / stuck manifest) is the known case
   where deleting the app manifest and retrying recovers.
2. Appends SteamCMD's `validate`, unless `STEAMCMD_VALIDATE` is false. `validate`
   re-reads the whole install, so disabling it makes startup much faster.
3. Prepends `<install dir>/linux64` to `LD_LIBRARY_PATH`.
4. Runs `/data/start_server_bepinex.sh` when BepInEx is present, otherwise
   `/data/valheim_server.x86_64`, with:

   ```text
   -batchmode -nographics -name … -port … -world … -public … -savedir …
   [-password …] [-saveinterval …] [-backups …] [-backupshort …] [-backuplong …]
   [-crossplay]
   ```

   Empty values omit their flag, so exporting `SERVER_BACKUPS=` drops `-backups`
   and letting Valheim apply its own default.

The entrypoint `exec`s the server, so it stays PID 1 and receives signals
directly. `STEAMCMD_UPDATE` and `STEAMCMD_VALIDATE` accept booleans: `1`/`true`,
`yes`, `on` (any case) are true, anything else is false.

### SteamCMD

| Env | Default |
|---|---|
| `STEAMCMD_UPDATE` | `true` |
| `STEAMCMD_VALIDATE` | `true` |
| `STEAMCMD_RESET_APP` | `false` |

SteamCMD is fixed at `/opt/steamcmd/steamcmd.sh`, installs into `/data` and logs
in anonymously. The app id (`896660`), install directory (`/data`) and save
directory (`worlds`) are not configurable, because the image is Valheim-specific.

### Server

| Env | Default |
|---|---|
| `SERVER_NAME` | `Valheim` |
| `SERVER_PORT` | `2456` |
| `SERVER_PUBLIC` | `1` |
| `SERVER_WORLD_NAME` | `Dedicated` |
| `SERVER_PW` | empty → `-password` omitted |
| `SERVER_SAVE_INTERVAL` | `1800` |
| `SERVER_BACKUPS` | `4` |
| `SERVER_BACKUP_SHORT` | `7200` |
| `SERVER_BACKUP_LONG` | `43200` |
| `SERVER_CROSSPLAY` | `false` |
| `SERVER_ADMINS` | empty |
| `ADDITIONAL_ARGS` | empty |

`SERVER_PUBLIC` is passed straight to the server's `-public` flag, so it takes
`0` or `1`. `SERVER_PW` is the server password — Valheim requires at least 5
characters — and when it is empty `-password` is omitted, in which case the
server may refuse to start. `SERVER_CROSSPLAY` adds `-crossplay`, which routes
through PlayFab so console players can join.

`SERVER_ADMINS` is a space-separated list of SteamID64s. On start each id is
appended to `<saveDir>/adminlist.txt` if it is not already there, so it is
idempotent and survives the file being recreated with a new world. Non-numeric
entries are skipped with a warning.

SteamCMD writes to `$HOME` (`/home/steam`) and `/opt/steamcmd`, so the container
needs a writable root filesystem or writable volumes at those paths.

The image sets `SteamAppId=892970` (Valheim's game id, distinct from the
`896660` dedicated server app) so the server registers with Steam.

## Image

- Base: `debian:13-slim`, pinned by digest
- Runtime libraries: `libatomic1`, `libpulse0`, `libstdc++6`, `libgcc-s1`
- SteamCMD: pinned `steamcmd_linux.tar.gz` (SHA256-verified) into `/opt/steamcmd`
- SteamCMD deps: `lib32gcc-s1`, `lib32stdc++6` (i386)
- Platform: `linux/amd64` only, since SteamCMD is x86

Images are built by
[.github/workflows/valheim.yaml](../../.github/workflows/valheim.yaml) on every
push to `main` that touches `images/valheim/` and on demand, but those builds
are only a check: nothing is published. Only a release tag
`valheim-v<version>` publishes, as image tag `<version>`. Branch and `latest`
tags are never moved by a commit, because `charts/valheim` pulls `:latest` and
a running server must not change under an ordinary push.
