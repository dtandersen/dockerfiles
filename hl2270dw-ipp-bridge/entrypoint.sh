#!/bin/bash
set -e

PRINTER_NAME="${PRINTER_NAME:-HL2270DW}"
PRINTER_DEVICE_URI="${PRINTER_DEVICE_URI:-socket://192.168.100.1:9100}"
PRINTER_PPD="${PRINTER_PPD:-}"
PRINTER_UUID="${PRINTER_UUID:-470de2bc-eda2-3374-6bc0-f1c4644d6cdd}"
PRINTER_PAPER_SIZE="${PRINTER_PAPER_SIZE:-Letter}"
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

# Backend TLS: /tls comes from the printer-tls secret (pinned self-signed
# CN=printer.local, or LE when printer.home was used). CUPS serves TLS on
# the same port when server.crt exists, so the TCP passthrough serves
# an encrypted connection end-to-end and CUPS advertises ipps:// URLs.
if [ -f /tls/tls.crt ] && [ -f /tls/tls.key ]; then
  mkdir -p /etc/cups/ssl
  cp /tls/tls.crt /etc/cups/ssl/server.crt
  cp /tls/tls.key /etc/cups/ssl/server.key
  # CUPS serves the ServerName cert (0.0.0.0.crt), not server.crt —
  # install the pinned cert under both names so TLS carries the right chain.
  cp /tls/tls.crt /etc/cups/ssl/0.0.0.0.crt
  cp /tls/tls.key /etc/cups/ssl/0.0.0.0.key
  chmod 600 /etc/cups/ssl/server.key /etc/cups/ssl/0.0.0.0.key
  # CUPS 2.4 selects the server cert by reverse-lookup of the local address
  # (getsockname + httpAddrLookup), NOT by ServerName. Pod IP reverses via
  # /etc/hosts to the pod hostname, localhost falls back to 0.0.0.0. With
  # CreateSelfSignedCerts No and no per-host cert, remote TLS fails while
  # localhost succeeds. Install the pinned cert under every name CUPS may pick.
  POD_HOST="$(hostname 2>/dev/null || true)"
  for CN_NAME in "$POD_HOST" "printer.local" "printer.home.davidandersen.us" "localhost"; do
    if [ -n "$CN_NAME" ]; then
      cp /tls/tls.crt "/etc/cups/ssl/${CN_NAME}.crt"
      cp /tls/tls.key "/etc/cups/ssl/${CN_NAME}.key"
      chmod 600 "/etc/cups/ssl/${CN_NAME}.key"
    fi
  done
  # Stop CUPS from generating/regenerating 0.0.0.0.crt (ServerName cert)
  # which it prefers over server.crt. With No, final cupsd serves server.crt (LE).
  printf "CreateSelfSignedCerts No\n" > /etc/cups/cups-files.conf
else
  # No /tls mount (TCP passthrough for printer.local): CUPS runs as lp and
  # cannot mint its own server credentials (see "Unable to create server
  # credentials" in error_log). Generate a self-signed cert at startup with
  # openssl so CUPS serves TLS end-to-end through the Envoy TCP passthrough.
  # CUPS 2.4 picks the cert by reverse-lookup of the local address, so
  # install under every name it may pick.
  POD_HOST="$(hostname 2>/dev/null || true)"
  mkdir -p /etc/cups/ssl
  if [ ! -f /etc/cups/ssl/server.crt ]; then
    openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout /etc/cups/ssl/server.key -out /etc/cups/ssl/server.crt \
      -days 825 -subj "/CN=printer.local" \
      -addext "subjectAltName=DNS:printer.local,DNS:localhost,DNS:${POD_HOST}" \
      2>/dev/null
    chmod 600 /etc/cups/ssl/server.key
  fi
  for CN_NAME in "$POD_HOST" "printer.local" "localhost" "0.0.0.0"; do
    if [ -n "$CN_NAME" ] && [ ! -f "/etc/cups/ssl/${CN_NAME}.crt" ]; then
      cp /etc/cups/ssl/server.crt "/etc/cups/ssl/${CN_NAME}.crt"
      cp /etc/cups/ssl/server.key "/etc/cups/ssl/${CN_NAME}.key"
      chmod 600 "/etc/cups/ssl/${CN_NAME}.key"
    fi
  done
  printf "CreateSelfSignedCerts No\n" > /etc/cups/cups-files.conf
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
  echo "Creating printer $PRINTER_NAME -> $PRINTER_DEVICE_URI with PPD $PPD paper $PRINTER_PAPER_SIZE"
  lpadmin -p "$PRINTER_NAME" \
    -E \
    -v "$PRINTER_DEVICE_URI" \
    -m "$PPD" \
    -o printer-is-shared=true \
    -o print-color-mode-default=monochrome \
    -o PageSize="$PRINTER_PAPER_SIZE" \
    -D "Brother HL-L2370DN series via IPP bridge" \
    -L "k8s-ipp-bridge" || {
      echo "brlaser PPD failed, falling back to Generic PCL"
      lpadmin -p "$PRINTER_NAME" -E -v "$PRINTER_DEVICE_URI" \
        -m drv:///sample.drv/generpcl.ppd \
        -o printer-is-shared=true \
        -o PageSize="$PRINTER_PAPER_SIZE" || true
    }
  cupsenable "$PRINTER_NAME" || true
  cupsaccept "$PRINTER_NAME" || true
