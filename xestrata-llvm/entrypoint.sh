#!/bin/sh
# XeStrata entrypoint: run setup once, then serve.
set -eu

DATA_DIR="${XESTRATA_DATA_DIR:-/data}"
CONFIG_DIR="${XESTRATA_CONFIG_DIR:-/config}"
MODEL="${XESTRATA_MODEL:-IQ2_XS}"
FAMILY="${XESTRATA_FAMILY:-}"
CONTEXT="${XESTRATA_CONTEXT:-32768}"

export XDG_CONFIG_HOME="${CONFIG_DIR}"
export XDG_DATA_HOME="${DATA_DIR}"

mkdir -p "${DATA_DIR}" "${CONFIG_DIR}"

if [ ! -f "${CONFIG_DIR}/xestrata/settings.json" ]; then
  LOW_RAM_ARGS=""
  if [ -n "${XESTRATA_LOW_RAM:-}" ]; then
    case "${XESTRATA_LOW_RAM}" in
      auto|on|off|resident|mmap) LOW_RAM_ARGS="--low-ram ${XESTRATA_LOW_RAM}" ;;
      *) echo "XESTRATA_LOW_RAM must be auto|on|off|resident|mmap, got '${XESTRATA_LOW_RAM}'" >&2; exit 1 ;;
    esac
  fi
  SETUP_ARGS="--setup --data-dir ${DATA_DIR} --model ${MODEL} --license contrib --intel-llvm /opt/xestrata/.tools/intel-llvm-contrib/install --context ${CONTEXT} --vision no --port 8095 --host 0.0.0.0 --yes"
  if [ -n "${FAMILY}" ]; then
    # shellcheck disable=SC2086
    xestrata ${SETUP_ARGS} ${LOW_RAM_ARGS} --family "${FAMILY}"
  else
    # shellcheck disable=SC2086
    xestrata ${SETUP_ARGS} ${LOW_RAM_ARGS}
  fi
fi

# Patched into every model config on each start. Qwen only; others ignore them.
if [ -n "${XESTRATA_VRAM_RESERVE:-}" ]; then
  if ! [ "${XESTRATA_VRAM_RESERVE}" -eq "${XESTRATA_VRAM_RESERVE}" ] 2>/dev/null || [ "${XESTRATA_VRAM_RESERVE}" -lt 0 ]; then
    echo "XESTRATA_VRAM_RESERVE must be MiB, 0 or more, got '${XESTRATA_VRAM_RESERVE}'" >&2
    exit 1
  fi
fi
if [ -n "${XESTRATA_PARALLEL:-}" ]; then
  if ! [ "${XESTRATA_PARALLEL}" -eq "${XESTRATA_PARALLEL}" ] 2>/dev/null || [ "${XESTRATA_PARALLEL}" -lt 1 ]; then
    echo "XESTRATA_PARALLEL must be a positive number, got '${XESTRATA_PARALLEL}'" >&2
    exit 1
  fi
fi
if [ -n "${XESTRATA_POOL_WORKERS:-}" ]; then
  if ! [ "${XESTRATA_POOL_WORKERS}" -eq "${XESTRATA_POOL_WORKERS}" ] 2>/dev/null; then
    echo "XESTRATA_POOL_WORKERS must be a number, got '${XESTRATA_POOL_WORKERS}'" >&2
    exit 1
  fi
fi
if [ -n "${XESTRATA_VRAM_RESERVE:-}${XESTRATA_PARALLEL:-}${XESTRATA_POOL_WORKERS:-}" ]; then
  for cfg in /opt/xestrata/xestrata-*.json; do
    [ -f "$cfg" ] || continue
    XESTRATA_VRAM_RESERVE="${XESTRATA_VRAM_RESERVE:-}" \
    XESTRATA_PARALLEL="${XESTRATA_PARALLEL:-}" \
    XESTRATA_POOL_WORKERS="${XESTRATA_POOL_WORKERS:-}" \
    /usr/bin/python3 - "$cfg" <<'EOF'
import json, os, sys
p = sys.argv[1]
cfg = json.load(open(p, encoding="utf-8-sig"))
args = cfg.get("args", [])

def set_arg(lst, flag, value):
    if flag in lst:
        lst[lst.index(flag) + 1] = value
    else:
        lst.append(flag)
        lst.append(value)

if os.environ["XESTRATA_VRAM_RESERVE"]:
    set_arg(args, "--vram-reserve-mib", os.environ["XESTRATA_VRAM_RESERVE"])
if os.environ["XESTRATA_PARALLEL"]:
    n = int(os.environ["XESTRATA_PARALLEL"])
    if n >= 2:
        cfg["parallel"] = n
    else:
        cfg.pop("parallel", None)
if os.environ["XESTRATA_POOL_WORKERS"]:
    set_arg(args, "--pool-workers", os.environ["XESTRATA_POOL_WORKERS"])
cfg["args"] = args
json.dump(cfg, open(p, "w", encoding="utf-8"), indent=1)
print(f"tuned {p}")
EOF
  done
fi

if [ -n "${XESTRATA_API_KEY:-}" ]; then
  exec xestrata --host 0.0.0.0 --port 8095 --api-key "${XESTRATA_API_KEY}" --yes
else
  exec xestrata --host 0.0.0.0 --port 8095 --yes
fi
