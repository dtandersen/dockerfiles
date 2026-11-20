# gickup

Helm chart for [gickup](https://github.com/cooperspencer/gickup), a scheduled
Git repository backup/mirror tool. It runs one `conf.yml` as a Kubernetes
CronJob using the upstream `buddyspencer/gickup` image and the TrueCharts
[`common`](https://truecharts.org/common/) library chart.

## Config

gickup reads `/gickup/conf.yml` (the image's default argument) from a
ConfigMap. For an externally managed config, create one in the release
namespace with the config under the `conf.yml` key and set
`gickup.existingConfigMap` to its name.

Keep credentials out of `conf.yml`. Gickup supports `token_file` and `sshkey`;
use absolute paths (for example `/auth/token`) and mount a Secret there via
common values:

```yaml
persistence:
  auth:
    enabled: true
    type: secret
    objectName: gickup-auth
    expandObjectName: false
    mountPath: /auth
    readOnly: true
```

Keep tokens out of chart values.

For inline configs, set `configmap.config.data.conf.yml` in the release
values. The common chart renders it verbatim as `conf.yml` in a
`<release>-config` ConfigMap. `gickup.existingConfigMap` wins when both are
set.
See the [upstream config example](https://github.com/cooperspencer/gickup/blob/main/conf.example.yml)
for sources, destinations, and filters.

Kubernetes owns the schedule, so leave `cron:` out of `conf.yml` — setting it
makes gickup run its own daemon instead of exiting after one backup.

## Values

| Key | Default | Purpose |
| --- | --- | --- |
| `gickup.schedule` | `0 3 * * *` | Five-field CronJob schedule |
| `gickup.timeZone` | `UTC` | IANA schedule time zone |
| `gickup.existingConfigMap` | `""` | ConfigMap with `conf.yml` |
| `configmap.config.data.conf.yml` | `""` | Inline `conf.yml` (no credentials) |
| `image.repository` / `image.tag` | `docker.io/buddyspencer/gickup` / `0.10.47` | Upstream first-party image |

Defaults are a single `CronJob` with `concurrencyPolicy: Forbid`, two retries,
600 s job TTL, a read-only root filesystem with `HOME=/tmp` on an `emptyDir`,
and an optional PVC at `/data` (disabled by default). Enable
`persistence.data` only when `conf.yml` uses a `destination.local` path of
`/data`; size and retention follow the common chart defaults unless overridden
in the release values.

All other values come from the common chart: `service`, `workload`,
`persistence`, `podOptions`, `securityContext`, etc.
