#!/bin/bash
set -e

PRINTER_NAME="${PRINTER_NAME:-HL2270DW}"
PRINTER_DEVICE_URI="${PRINTER_DEVICE_URI:-socket://192.168.3.28:9100}"
PRINTER_PPD="${PRINTER_PPD:-}"

# 1. Ensure cupsd dirs exist (k8s emptyDir / PVC mounts come up empty)
mkdir -p /etc/cups /var/spool/cups /var/cache/cups /run/cups

# 3. Pick a PPD: explicit $PRINTER_PPD > brlaser HL-2270DW > generic PCL
pick_ppd() {
  if [ -n "$PRINTER_PPD" ]; then
    echo "$PRINTER_PPD"
    return
  fi
  if command -v lpinfo >/dev/null 2>&1; then
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
    -D "Brother HL-2270DW via IPP bridge" \
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

echo "Bridge ready: ipp://<service-ip>:631/printers/$PRINTER_NAME"
echo "Backend: $PRINTER_DEVICE_URI"
exec /usr/sbin/cupsd -f
