# XeStrata runtime image, built from source on Ubuntu.
#
# contrib-llvm build (upstream's default mode, docs/BUILD.md "Build and run"):
# intel/llvm 7.1.1 (the release tools/intel_llvm_build.py pins, built here)
# with its CUDA target (--contrib) in .tools/intel-llvm-contrib, oneMath's
# oneMKL backend for Intel GPUs (non-free, Intel's oneAPI repository) and its
# cuBLAS backend for NVIDIA GPUs (Ubuntu 26.04's nvidia-cuda-toolkit 12.4,
# also non-free). This is BUILD.md's validated combo: Ubuntu 26.04 +
# nvidia-cuda-toolkit 12.4 + intel/llvm v7.1.1 (sm_89 on an RTX 4070).
#
# Design: ship a pre-warmed source tree (engine already compiled, BUILD.json
# stamped in setup.py's own format) instead of the .deb layout, so the pod's
# first start only downloads the model and writes its config — setup.py sees
# `engine already built for this PC` and never recompiles in the pod.
# This only holds while builder and runtime agree on absolute paths
# (intel/llvm at /opt/xestrata/.tools/intel-llvm-contrib/install, oneMKL at
# /opt/intel/oneapi/mkl/latest in both stages) and while the pod's host
# matches the stamp: Intel GPU with XMX, no NVIDIA/AMD GPUs (xmx=True, empty
# CUDA/HIP archs). The binary DOES carry NVIDIA code (XESTRATA_CUDA_ARCHS)
# and runs without NVIDIA's driver/CUDA on Intel-only hosts; on an
# NVIDIA/AMD host setup recomputes the stamp and would try to recompile (no
# toolkit in the runtime image), so those hosts need an image rebuilt and
# restamped for them — rebuild with other args.
#
# First build takes a while (intel/llvm --contrib from source: ~25 min on 28
# threads, much longer on a small GitHub runner; the engine with 8 CUDA
# architectures plus oneMath adds the better part of an hour). Later XeStrata
# bumps only redo the engine layer while the llvm layer is cached.
#
# Assumptions baked in (wrong for other GPUs — rebuild with other args):
# - XMX=True: target is an XMX card (Arc A/B series, incl. the B70).
#   Without matrix engines the engine still runs (DP4a fallback at run time).
# - NVIDIA code for XESTRATA_CUDA_ARCHS (upstream's CUDA 12.4 set, Pascal
#   through Hopper); no AMD code (STRATA_HIP_ARCHS empty, no ROCm).
#   Hosts with an AMD GPU besides the Intel one must hide its KFD compute
#   topology from the container (`-v /tmp/empty-kfd:/sys/class/kfd:ro` with
#   an empty dir), or setup demands ROCm's packages for it and stops.
# - Own-kernel GEMMs (STRATA_NO_BLAS=1, see the ENV below): oneMath's
#   oneMKL backend segfaults on this stack, so the dense products run on
#   XeStrata's own XMX kernels (a few % of prefill speed on Intel). Unset
#   for NVIDIA hosts (cuBLAS) or to retry oneMKL.
# - Text-only: the Vulkan/CPU image encoders are NOT built, so
#   xestrata.vision must stay "no". Vision needs the encoders from
#   tools/vision (libvulkan-dev, glslc, spirv-headers in the builder).
# - NVIDIA hosts need a driver that loads CUDA 12.4 PTX. The runtime image
#   ships no CUDA toolkit: oneMath opens cuBLAS and the driver at run time,
#   only on NVIDIA hosts (upstream's contrib package Suggests, not Requires,
#   them for the same reason).
#
# Verify after building (on the B70 host):
#   docker run --rm --device /dev/dri <image> xestrata --check

