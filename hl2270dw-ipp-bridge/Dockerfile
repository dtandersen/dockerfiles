# CUPS IPP-Everywhere bridge for Brother HL-2270DW.
#
# The HL-2270DW speaks IPP 1.0 + PCL only, so Windows Protected Print
# (Mopria / IPP Everywhere + PDF/PWG) rejects it natively. This image
# fronts it with CUPS IPP 2.1: Windows sends PDF, CUPS renders PDF -> PCL
# via Ghostscript + brlaser, then forwards RAW to the printer on port 9100.
#
# Rebuild tracking:
#   docker build -t ghcr.io/dtandersen/hl2270dw-ipp-bridge:<tag> .
#   docker push ghcr.io/dtandersen/hl2270dw-ipp-bridge:<tag>
# then point image in the printer k8s manifest
# ../printer/k8s.yaml at the new tag.
ARG DEBIAN_RELEASE=trixie-slim
FROM debian:${DEBIAN_RELEASE}

ENV DEBIAN_FRONTEND=noninteractive \
    CUPS_WEBIF=yes \
    PRINTER_NAME=HL2270DW \
    PRINTER_DEVICE_URI=socket://192.168.3.28:9100

RUN apt-get update && apt-get install -y --no-install-recommends \
      cups \
      cups-filters \
      cups-ipp-utils \
      printer-driver-brlaser \
      printer-driver-splix \
      ghostscript \
      qpdf \
      poppler-utils \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /etc/cups /var/spool/cups /var/cache/cups

COPY cupsd.conf /etc/cups/cupsd.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 631/tcp

VOLUME ["/etc/cups", "/var/spool/cups", "/var/cache/cups"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["cupsd", "-f"]
