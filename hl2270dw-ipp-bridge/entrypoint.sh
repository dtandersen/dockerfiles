#!/bin/bash
set -e

PRINTER_NAME="${PRINTER_NAME:-HL2270DW}"
PRINTER_DEVICE_URI="${PRINTER_DEVICE_URI:-socket://192.168.100.1:9100}"
PRINTER_PPD="${PRINTER_PPD:-}"
CUPS_PORT="${CUPS_PORT:-8631}"

# Talk to cupsd over TCP (no /run/cups domain socket when unprivileged).
export CUPS_SERVER="127.0.0.1:${CUPS_PORT}"

# 1. Ensure cupsd dirs exist (k8s emptyDir / PVC mounts come up empty).
# No /run/cups here: /run is root-owned and the unprivileged lp user cannot
# socket lives at /tmp/cups.sock (see cupsd.conf) and /tmp is world-writable.
mkdir -p /etc/cups /var/spool/cups /var/cache/cups

# k8s emptyDir on /etc/cups hides the image's cupsd.conf — restore it if missing.
if [ ! -s /etc/cups/cupsd.conf ] && [ -f /usr/local/share/cupsd.conf.orig ]; then
  cp /usr/local/share/cupsd.conf.orig /etc/cups/cupsd.conf
fi

# Backend TLS for Envoy Gateway origination: /tls comes from the printer-tls
# secret (LE cert). CUPS serves TLS on the same port when server.crt exists,
# so Envoy's https backend sees an encrypted connection and CUPS advertises
# ipps:// + https:// URLs instead of ipp:// + http://.
if [ -f /tls/tls.crt ] && [ -f /tls/tls.key ]; then
  mkdir -p /etc/cups/ssl
  cp /tls/tls.crt /etc/cups/ssl/server.crt
  cp /tls/tls.key /etc/cups/ssl/server.key
  chmod 600 /etc/cups/ssl/server.key
fi

# 2. Make sure cupsd.conf listens on $CUPS_PORT (image defaults to 8631).
if command -v sed >/dev/null 2>&1; then
  sed -i -E "s|^Listen 0\.0\.0\.0:[0-9]+|Listen 0.0.0.0:${CUPS_PORT}|" /etc/cups/cupsd.conf 2>/dev/null || true
fi

# 3. Pick a PPD: explicit $PRINTER_PPD > certified-family brlaser HL-L2370DN
# (Mopria-certified family, same mono-laser engine + URF) > HL-2270DW > generic PCL.
# The HL-2270DW itself is NOT Mopria certified, so advertising its PPD
# keeps Windows from showing the Mopria shield. The 2370DN PPD renders
# through the same rastertobrlaser path to the 9100 backend.
pick_ppd() {
  if [ -n "$PRINTER_PPD" ]; then
    echo "$PRINTER_PPD"
    return
  fi
  # Prefer the certified-family PPD so IPP advertises a Mopria-listed model.
  # brl2370d.ppd = "Brother HL-L2370DN series" (Mopria family, URF-capable).
  if command -v lpinfo >/dev/null 2>&1; then
    CANDIDATE=$(lpinfo -m 2>/dev/null | grep -i -m1 "2370dn" | awk '{print $1}' || true)
    if [ -n "$CANDIDATE" ]; then echo "$CANDIDATE"; return; fi
    # brlaser ships HL-2270DW support (printer-driver-brlaser)
    CANDIDATE=$(lpinfo -m 2>/dev/null | grep -i -m1 "2270dw" | awk '{print $1}' || true)
    if [ -n "$CANDIDATE" ]; then echo "$CANDIDATE"; return; fi
    CANDIDATE=$(lpinfo -m 2>/dev/null | grep -i -m1 "brlaser" | awk '{print $1}' || true)
    if [ -n "$CANDIDATE" ]; then echo "$CANDIDATE"; return; fi
    CANDIDATE=$(lpinfo -m 2>/dev/null | grep -i -m1 "generpcl\|Generic PCL" | awk '{print $1}' || true)
    if [ -n "$CANDIDATE" ]; then echo "$CANDIDATE"; return; fi
  fi
  echo "drv:///sample.drv/generpcl.ppd"
}

# 4. Start cupsd briefly to create the queue if missing, then exec real cupsd
# cupsd must be running for lpadmin/lpinfo to work.
cupsd
for i in $(seq 1 15); do
  lpstat -r 2>/dev/null | grep -q "scheduler is running" && break
  sleep 1
done

# Enable sharing cluster-wide (same-subnet only is the CUPS default, k8s needs remote-any)
# Must run after cupsd is up, otherwise: "Unable to connect to server"
cupsctl --share-printers --remote-any || true

if ! lpstat -v 2>/dev/null | grep -q "$PRINTER_NAME"; then
  PPD=$(pick_ppd)
  echo "Creating printer $PRINTER_NAME -> $PRINTER_DEVICE_URI with PPD $PPD"
  lpadmin -p "$PRINTER_NAME" \
    -E \
    -v "$PRINTER_DEVICE_URI" \
    -m "$PPD" \
    -o printer-is-shared=true \
    -o print-color-mode-default=monochrome \
    -D "Brother HL-L2370DN series via IPP bridge" \
    -L "k8s-ipp-bridge" || {
      echo "brlaser PPD failed, falling back to Generic PCL"
      lpadmin -p "$PRINTER_NAME" -E -v "$PRINTER_DEVICE_URI" \
        -m drv:///sample.drv/generpcl.ppd \
        -o printer-is-shared=true || true
    }
  cupsenable "$PRINTER_NAME" || true
  cupsaccept "$PRINTER_NAME" || true
else
  echo "Printer $PRINTER_NAME already exists, enabling sharing"
  lpadmin -p "$PRINTER_NAME" -o printer-is-shared=true || true
  cupsenable "$PRINTER_NAME" || true
  cupsaccept "$PRINTER_NAME" || true
fi

lpstat -v || true

# Stop temp cupsd, exec foreground for container / k8s
kill %1 2>/dev/null || pkill cupsd || true
sleep 1

echo "Bridge ready (as $(id -u):$(id -g)): http://<service-ip>:631/printers/$PRINTER_NAME -> 127.0.0.1:${CUPS_PORT}"
echo "Backend: $PRINTER_DEVICE_URI"
exec /usr/sbin/cupsd -f