ARG UBUNTU_RELEASE=26.04
# Upstream git tag (release name, e.g. xe0.1.43.1).
ARG XESTRATA_REF=xe0.1.43.1
# Source repository (override to build a fork/branch, e.g. a fix branch).
ARG XESTRATA_REPO=https://github.com/MistVVK/XeStrata.git
# intel/llvm build parallelism (default: all builder CPUs).
ARG XESTRATA_JOBS=""
# intel/llvm release to build (tools/intel_llvm_build.py --tag). Must be 7
# or later (the engine needs libsycl 9); BUILD.md validates v7.1.1, which
# is also what upstream's script pins. Other tags may not take upstream's
# patches (the build script then fails loudly).
ARG XESTRATA_LLVM_TAG="v7.1.1"
# NVIDIA architectures for the cuBLAS backend and device code (contrib).
# Upstream's CUDA 12.4 set from tools/package/container.sh; trim for a
# single generation, e.g. --build-arg XESTRATA_CUDA_ARCHS=sm_89.
ARG XESTRATA_CUDA_ARCHS="sm_60;sm_61;sm_70;sm_75;sm_80;sm_86;sm_89;sm_90"

# ---------------------------------------------------------------- builder
FROM ubuntu:${UBUNTU_RELEASE} AS builder
ARG XESTRATA_REPO
ARG XESTRATA_REF
ARG XESTRATA_JOBS
ARG XESTRATA_LLVM_TAG
ARG XESTRATA_CUDA_ARCHS
ENV DEBIAN_FRONTEND=noninteractive