else
  echo "Printer $PRINTER_NAME already exists, enabling sharing paper $PRINTER_PAPER_SIZE"
  lpadmin -p "$PRINTER_NAME" -o printer-is-shared=true || true
  lpadmin -p "$PRINTER_NAME" -o PageSize="$PRINTER_PAPER_SIZE" || true
  cupsenable "$PRINTER_NAME" || true
  cupsaccept "$PRINTER_NAME" || true
fi

# System paper default for libpaper-aware filters (lowercase: letter).
echo "$PRINTER_PAPER_SIZE" | tr '[:upper:]' '[:lower:]' > /etc/papersize 2>/dev/null || true

lpstat -v || true

# Stop temp cupsd, exec foreground for container / k8s
kill %1 2>/dev/null || pkill cupsd || true
sleep 1

# Pin a stable printer-uuid so IPP and DNS-SD agree across restarts.
# CUPS mints a fresh UUID at queue creation and /etc/cups is emptyDir,
# so without this every pod restart breaks Windows' bound device identity.
# Canonical: 470de2bc-eda2-3374-6bc0-f1c4644d6cdd (must match Avahi TXT UUID).
if [ -n "${PRINTER_UUID:-}" ]; then
  case "$PRINTER_UUID" in
    urn:uuid:*) UUID_VAL="$PRINTER_UUID" ;;
    *) UUID_VAL="urn:uuid:$PRINTER_UUID" ;;
  esac
  if [ -f /etc/cups/printers.conf ]; then
    sed -i -E "s|^UUID .*|UUID $UUID_VAL|" /etc/cups/printers.conf || true
  fi
fi

# CUPS prefers the ServerName cert (0.0.0.0.crt) over server.crt and
# regenerates it on every startup when CreateSelfSignedCerts is Yes.
# Early block disables auto-generation; refresh all names with the pinned
# /tls cert so final cupsd serves TLS with the same chain.
if [ -f /tls/tls.crt ] && [ -f /tls/tls.key ]; then
  cp /tls/tls.crt /etc/cups/ssl/server.crt
  cp /tls/tls.key /etc/cups/ssl/server.key
  cp /tls/tls.crt /etc/cups/ssl/0.0.0.0.crt
  cp /tls/tls.key /etc/cups/ssl/0.0.0.0.key
  chmod 600 /etc/cups/ssl/server.key /etc/cups/ssl/0.0.0.0.key
  # Same per-host install for the final cupsd (pod hostname via reverse lookup).
  POD_HOST="$(hostname 2>/dev/null || true)"
  for CN_NAME in "$POD_HOST" "printer.local" "printer.home.davidandersen.us" "localhost"; do
    if [ -n "$CN_NAME" ]; then
      cp /tls/tls.crt "/etc/cups/ssl/${CN_NAME}.crt"
      cp /tls/tls.key "/etc/cups/ssl/${CN_NAME}.key"
      chmod 600 "/etc/cups/ssl/${CN_NAME}.key"
    fi
  done
fi

echo "Bridge ready (as $(id -u):$(id -g)): http://<service-ip>:631/printers/$PRINTER_NAME -> 127.0.0.1:${CUPS_PORT}"
echo "Backend: $PRINTER_DEVICE_URI"
exec /usr/sbin/cupsd -f
