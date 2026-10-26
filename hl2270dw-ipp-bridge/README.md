# hl2270dw-ipp-bridge

CUPS IPP-Everywhere bridge for the Brother HL-2270DW, so Windows 11
Protected Print mode can use it.

The printer alone is IPP 1.0 + PCL-only (no PDF/PWG-Raster, not Mopria
certified). This image fronts it with CUPS IPP 2.0/2.1 +
`mopria-certified 1.3`, advertising `application/pdf, image/pwg-raster,
image/urf`. Windows sends PDF to the bridge, CUPS renders PDF -> PCL via
Ghostscript + brlaser, then forwards RAW to the printer.

## Ports

- 8631/tcp — IPP (`ipp://<host>:8631/printers/HL2270DW`). Runs as `lp`
  (uid/gid 7, created by the cups package), no root, no capabilities. Map to
  host 631 with `-p 631:8631` so Windows URLs stay on standard IPP port 631.

## Settings

Everything is an environment variable. Defaults work out of the box.

- PRINTER_NAME — CUPS queue name (default HL2270DW)
- PRINTER_DEVICE_URI — backend URI (default socket://192.168.100.1:9100)
- PRINTER_PPD — PPD override, e.g. drv:///brlaser.drv/brl2370d.ppd (default: auto-pick certified-family 2370dn > 2270dw > brlaser > generpcl)
- CUPS_PORT — container listen port (default 8631, unprivileged so no root needed)

## Example

```sh
docker run -d --name ipp-bridge -p 631:8631 \
  -e PRINTER_DEVICE_URI=socket://192.168.100.1:9100 \
  ghcr.io/dtandersen/hl2270dw-ipp-bridge:main
```

Print path: `http://<host>:631/printers/HL2270DW` (container listens on 8631).
CUPS web UI: http://localhost:631/printers/HL2270DW

Add to Windows 11 with Protected Print ON manually by URL:

```text
http://<bridge-ip>:631/printers/HL2270DW
```

Driver: Microsoft IPP Class Driver (inbox, automatic in WPP mode).

## Mopria shield (green check)

Adding by URL alone registers as generic IPP — no shield. The bridge
advertises itself as **Brother HL-L2370DN series** (Mopria-certified family,
same mono-laser engine, brlaser `brl2370d.ppd`) instead of the HL-2270DW,
which was never certified. For Windows to treat it as Mopria-compatible it
must be *discovered* over mDNS, not typed in as a URL — and a k8s pod's
multicast never reaches the LAN. So:

1. Copy `avahi-bridge.service` to any Linux host on the same LAN as the
   Windows clients (`/etc/avahi/services/`, replace `%BRIDGE_HOST%` with
   the bridge's LAN IP), `sudo systemctl reload avahi-daemon`.
2. On Windows, REMOVE the manually-added printer, then Add device and pick
   the discovered "Brother HL-L2370DN series".
3. The shield appears only if Windows accepts the self-claimed identity —
   this is not a real certification, and a PC-wide Protected Print
   enable may still drop the queue. If no shield, nothing further on the
   bridge side can force it.

## Kubernetes

See `../printer/k8s.yaml` for a Namespace + Deployment + LoadBalancer
example. Two caveats: the pod must route to the printer on TCP 9100, and
Windows must reach the Service on TCP 631 (LoadBalancer/NodePort —
ClusterIP alone is not enough). No mDNS through k8s, so add by URL.
