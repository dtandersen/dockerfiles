# hl2270dw-ipp-bridge

CUPS IPP-Everywhere bridge for the Brother HL-2270DW, so Windows 11
Protected Print mode can use it.

The printer alone is IPP 1.0 + PCL-only (no PDF/PWG-Raster, not Mopria
certified). This image fronts it with CUPS IPP 2.0/2.1 +
`mopria-certified 1.3`, advertising `application/pdf, image/pwg-raster,
image/urf`. Windows sends PDF to the bridge, CUPS renders PDF -> PCL via
Ghostscript + brlaser, then forwards RAW to the printer.

## Ports

- 631/tcp — IPP (`ipp://<host>:631/printers/HL2270DW`)

## Settings

Everything is an environment variable. Defaults work out of the box.

- PRINTER_NAME — CUPS queue name (default HL2270DW)
- PRINTER_DEVICE_URI — backend URI (default socket://192.168.3.28:9100)
- PRINTER_PPD — PPD override, e.g. drv:///brlaser.drv/br2270dw.ppd (default: auto-pick 2270dw > brlaser > generpcl)

## Example

```sh
docker run -d --name ipp-bridge -p 631:631 \
  -e PRINTER_DEVICE_URI=socket://192.168.3.28:9100 \
  ghcr.io/dtandersen/hl2270dw-ipp-bridge:main
```

Print path: `ipp://<host>:631/printers/HL2270DW`.
CUPS web UI: http://localhost:631/printers/HL2270DW

Add to Windows 11 with Protected Print ON manually by URL:

```text
http://<bridge-ip>:631/printers/HL2270DW
```

Driver: Microsoft IPP Class Driver (inbox, automatic in WPP mode).

## Kubernetes

See `../printer/k8s.yaml` for a Namespace + Deployment + LoadBalancer
example. Two caveats: the pod must route to the printer on TCP 9100, and
Windows must reach the Service on TCP 631 (LoadBalancer/NodePort —
ClusterIP alone is not enough). No mDNS through k8s, so add by URL.
