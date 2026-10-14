#!/bin/sh
# Container entrypoint for XeStrata.
# Runs the interactive setup once (non-interactive flags), then starts the
# server in the foreground. Configuration is driven by chart values via env.
set -eu

DATA_DIR="${XESTRATA_DATA_DIR:-/data}"
CONFIG_DIR="${XESTRATA_CONFIG_DIR:-/config}"
MODEL="${XESTRATA_MODEL:-IQ2_XS}"
FAMILY="${XESTRATA_FAMILY:-}"
CONTEXT="${XESTRATA_CONTEXT:-32768}"

export XDG_CONFIG_HOME="${CONFIG_DIR}"
export XDG_DATA_HOME="${DATA_DIR}"

mkdir -p "${DATA_DIR}" "${CONFIG_DIR}"

# First start: fetch the model (60-110 GB) and write the server config.
# Settings land under ${CONFIG_DIR}/xestrata, models under ${DATA_DIR}.
if [ ! -f "${CONFIG_DIR}/xestrata/settings.json" ]; then
  # Build mode, toolchain and vision are baked into the image (they must
  # match engine/BUILD.json's stamp; this is a text-only image, the image
  # encoders are not built); not configurable on purpose.
  SETUP_ARGS="--setup --data-dir ${DATA_DIR} --model ${MODEL} --license contrib --intel-llvm /opt/xestrata/.tools/intel-llvm-contrib/install --context ${CONTEXT} --vision no --port 8095 --yes"
  if [ -n "${FAMILY}" ]; then
    # shellcheck disable=SC2086
    xestrata ${SETUP_ARGS} --family "${FAMILY}"
  else
    # shellcheck disable=SC2086
    xestrata ${SETUP_ARGS}
  fi
fi

# Optional engine tuning: XESTRATA_POOL_WORKERS sets --pool-workers N
# (CPU threads computing experts) in every installed model config.
# setup.py has no flag for it, so it is patched here after setup and
# before serve, on every start. Unset = engine default (calibration
# already measured it optimal on this PC; use only for A/B tests).
if [ -n "${XESTRATA_POOL_WORKERS:-}" ]; then
  if ! [ "${XESTRATA_POOL_WORKERS}" -eq "${XESTRATA_POOL_WORKERS}" ] 2>/dev/null; then
    echo "XESTRATA_POOL_WORKERS must be a number, got '${XESTRATA_POOL_WORKERS}'" >&2
    exit 1
  fi
  for cfg in /opt/xestrata/xestrata-*.json; do
    [ -f "$cfg" ] || continue
    /usr/bin/python3 - "$cfg" "${XESTRATA_POOL_WORKERS}" <<'EOF'
import json, sys
p, n = sys.argv[1], sys.argv[2]
cfg = json.load(open(p, encoding="utf-8-sig"))
args = cfg.get("args", [])
if "--pool-workers" in args:
    args[args.index("--pool-workers") + 1] = n
else:
    args += ["--pool-workers", n]
cfg["args"] = args
json.dump(cfg, open(p, "w", encoding="utf-8"), indent=1)
print(f"pool-workers {n} in {p}")
EOF
  done
fi

# Verify the exact serve flags with `xestrata --help` when bumping the image;
# upstream documents `--host 0.0.0.0 --api-key <secret>` for remote access.
if [ -n "${XESTRATA_API_KEY:-}" ]; then
  exec xestrata --host 0.0.0.0 --port 8095 --api-key "${XESTRATA_API_KEY}"
else
  exec xestrata --host 0.0.0.0 --port 8095
fi
