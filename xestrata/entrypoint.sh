#!/bin/sh
# Container entrypoint for XeStrata.
# Runs the interactive setup once (non-interactive flags), then starts the
# server in the foreground. Configuration is driven by chart values via env.
set -eu

DATA_DIR="${XESTRATA_DATA_DIR:-/data}"
CONFIG_DIR="${XESTRATA_CONFIG_DIR:-/config}"
PORT="${XESTRATA_PORT:-8095}"
MODEL="${XESTRATA_MODEL:-IQ2_XS}"
FAMILY="${XESTRATA_FAMILY:-}"
CONTEXT="${XESTRATA_CONTEXT:-32768}"
VISION="${XESTRATA_VISION:-no}"

export XDG_CONFIG_HOME="${CONFIG_DIR}"
export XDG_DATA_HOME="${DATA_DIR}"

mkdir -p "${DATA_DIR}" "${CONFIG_DIR}"

# First start: fetch the model (60-110 GB) and write the server config.
# Settings land under ${CONFIG_DIR}/xestrata, models under ${DATA_DIR}.
if [ ! -f "${CONFIG_DIR}/xestrata/settings.json" ]; then
  SETUP_ARGS="--setup --data-dir ${DATA_DIR} --model ${MODEL} --context ${CONTEXT} --vision ${VISION} --port ${PORT} --yes"
  if [ -n "${FAMILY}" ]; then
    # shellcheck disable=SC2086
    xestrata ${SETUP_ARGS} --family "${FAMILY}"
  else
    # shellcheck disable=SC2086
    xestrata ${SETUP_ARGS}
  fi
fi

# Verify the exact serve flags with `xestrata --help` when bumping the image;
# upstream documents `--host 0.0.0.0 --api-key <secret>` for remote access.
if [ -n "${XESTRATA_API_KEY:-}" ]; then
  exec xestrata --host 0.0.0.0 --port "${PORT}" --api-key "${XESTRATA_API_KEY}"
else
  exec xestrata --host 0.0.0.0 --port "${PORT}"
fi
