# remote-pi-relay

Helm chart for the [Remote Pi relay](https://github.com/jacobaraujo7/remote_pi/tree/main/relay)
(`jacobmoura7/remote-pi-relay`), so Pi agents and the mobile app can mesh
without the public relay. It is built on the TrueCharts
[`common`](https://truecharts.org/common/) library chart.

The relay is a single-port Rust server: WebSocket upgrade (`/`), `GET
/health` (`200 OK`), and `GET`/`POST /mesh/<owner_pk_hash>` (Owner-signed
membership blobs, Ed25519-verified, monotonic, 500 KB cap). State is one
SQLite file (`mesh.db`, rollback-journal mode) holding membership
authorization metadata only — never message traffic.

## Values

```yaml
relay:
  port: 3000
  dbPath: /data/mesh.db
  logLevel: info
```

These render as the image's `REMOTEPI_RELAY_PORT`, `REMOTEPI_MESH_DB_PATH`,
and `RUST_LOG` environment variables.

The chart also ships these defaults:

- image `jacobmoura7/remote-pi-relay:v0.3.1`
- a `Deployment` (single replica, `Recreate` — one SQLite writer) with HTTP
  probes on `/health`
- a `ClusterIP` service on TCP `3000` -> container `3000`
- a retained `1Gi` PVC mounted at `/data` (membership blobs survive restarts;
  without it clients re-publish at their next mutation)

All other values are supplied by the TrueCharts common chart. See the [common
docs](https://truecharts.org/common/) for `service`, `workload`, `persistence`,
`ingress`, etc.

## Point Pi at it

```text
/remote-pi set-relay https://relay.yourdomain.tld
```

Only `http(s)://` is accepted (the extension converts to `ws(s)://`
internally). Or override one run: `REMOTE_PI_RELAY=https://relay.yourdomain.tld
pi`. Verify with `/remote-pi config`. The mobile app has its own relay-URL
setting — keep both on the same relay. If you change URLs while connected:
`/remote-pi stop` then `/remote-pi` again.

Resolution order: `REMOTE_PI_RELAY` env > `~/.pi/remote/config.json` > built-in
default (`https://relay-rp1.jacobmoura.work`).

## Exposing it

Terminate TLS in front (Caddy example from upstream):

```caddy
relay.yourdomain.com {
    reverse_proxy localhost:3000
}
```

In this repo, front the `ClusterIP` with the Envoy Gateway snippet (same
pattern as `hl2270dw-ipp-bridge` `printer-ipp`) or switch
`service.main.type` to `LoadBalancer` and put it behind Tailscale/WireGuard
so only your devices reach the WebSocket port.

## Helmfile

```yaml
releases:
  - name: remote-pi-relay
    chart: ../charts/charts/remote-pi-relay
    namespace: remote-pi
    createNamespace: true
    values:
      - relay:
          port: 3000
        service:
          main:
            type: ClusterIP
```

## Upgrades

Relay `0.3` first, then Extension `0.6` (mixed old/new Extension wire labels
are deferred — see upstream [Plan
51](https://github.com/jacobaraujo7/remote_pi/blob/main/plan/51-cross-pc-mesh-routing-hardening.md)).