# Build tools: the contrib-llvm package row from docs/BUILD.md (Ubuntu 26.04
# column; no ROCm: no AMD code), plus unzip for the llama.cpp archive and gpg
# for Intel's oneAPI repository below. No Vulkan packages: text-only image,
# the image encoders are not built (see header note).
# ccache: shared compiler cache across rebuilds (same trick as upstream's
# tools/package, 30G like theirs); needs BuildKit (`docker buildx`).
# Size is a build arg so CI (10 GB GHA cache cap) can set it lower.
ARG CCACHE_MAXSIZE=30G
ENV CCACHE_DIR=/var/cache/ccache CCACHE_MAXSIZE=${CCACHE_MAXSIZE}
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip gpg \
      cmake ninja-build build-essential lld pkg-config patchelf ccache \
      python3 python3-venv \
      libhwloc-dev libzstd-dev libblosc2-dev \
      nvidia-cuda-toolkit \
    && rm -rf /var/lib/apt/lists/*

# oneMKL for the contrib oneMKL backend (non-free, Intel's oneAPI
# repository). Same package tools/package/container.sh uses on Ubuntu.
RUN curl -fsSL https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
      | gpg --dearmor -o /usr/share/keyrings/oneapi-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] https://apt.repos.intel.com/oneapi all main" \
      > /etc/apt/sources.list.d/oneAPI.list \
    && apt-get update && apt-get install -y --no-install-recommends \
         intel-oneapi-mkl-sycl-devel \
    && rm -rf /var/lib/apt/lists/*

# Upstream source at the pinned tag.
RUN git clone --depth 1 --branch "${XESTRATA_REF}" \
      "${XESTRATA_REPO}" /opt/xestrata
WORKDIR /opt/xestrata

# llama.cpp at the commit setup.py pins (ggml for the engine). Same download
# tools/package/container.sh does; third_party/main/llama.cpp is not vendored.
RUN commit=$(sed -n 's/^LLAMA_CPP_COMMIT = "\([0-9a-f]*\)"$/\1/p' setup.py) \
    && curl -fsSL -o /tmp/llama.zip \
         "https://github.com/ggml-org/llama.cpp/archive/${commit}.zip" \
    && unzip -q /tmp/llama.zip -d /tmp/llama \
    && mv "/tmp/llama/llama.cpp-${commit}" third_party/main/llama.cpp \
    && rm -rf /tmp/llama /tmp/llama.zip

# The CUDA toolkit the contrib build needs must be usable before the long
# intel/llvm build starts: fail fast when Ubuntu's layout ever moves nvcc or
# the libdevice bitcode setup.py's cuda_toolkits() looks for.
RUN command -v nvcc && nvcc --version \
    && test -n "$(ls /usr/lib/cuda/nvvm/libdevice/libdevice*.bc 2>/dev/null)"

# intel/llvm DPC++ (tools/intel_llvm_build.py --tag, default v7.1.1) with
# its CUDA target (--contrib: NVIDIA GPUs; needs the toolkit above).
# Without ROCm HIP installed it skips the HIP target on its own (no AMD code).
# Installs into .tools/intel-llvm-contrib/install inside the tree (see header
# note). The XESTRATA.json check pins the built tag; the adapter check
# proves the CUDA target was actually built (setup.py refuses a toolchain
# without it on NVIDIA hosts).
# The cache mount keeps ccache warm between rebuilds (LLVM objects are reused
# when only the engine or the XeStrata source changes).
RUN --mount=type=cache,target=/var/cache/ccache \
    export CMAKE_C_COMPILER_LAUNCHER=ccache CMAKE_CXX_COMPILER_LAUNCHER=ccache \
    && python3 tools/intel_llvm_build.py --contrib --yes --tag "${XESTRATA_LLVM_TAG}" --jobs "${XESTRATA_JOBS:-$(nproc)}" \
    && grep -q "\"tag\": \"${XESTRATA_LLVM_TAG}\"" /opt/xestrata/.tools/intel-llvm-contrib/install/XESTRATA.json \
    && test -n "$(ls /opt/xestrata/.tools/intel-llvm-contrib/install/lib/libur_adapter_cuda.so* 2>/dev/null)"

# Python env now, so the pod never pip-installs at start (setup.py skips its
# pip step when requirements.txt is already satisfied in .venv). The stamp
# file is setup.py's own format (.strata-pip.json, written by its
# requirement_lines()): a plain `pip install` leaves no stamp, and without
# it setup would reinstall every pinned package into the container on first
# start (network + minutes, on every fresh container).
RUN python3 -m venv .venv \
    && .venv/bin/pip install --no-cache-dir -r requirements.txt \
    && .venv/bin/python -c "import json; from pathlib import Path; import setup; Path('.venv/.strata-pip.json').write_text(json.dumps(sorted(set(setup.requirement_lines())), indent=0))"

# The engine, contrib-llvm. Same flags setup.py passes a contrib build
# (build_engine), run directly because setup.py would stop here without a GPU
# for its XMX probe. STRATA_CUDA_PATH/PTX mirror tools/package/container.sh
# for 12.4 (toolkit's PTX; needs a 12.4-capable driver on NVIDIA hosts).
# cmake fetches oneMath from XeStrata's fork (pinned archive + SHA-256 in
# CMakeLists.txt). `strata` also builds oneMath (a build dependency) for the
# oneMKL/cuBLAS backends; the backend libraries are staged into the tree in
# the next step.
RUN --mount=type=cache,target=/var/cache/ccache \
    export PATH="/usr/lib/cuda/bin:${PATH}" \
    && cmake -G Ninja -S /opt/xestrata -B /build/engine \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
      -DCMAKE_CXX_COMPILER=/opt/xestrata/.tools/intel-llvm-contrib/install/bin/clang++ \
      -DCMAKE_C_COMPILER=/opt/xestrata/.tools/intel-llvm-contrib/install/bin/clang \
      -DSTRATA_LICENSE=contrib \
      -DSTRATA_CUDA_ARCHS="${XESTRATA_CUDA_ARCHS}" \
      -DSTRATA_CUDA_PATH=/usr/lib/cuda -DSTRATA_CUDA_PTX= \
      -DSTRATA_HIP_ARCHS= \
      -DSTRATA_ONEMKL=ON -DMKL_ROOT=/opt/intel/oneapi/mkl/latest \
      -DSTRATA_ENABLE_XE=ON -DSTRATA_NATIVE_EXPERTS=ON \
      -DSTRATA_BUILD_TESTS=OFF -DSTRATA_PORTABLE=ON \
      -DSTRATA_GGML_DIR=/opt/xestrata/third_party/main/llama.cpp \
    && cmake --build /build/engine --target strata -j "${XESTRATA_JOBS:-$(nproc)}"

# Stage the engine's shared libraries into the tree and trim oneMKL to what
# the oneMath backend actually resolves to (libmkl_sycl_blas; libsycl comes
# from our own toolchain). RPATHs are fixed so the files work from the tree:
# the binary finds engine/lib, libonemath finds its backends beside it, and
# the backends keep their absolute MKL/CUDA paths (stale /build entries are
# dropped). CUDA/cuBLAS files are deliberately NOT staged: oneMath opens them
# at run time, only on NVIDIA hosts.
RUN .venv/bin/python - <<'EOF'
import os, shutil, subprocess
from pathlib import Path

eng = Path("/opt/xestrata/engine")
lib = eng / "lib"
lib.mkdir(parents=True, exist_ok=True)
mkllib = Path("/opt/intel/oneapi/mkl/latest/lib")
stage = Path("/mkl-stage/opt/intel/oneapi/mkl/latest/lib")
stage.mkdir(parents=True, exist_ok=True)
llvm_lib = Path("/opt/xestrata/.tools/intel-llvm-contrib/install/lib")

found = sorted(Path("/build/engine").rglob("libonemath*.so*"))
assert found, "no libonemath built in /build/engine"
print("oneMath:", [str(p) for p in found])
shutil.copy2("/build/engine/strata", eng / "strata")
for p in found:
    shutil.copy2(p, lib / p.name, follow_symlinks=False)

def rpath(p):
    r = subprocess.run(["patchelf", "--print-rpath", str(p)],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return [e for e in r.stdout.strip().split(":") if e]

def set_rpath(p, *first):
    keep = [e for e in rpath(p)
            if not e.startswith(("/build", "/tmp", "/mkl-stage"))]
    new = list(dict.fromkeys([*first, *keep]))
    subprocess.run(["patchelf", "--set-rpath", ":".join(new), str(p)],
                   check=True)
    print("rpath", p.name, "->", ":".join(new))

set_rpath(eng / "strata", "$ORIGIN/lib")
assert (llvm_lib / "libur_adapter_cuda.so.0").exists() or \
    list(llvm_lib.glob("libur_adapter_cuda.so*")), "no CUDA adapter"
for p in sorted(lib.glob("libonemath*.so*")):
    if p.is_symlink():
        continue
    set_rpath(p, "$ORIGIN", str(mkllib))

names = [p.name for p in lib.glob("libonemath*.so*") if not p.is_symlink()]
assert any(n.startswith("libonemath_blas_mklgpu.") for n in names), names
assert any(n.startswith("libonemath_blas_cublas.") for n in names), names

env = dict(os.environ, LD_LIBRARY_PATH=os.pathsep.join(
    [str(lib), str(llvm_lib), str(mkllib),
     os.environ.get("LD_LIBRARY_PATH", "")]))
r = subprocess.run(["ldd", str(eng / "strata"),
                    *[str(p) for p in sorted(lib.glob("libonemath*.so*"))
                      if not p.is_symlink() and "cublas" not in p.name]],
                   capture_output=True, text=True, env=env)
print(r.stdout)
bad = [l for l in r.stdout.splitlines() if "not found" in l]
assert not bad, f"unresolved: {bad}"

def stage_tree(src: Path):
    cur, seen = src, set()
    while cur.name not in seen:
        seen.add(cur.name)
        dst = stage / cur.name
        if cur.is_symlink():
            tgt = os.readlink(cur)
            if dst.is_symlink() or dst.exists():
                dst.unlink()
            dst.symlink_to(tgt)
            nxt = cur.parent / tgt if not os.path.isabs(tgt) else Path(tgt)
            if not str(nxt).startswith("/opt/intel"):
                break
            cur = nxt
        else:
            shutil.copy2(cur, dst)
            break

n = 0
for line in r.stdout.splitlines():
    if "=>" not in line:
        continue
    path = line.split("=>", 1)[1].strip().split()[0]
    if path.startswith("/opt/intel/"):
        stage_tree(Path(path))
        n += 1
assert n > 0, "no /opt/intel dependency found: oneMKL backend not linked?"
size = sum(p.stat().st_size for p in stage.iterdir())
print(f"staged {n} MKL files, {size // 1024 // 1024} MB in {stage}")
EOF

# Stamp engine/BUILD.json exactly as setup.py's build_engine would on the
# deployment host (Intel GPU with XMX, no NVIDIA/AMD GPUs: contrib mode
# without NVIDIA cards uses the toolchain above with an empty cuda_archs and
# oneMKL on), so the pod accepts the engine (`engine already built for this
# PC`). Keys and hash inputs mirror build_engine; xmx=True targets XMX cards
# (see header note). engine/lib is on lib_dirs so the server's
# LD_LIBRARY_PATH covers libonemath and its backends.
RUN .venv/bin/python - <<'EOF'
import json
from pathlib import Path
import setup
install = Path("/opt/xestrata/.tools/intel-llvm-contrib/install")
comp = setup.free_compiler(install, "contrib")
comp["onemkl"] = True
comp["version"] = setup.compiler_version(comp["cxx"], comp["env"])
used = {"cxx": comp["cxx"], "version": comp["version"], "kind": comp["kind"],
        "xmx": True, "license": comp["license"], "cuda_archs": comp["cuda_archs"],
        "onemkl": comp["onemkl"], "hip_archs": comp.get("hip_archs", [])}
meta = {"source": "local", "backend": "xe", "version": setup.source_version(),
        "compiler": used,
        "lib_dirs": [str(install / "lib"), "/opt/xestrata/engine/lib"],
        "src": setup.source_hash(setup.ENGINE_SOURCES), "vision_srcs": {}}
Path("/opt/xestrata/engine/BUILD.json").write_text(json.dumps(meta, indent=1))
print("stamped", meta["version"], meta["src"])
EOF

# ---------------------------------------------------------------- runtime
FROM ubuntu:${UBUNTU_RELEASE}
ARG XESTRATA_REF
ENV DEBIAN_FRONTEND=noninteractive
# Own-kernel GEMMs by default: oneMath's oneMKL backend segfaults on this
# stack (MKL 2026.1 submits through intel/llvm 7.1.1's UR Level Zero v2
# adapter, whose isGraphCaptureActive calls a null function pointer — gdb
# backtrace 2026-10-14). The contrib build itself (NVIDIA code, cuBLAS and
# oneMKL backends) stays intact in the image; pass -e STRATA_NO_BLAS=0 to
# retry oneMKL on Intel or for cuBLAS on NVIDIA hosts.
ENV STRATA_NO_BLAS=1

# Runtime deps: Python for setup.py/serve, Ubuntu's Python modules (same set
# as requirements.txt where packaged), Level Zero loader and the OpenCL
# headers. ocl-icd-opencl-dev: every `-fsycl` compile needs CL/cl.h
# (sycl.hpp pulls it in) — the smoke test below, and at first start setup's
# compiler re-validation plus the live XMX probe build. The Intel GPU
# userspace below (26 series lists Battlemage/B70; distro packages are older).
# libstdc++-15-dev: setup re-validates the prebuilt compiler at first start
# (new_enough: clang++ -fsycl -dM -E over sycl.hpp), which needs the host C++
# headers the builder got from g++ (Ubuntu 26.04's default GCC is 15).
# Re-check the number when bumping UBUNTU_RELEASE. libblosc2-7:
# engine/strata links it (conversation compression); setup only puts the
# compiler's lib dir on the library path. binutils: setup's XMX probe
# compiles AND links tools/xmx_probe.cpp live at first start; without ld the
# link fails and the probe reads as "no XMX". libhwloc15: the SYCL runtime
# dlopens the Level Zero/OpenCL adapters at first start, and they link
# libhwloc — without it sycl-ls finds no GPU. (dlopen deps don't show in
# `ldd engine/strata`, so the smoke test below can't catch this; re-check the
# package names when bumping UBUNTU_RELEASE.)
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl \
      python3 python3-venv \
      python3-numpy python3-jinja2 python3-regex python3-yaml python3-tqdm \
      python3-requests python3-pil python3-psutil \
      libze1 ocl-icd-libopencl1 ocl-icd-opencl-dev \
      libstdc++-15-dev libblosc2-7 binutils libhwloc15 \
    && rm -rf /var/lib/apt/lists/*

# Intel Level Zero userspace, pinned 26 series (verified release assets).
# Re-pin all four together. Every step is &&-chained on purpose: a failed
# download or install must fail the build here, not limp on without a GPU
# driver (an `|| apt-get -f` fallback once masked a failed curl and shipped
# an image whose SYCL runtime listed no GPU). The trailing apt-get -f only
# resolves dependencies of successfully unpacked debs.
ARG INTEL_CR=26.35.39758.10
ARG INTEL_IGC=2.41.5
ARG INTEL_IGC_BUILD=22716
ARG INTEL_GMMLIB=22.10.0
RUN cd /tmp \
    && curl -fsSLO "https://github.com/intel/compute-runtime/releases/download/${INTEL_CR}/libze-intel-gpu1_${INTEL_CR}-0_amd64.deb" \
    && curl -fsSLO "https://github.com/intel/compute-runtime/releases/download/${INTEL_CR}/intel-ocloc_${INTEL_CR}-0_amd64.deb" \
    && curl -fsSLO "https://github.com/intel/compute-runtime/releases/download/${INTEL_CR}/libigdgmm12_${INTEL_GMMLIB}_amd64.deb" \
    && curl -fsSLO "https://github.com/intel/intel-graphics-compiler/releases/download/v${INTEL_IGC}/intel-igc-core-2_${INTEL_IGC}+${INTEL_IGC_BUILD}_amd64.deb" \
    && curl -fsSLO "https://github.com/intel/intel-graphics-compiler/releases/download/v${INTEL_IGC}/intel-igc-opencl-2_${INTEL_IGC}+${INTEL_IGC_BUILD}_amd64.deb" \
    && dpkg -i ./*.deb && apt-get install -y -f --no-install-recommends \
    && rm -f ./*.deb \
    && rm -rf /var/lib/apt/lists/* \
    && ldconfig -p | grep -q libze_intel_gpu

# Pre-warmed tree: source, .venv, compiler, engine + stamp. Prune what the
# pod never reads (repo history, bench data, llvm build sources) to keep the
# image from growing further. oneMKL comes as the trimmed runtime closure
# staged in the builder (only what the oneMath backend resolves to); no CUDA
# toolkit here (oneMath opens cuBLAS/the driver at run time, NVIDIA hosts
# only — see header note).
COPY --from=builder /opt/xestrata /opt/xestrata
COPY --from=builder /mkl-stage/opt/intel/oneapi/mkl/latest /opt/intel/oneapi/mkl/latest
RUN rm -rf /opt/xestrata/.git /opt/xestrata/bench \
      /opt/xestrata/.tools/intel-llvm-contrib/src \
    && test -x /opt/xestrata/engine/strata \
    && test -f /opt/xestrata/engine/BUILD.json \
    && test -n "$(ls /opt/xestrata/engine/lib/libonemath_blas_mklgpu.so* 2>/dev/null)" \
    && test -n "$(ls /opt/xestrata/engine/lib/libonemath_blas_cublas.so* 2>/dev/null)" \
    && test -d /opt/intel/oneapi/mkl/latest/lib \
    && test -n "$(ls /opt/intel/oneapi/mkl/latest/lib/libmkl_sycl_blas.so* 2>/dev/null)" \
    && echo '#include <sycl/sycl.hpp>' \
         | /opt/xestrata/.tools/intel-llvm-contrib/install/bin/clang++ \
             -fsycl -dM -E -x c++ - \
         | grep -q '__LIBSYCL_MAJOR_VERSION 9' \
    && /opt/xestrata/.tools/intel-llvm-contrib/install/bin/clang++ \
         -fsycl /opt/xestrata/tools/xmx_probe.cpp -o /tmp/xmx_probe \
    && ! (LD_LIBRARY_PATH=/opt/xestrata/.tools/intel-llvm-contrib/install/lib:/opt/xestrata/engine/lib:/opt/intel/oneapi/mkl/latest/lib \
       ldd /opt/xestrata/engine/strata | grep -q 'not found')

# `xestrata` command, same shape as the deb's xestrata.in wrapper (setup.py
# for everything, chat.py for `xestrata chat`), against the tree's own venv.
RUN printf '#!/bin/sh\nPYTHONDONTWRITEBYTECODE=1\nexport PYTHONDONTWRITEBYTECODE\nif [ "$1" = chat ]; then shift; exec /opt/xestrata/.venv/bin/python /opt/xestrata/chat.py "$@"; fi\nexec /opt/xestrata/.venv/bin/python /opt/xestrata/setup.py "$@"\n' \
      > /usr/local/bin/xestrata \
    && chmod +x /usr/local/bin/xestrata \
    && command -v xestrata

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/data", "/config"]
EXPOSE 8095
ENTRYPOINT ["/entrypoint.sh"]
