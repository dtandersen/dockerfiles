# xestrata

[xestrata](https://github.com/MistVVK/XeStrata) is an Intel-first, but not Intel only, port of [strata](https://github.com/Niko1221/Strata). The GPU code was rewritten from CUDA to SYCL/Level Zero.

It is made to run MoE models that are too large to fit in VRAM. The experts live in RAM and `xestrata` learns which ones are most used and swaps them into VRAM. It can also run the experts on the CPU.

This image installs upstream's prebuilt **contrib** `.deb`
(`xestrata-contrib-cuda13.1` by default — CUDA 13.1 PTX, Turing through
Hopper). For the Intel-only source build
with intel/llvm `--contrib`, see [xestrata-llvm](../xestrata-llvm/).

## Volumes

- /data - model weights
- /config - configuration files
- /root/.cache - neo compiler cache

## Model

Put the model into /data.

Set the model name, e.g. `XESTRATA_MODEL=IQ3_S`, and it downloads `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-GGUF` from Huggingface into `/data`.

`XESTRATA_FAMILY=qwen` is set by default for the Qwen 3.8 Flash Next family of models.

## Settings

Everything is an environment variable. Defaults work out of the box.

- XESTRATA_MODEL - which model to download (default IQ2_XS)
- XESTRATA_CONTEXT - context length in tokens (default 32768)
- XESTRATA_API_KEY - require this API key (default unset = open port)
- XESTRATA_VISION - let the model read images: yes|no|none|gpu|cpu
  (default no = text-only, like xestrata-llvm; the deb ships both the CPU
  and Vulkan encoders, so `yes`/`gpu`/`cpu` work — Vulkan needs a GPU
  with `mesa-vulkan-drivers`, installed in the image)
- STRATA_NO_BLAS - use the engine's own GEMM kernels instead of oneMath
  (default 1, baked into the image; `-e STRATA_NO_BLAS=0` retries oneMKL
  on Intel or cuBLAS on NVIDIA)
- XESTRATA_LOW_RAM - force setup's low-RAM mode (experts from NVMe via
  the page cache instead of all in RAM): auto|on|off|resident|mmap.
  Default unset = auto (host-RAM based; blind to a container memory cap,
  so set `mmap` explicitly when capping RAM below what the model wants)
- XESTRATA_POOL_WORKERS - CPU threads computing experts (`--pool-workers N`
  in the model config; default unset = engine default, which calibration
  measured optimal — set only for A/B tests, e.g. `-e XESTRATA_POOL_WORKERS=6`)
- XESTRATA_VRAM_RESERVE - MiB of VRAM the engine leaves free
  (`--vram-reserve-mib N` in the model config; the expert cache takes that
  much less). Default unset = 700. Raise for verify-window headroom on
  tight cards, e.g. `-e XESTRATA_VRAM_RESERVE=2048`
- XESTRATA_PARALLEL - up to N requests decode together (`"parallel": N`
  in the model config; default unset = one at a time, the others wait,
  `1` = explicitly sequential). Each slot costs ~0.6 GB of VRAM from the
  expert cache at 32k int8 (more at larger contexts); where experts mostly
  run from CPU each request also gets 10-25% slower. Qwen models only
- STRATA_ROUTE_TAIL_SKIP - skip missed experts inside verify windows
  (default 0, baked into the image; upstream default 7). The engine
  segfaulted in MTP suffix-draft verification with tail-skip on while
  verify captures ran with only ~150-480 MiB VRAM free — exact routing
  keeps `--spec` on at the cost of a few % decode. Pass
  `-e STRATA_ROUTE_TAIL_SKIP=7` to re-enable upstream's default

## Ports

The `xestrata` OpenAI compatible endpoint is on port 8095.


## Example

```sh
docker run -d --name xestrata --device /dev/dri \
  -p 8095:8095 \
  -v xestrata-data:/data -v xestrata-config:/config \
  -e XESTRATA_MODEL=IQ3_S \
  ghcr.io/dtandersen/xestrata:xe0.1.43.1
```

On a host with an AMD GPU next to the Intel one, also hide its KFD
compute topology or setup demands ROCm and stops:

```sh
mkdir -p /tmp/empty-kfd
# ... add to the run above:
# -v /tmp/empty-kfd:/sys/class/kfd:ro
```

The image defaults to its own GEMM kernels (`STRATA_NO_BLAS=1`, baked
in): oneMath's oneMKL backend segfaults on the intel/llvm 7.1.1 UR Level
Zero v2 stack. Pass `-e STRATA_NO_BLAS=0` to retry oneMKL on Intel or
for cuBLAS on NVIDIA hosts.

First start downloads the model (~84 GB) into the data volume, then
serves it. Chat at http://localhost:8095, or point any OpenAI-compatible
app at http://localhost:8095/v1.

## Building

```sh
docker buildx build ./xestrata -t xestrata:local \
  --build-arg XESTRATA_REF=xe0.1.43.1
```

Build args:

- XESTRATA_REF - upstream git tag to install (default xe0.1.43.1).
  Tag pushes to this repo install that version instead. The .deb file
  name is resolved via the release's SHA256SUMS, so release-count
  suffixes (e.g. `0.1.43-2`) need no mapping.
- XESTRATA_VARIANT - upstream package variant (default contrib-cuda13.1).
  `contrib-cuda12.4` keeps Pascal/Volta (sm_60/sm_61/sm_70) — a
  P100/P40/V100 takes cuda12.4. Newer GPUs run the newest PTX their
  driver compiles.
- UBUNTU_RELEASE - base image release (default 26.04).
