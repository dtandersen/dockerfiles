# valheim

Helm chart for the [Valheim](https://valheim.com/support/a-guide-to-dedicated-servers/)
dedicated server. It runs the
[`valheim`](https://github.com/dtandersen/valheim-docker) image, whose
entrypoint installs/updates Steam app `896660` with SteamCMD and launches the
server. It is built on the TrueCharts
[`common`](https://truecharts.org/common/) library chart.

## Values

```yaml
valheim:
  update: true
  verify: true
  name: Valheim
  port: 2456
  public: false
  world: Dedicated
  password: ""
  saveInterval: 1800
  backups: 4
  backupShort: 7200
  backupLong: 43200
  crossplay: false
  administrators: []
  additionalArgs: ""
```

These are rendered as the image's `STEAMCMD_*` and `SERVER_*` environment
variables, except `valheim.password`: it is rendered into a `valheim-password`
Secret and consumed with a `secretKeyRef`, so it never appears in the
Deployment. When it is empty the chart generates a random 8-character
alphanumeric password, which rotates on every render — set it to pin one.
`valheim.port` is the game port, and the Steam query port is always
`valheim.port + 1` — change the service ports to match if you change it.
`valheim.public` is a boolean and defaults to `false`, so the server is not
listed in the Steam server browser; set it to `true` to publish it. The chart
renders it as the `0`/`1` the server's `-public` flag expects.
`valheim.saveInterval`, `valheim.backups`, `valheim.backupShort`, and
`valheim.backupLong` map to the server's save and backup flags, and
`valheim.crossplay` adds `-crossplay` for console cross-play, and
`valheim.administrators` is a list of SteamID64s the entrypoint adds to the
server's admin list on start.
`valheim.update` defaults to `true` and makes the entrypoint run `app_update`
on every start; set it to `false` to skip updating on restarts. `valheim.verify`
defaults to `true` and adds SteamCMD's `validate`, which re-reads the whole
install; set it to `false` to make updates fast (only changed files).

The chart also ships these defaults:

- `image` — `ghcr.io/dtandersen/valheim:latest`, which bundles SteamCMD and the
  server's runtime libraries
- a `valheim-password` Secret holding `valheim.password`, randomly generated
  when that value is empty
- a `Deployment` (single replica, `Recreate`) with a PVC at `/data` for server
  files and worlds
- a ClusterIP service with UDP `2456` (game) and `2457` (query)
- `readOnlyRootFilesystem: false`, because SteamCMD writes to its install
  directory and `$HOME`
- no probes, since the game server exposes no HTTP endpoint
- `terminationGracePeriodSeconds: 120` and a `preStop` that sends `SIGINT`, so
  Valheim saves its world before the pod stops

Routes are not created by the chart. Declare them in the release, for example
with the gateway's `extraTpl` (note `UDPRoute` is only served at `v1alpha2`):

```yaml
extraTpl:
  - apiVersion: gateway.networking.k8s.io/v1alpha2
    kind: UDPRoute
    metadata:
      name: valheim-game
      namespace: valheim
    spec:
      parentRefs:
        - name: envoy
          namespace: default
          sectionName: valheim-udp
      rules:
        - backendRefs:
            - name: valheim
              port: 2456
```

All other values are supplied by the TrueCharts common chart. See the [common
chart documentation](https://truecharts.org/common/) for options including
`resources`, `podOptions`, `persistence`, `service`, `ingress`, `hpa`, and
security contexts.

## Helmfile

```yaml
releases:
  - name: valheim
    chart: dtandersen/valheim
    namespace: valheim
    createNamespace: true
    values:
      - valheim:
          name: Valheim
          world: Dedicated
          password: changeme
        podOptions:
          nodeSelector:
            kubernetes.io/hostname: kube-2
        persistence:
          data:
            storageClass: retain
            size: 20Gi
```

## Installation

Add the Helm repository and install the chart:

```console
helm repo add dtandersen https://dtandersen.github.io/dockerfiles
helm install valheim dtandersen/valheim \
  --namespace valheim \
  --create-namespace \
  --set valheim.password=changeme
```

The `common` dependency is bundled in the published chart package.

## Upstream

- Valheim dedicated server guide: <https://valheim.com/support/a-guide-to-dedicated-servers/>
- Image source: <https://github.com/dtandersen/valheim-docker>
- Default image: <https://github.com/dtandersen/valheim-docker/pkgs/container/valheim>
- TrueCharts common: <https://truecharts.org/common/>
