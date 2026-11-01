# hl2270dw-ipp-bridge

Helm chart for the Brother HL-2270DW CUPS IPP-Everywhere bridge, so
Windows 11 Protected Print mode can use it. It deploys the
[`hl2270dw-ipp-bridge`](https://github.com/dtandersen/dockerfiles/tree/main/hl2270dw-ipp-bridge)
image. It is built on the TrueCharts
[`common`](https://truecharts.org/common/) library chart.

The printer alone is IPP 1.0 + PCL-only (no PDF/PWG-Raster, not Mopria
certified). The bridge fronts it with CUPS IPP 2.0/2.1 +
`mopria-certified 1.3`, advertising `application/pdf, image/pwg-raster,
image/urf`. Windows sends PDF to the bridge, CUPS renders PDF -> PCL via
Ghostscript + brlaser, then forwards RAW to the printer.

## Values

```yaml
printer:
  name: HL2270DW
  deviceUri: socket://192.168.100.1:9100
  ppd: ""
  uuid: 079ac6e8-ea74-4414-9cc2-0553b5a414c3
```

These render as the image's `PRINTER_NAME`, `PRINTER_DEVICE_URI`, and
`PRINTER_PPD` environment variables. `printer.name` is the CUPS queue name,
also the IPP resource path `ipp://<svc>:631/printers/<name>`.
`printer.deviceUri` is the backend URI — `socket/9100` RAW is most reliable
for the HL-2270DW; change it if your printer DHCP moves. `printer.ppd`
overrides the driver (e.g. `drv:///brlaser.drv/brl2370d.ppd`); empty means
auto-pick certified-family 2370dn > 2270dw > brlaser > generpcl. The default
advertises the queue as **Brother HL-L2370DN series** (Mopria-certified
family) rather than the HL-2270DW, which was never certified.

`printer.uuid` becomes `PRINTER_UUID`. Set it explicitly: CUPS mints a new
UUID on every start, and Windows caches the UUID against the printer it
discovered, so a changing one makes Windows treat the queue as a different
device after each pod restart. It must also equal the UUID in the Avahi
`_ipps` TXT record used for discovery — if the two disagree, Windows
registers a queue whose identity CUPS does not recognise. The committed
default is a placeholder; give each deployment its own.

The chart also ships these defaults:

- image `ghcr.io/dtandersen/hl2270dw-ipp-bridge:main`
- a `Deployment` (single replica, `Recreate`) with `emptyDir` volumes for
  `/etc/cups`, `/var/spool/cups`, `/var/cache/cups`
- a `LoadBalancer` service on TCP `631` -> container `8631` (Windows must reach IPP on the LAN —
  ClusterIP alone is not enough; the container listens on unprivileged 8631).
  A Gateway API listener publishing port `631` in front of a `ClusterIP`
  service works instead when the gateway address is what clients resolve.
- TCP probes on `8631`
- `lp` (uid/gid 7, created by the cups package) via a minimal securityContext
  override — TrueCharts defaults to 568, but `lp` already owns CUPS spool/cache
  dirs. Still no root, no capabilities; unprivileged 8631, logs to stderr;
  `/etc/cups`, `/var/spool/cups`, `/var/cache/cups` are writable `emptyDir` mounts

There is no mDNS through Kubernetes, so Windows cannot discover the bridge
on its own — and a manually-added URL registers as generic IPP with no
Mopria shield. For discovery, copy the image's `avahi-bridge.service` to a
Linux host on the same LAN (replace `%BRIDGE_HOST%` with the bridge's LAN
IP), remove the manual-URL printer on Windows, and re-add the discovered
"Brother HL-L2370DN series":

```text
http://<bridge-ip>:631/printers/<printer.name>
```

The queue name in that URL is `printer.name`, and the TXT record's UUID must
match `printer.uuid`.

Driver: Microsoft IPP Class Driver (inbox, automatic in Protected Print mode).
Pin a stable LAN IP with `service.main.loadBalancerIP` (MetalLB pool, same
subnet as Windows clients) so the URL survives pod restarts, or switch
`service.main.type` to `NodePort` without MetalLB.

## Helmfile

```yaml
repositories:
  - name: dtandersen-charts
    url: https://dtandersen.github.io/dockerfiles

releases:
  - name: hl2270dw-ipp-bridge
    chart: dtandersen-charts/hl2270dw-ipp-bridge
    namespace: printing
    createNamespace: true
    values:
      - printer:
          deviceUri: socket://192.168.100.1:9100
          uuid: 079ac6e8-ea74-4414-9cc2-0553b5a414c3
        service:
          main:
            # loadBalancerIP: 192.168.100.10
            type: LoadBalancer
```

All other values are supplied by the TrueCharts common chart. See the [common
chart documentation](https://truecharts.org/common/) for options including
`resources`, `podOptions`, `persistence`, `service`, `ingress`, `hpa`, and
security contexts.
