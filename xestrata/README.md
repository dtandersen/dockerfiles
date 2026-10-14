# xestrata

[xestrata](https://github.com/MistVVK/XeStrata) is an Intel-first, but not Intel only, port of [strata](https://github.com/Niko1221/Strata). The GPU code was rewritten from CUDA to SYCL/Level Zero.

It is made to run MoE models that are too large to fit in VRAM. The experts live in RAM and `xestrata` learns which ones are most used and swaps them into VRAM. It can also run the experts on the CPU.

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
- STRATA_NO_BLAS - use the engine's own GEMM kernels instead of oneMath
  (default 1, baked into the image; `-e STRATA_NO_BLAS=0` retries oneMKL
  on Intel or cuBLAS on NVIDIA)
- XESTRATA_POOL_WORKERS - CPU threads computing experts (`--pool-workers N`
  in the model config; default unset = engine default, which calibration
  measured optimal — set only for A/B tests, e.g. `-e XESTRATA_POOL_WORKERS=6`)

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
in): oneMath's oneMKL backend segfaults on this stack (intel/llvm
7.1.1's UR Level Zero v2 adapter). Pass `-e STRATA_NO_BLAS=0` to retry
oneMKL on Intel or for cuBLAS on NVIDIA hosts.

First start downloads the model (~84 GB) into the data volume, then
serves it. Chat at http://localhost:8095, or point any OpenAI-compatible
app at http://localhost:8095/v1.

## Building

```sh
docker buildx build ./xestrata -t xestrata:local \
  --build-arg XESTRATA_REF=xe0.1.43.1 \
  --build-arg XESTRATA_JOBS=16
```

Build args:

- XESTRATA_REF - upstream git tag to build (default xe0.1.43.1).
  Tag pushes to this repo build that version instead.
- XESTRATA_REPO - source repository (default upstream). Point at a fork
  to build a fix branch, e.g. `--build-arg XESTRATA_REPO=https://github.com/you/XeStrata.git`
  with `--build-arg XESTRATA_REF=my-fix`.
- XESTRATA_JOBS - build parallelism (default: all CPUs).
- XESTRATA_LLVM_TAG - intel/llvm release to build (default v7.1.1,
  the validated one; must be 7+ for libsycl 9).
- XESTRATA_CUDA_ARCHS - NVIDIA architectures for device code and cuBLAS
  (default sm_60;sm_61;sm_70;sm_75;sm_80;sm_86;sm_89;sm_90, upstream's
  CUDA 12.4 set). Trim for one generation, e.g.
  `--build-arg XESTRATA_CUDA_ARCHS=sm_89`.
- CCACHE_MAXSIZE - compiler cache size (default 30G, like upstream's
  deb builds). Lower it where cache storage is capped, e.g.
  `--build-arg CCACHE_MAXSIZE=8G` for GitHub Actions (10 GB cache limit).
- UBUNTU_RELEASE - base image release (default 26.04).

Caching: intel/llvm and engine objects are shared between rebuilds via
ccache in a BuildKit cache mount — automatic with `buildx`, nothing to
pass. The GitHub workflow exports it with `type=gha,mode=max`, so CI
rebuilds reuse it too (within the 10 GB cap).
