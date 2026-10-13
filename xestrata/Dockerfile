# XeStrata runtime image, built from source on slim Debian.
#
# Free (free-software-only), Intel-only build: no oneMKL, no CUDA, no ROCm.
# The dense products run on XeStrata's own XMX kernels, which is also what the
# upstream free package does on Intel GPUs.
#
# Design: ship a pre-warmed source tree (engine already compiled, BUILD.json
# stamped in setup.py's own format) instead of the .deb layout, so the pod's
# first start only downloads the model and writes its config — setup.py sees
# `engine already built for this PC` and never recompiles in the pod.
# This only holds while builder and runtime agree on absolute paths:
# intel/llvm lives at /opt/xestrata/.tools/intel-llvm/install in both stages.
#
# First build takes a while (intel/llvm from source: ~13 min on 28 threads,
# much longer on a small GitHub runner; the engine adds 20-40 min). Later
# XeStrata bumps only redo the engine layer while the llvm layer is cached.
#
# Assumptions baked in (wrong for other GPUs — rebuild with other args):
# - XMX=True: target is an XMX card (Arc A/B series, incl. the B70).
#   Without matrix engines the engine still runs (DP4a fallback at run time).
# - No AMD/NVIDIA code (STRATA_HIP_ARCHS/CUDA_ARCHS empty, ONEMKL OFF).
# - Text-only: the Vulkan/CPU image encoders are NOT built, so
#   xestrata.vision must stay "no". Vision needs the encoders from
#   tools/vision (libvulkan-dev, glslc, spirv-headers in the builder).
#
# Verify after building (on the B70 host):
#   docker run --rm --device /dev/dri <image> xestrata --check

ARG DEBIAN_RELEASE=trixie-slim
# Upstream git tag (release name, e.g. xe0.1.43.1).
ARG XESTRATA_REF=xe0.1.43.1
# intel/llvm build parallelism (default: all builder CPUs).
ARG XESTRATA_JOBS=""

# ---------------------------------------------------------------- builder
FROM debian:${DEBIAN_RELEASE} AS builder
ARG XESTRATA_REF
ARG XESTRATA_JOBS
ENV DEBIAN_FRONTEND=noninteractive

# Build tools, the free-mode package rows from docs/BUILD.md (no ROCm: no AMD
# code; no oneAPI/CUDA: free license), plus unzip for the llama.cpp archive.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip \
      cmake ninja-build g++ lld pkg-config patchelf \
      python3 python3-venv \
      libhwloc-dev libzstd-dev libblosc2-dev \
    && rm -rf /var/lib/apt/lists/*

# Upstream source at the pinned tag.
RUN git clone --depth 1 --branch "${XESTRATA_REF}" \
      https://github.com/MistVVK/XeStrata.git /opt/xestrata
WORKDIR /opt/xestrata

# llama.cpp at the commit setup.py pins (ggml for the engine). Same download
# tools/package/container.sh does; third_party/main/llama.cpp is not vendored.
RUN commit=$(sed -n 's/^LLAMA_CPP_COMMIT = "\([0-9a-f]*\)"$/\1/p' setup.py) \
    && curl -fsSL -o /tmp/llama.zip \
         "https://github.com/ggml-org/llama.cpp/archive/${commit}.zip" \
    && unzip -q /tmp/llama.zip -d /tmp/llama \
    && mv "/tmp/llama/llama.cpp-${commit}" third_party/main/llama.cpp \
    && rm -rf /tmp/llama /tmp/llama.zip

# intel/llvm DPC++ 7+, free mode (no --contrib: no CUDA target, no oneMKL).
# Without ROCm HIP installed it skips the HIP target on its own (Intel-only).
# Installs into .tools/intel-llvm/install inside the tree (see header note).
RUN python3 tools/intel_llvm_build.py --yes --jobs "${XESTRATA_JOBS:-$(nproc)}"

# Python env now, so the pod never pip-installs at start (setup.py skips its
# pip step when requirements.txt is already satisfied in .venv).
RUN python3 -m venv .venv \
    && .venv/bin/pip install --no-cache-dir -r requirements.txt

# The engine, Intel-only. Same flags setup.py passes a free build with no
# AMD/NVIDIA GPUs (build_engine), run directly because setup.py would stop
# here without a GPU for its XMX probe.
RUN cmake -G Ninja -S /opt/xestrata -B /build/engine \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CXX_COMPILER=/opt/xestrata/.tools/intel-llvm/install/bin/clang++ \
      -DCMAKE_C_COMPILER=/opt/xestrata/.tools/intel-llvm/install/bin/clang \
      -DSTRATA_LICENSE=free \
      -DSTRATA_CUDA_ARCHS= -DSTRATA_HIP_ARCHS= -DSTRATA_ONEMKL=OFF \
      -DSTRATA_ENABLE_XE=ON -DSTRATA_NATIVE_EXPERTS=ON \
      -DSTRATA_BUILD_TESTS=OFF -DSTRATA_PORTABLE=ON \
      -DSTRATA_GGML_DIR=/opt/xestrata/third_party/main/llama.cpp \
    && cmake --build /build/engine --target strata -j "${XESTRATA_JOBS:-$(nproc)}" \
    && mkdir -p /opt/xestrata/engine \
    && cp /build/engine/strata /opt/xestrata/engine/strata

# Stamp engine/BUILD.json exactly as setup.py's build_engine would, so the
# pod accepts the engine (`engine already built for this PC`). Keys and hash
# inputs mirror build_engine; xmx=True targets XMX cards (see header note).
RUN .venv/bin/python - <<'EOF'
import json
from pathlib import Path
import setup
install = Path("/opt/xestrata/.tools/intel-llvm/install")
comp = setup.free_compiler(install)
comp["version"] = setup.compiler_version(comp["cxx"], comp["env"])
used = {"cxx": comp["cxx"], "version": comp["version"], "kind": comp["kind"],
        "xmx": True, "license": comp["license"], "cuda_archs": comp["cuda_archs"],
        "onemkl": comp["onemkl"], "hip_archs": comp.get("hip_archs", [])}
meta = {"source": "local", "backend": "xe", "version": setup.source_version(),
        "compiler": used, "lib_dirs": comp["lib_dirs"],
        "src": setup.source_hash(setup.ENGINE_SOURCES), "vision_srcs": {}}
Path("/opt/xestrata/engine/BUILD.json").write_text(json.dumps(meta, indent=1))
print("stamped", meta["version"], meta["src"])
EOF

# ---------------------------------------------------------------- runtime
FROM debian:${DEBIAN_RELEASE}
ARG XESTRATA_REF
ENV DEBIAN_FRONTEND=noninteractive

# Runtime deps: Python for setup.py/serve, Debian's Python modules (same set
# as requirements.txt where packaged), Level Zero loader. The Intel GPU
# userspace below (26 series lists Battlemage/B70; distro packages are older).
# libstdc++-14-dev: setup re-validates the prebuilt compiler at first start
# (new_enough: clang++ -fsycl -dM -E over sycl.hpp), which needs the host C++
# headers the builder got from g++. Re-check the number when bumping
# DEBIAN_RELEASE. libblosc2-4: engine/strata links it (conversation
# compression); setup only puts the compiler's lib dir on the library path.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl \
      python3 python3-venv \
      python3-numpy python3-jinja2 python3-regex python3-yaml python3-tqdm \
      python3-requests python3-pil python3-psutil \
      libze1 ocl-icd-libopencl1 \
      libstdc++-14-dev libblosc2-4 \
    && rm -rf /var/lib/apt/lists/*

# Intel Level Zero userspace, pinned 26 series (verified release assets;
# Ubuntu-built debs install cleanly on Debian). Re-pin all four together.
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
    && dpkg -i ./*.deb || apt-get install -y -f --no-install-recommends \
    && rm -f ./*.deb \
    && rm -rf /var/lib/apt/lists/*

# Pre-warmed tree: source, .venv, compiler, engine + stamp. Prune what the
# pod never reads (repo history, bench data, llvm build sources) to keep the
# ~6 GB image from growing further.
COPY --from=builder /opt/xestrata /opt/xestrata
RUN rm -rf /opt/xestrata/.git /opt/xestrata/bench \
      /opt/xestrata/.tools/intel-llvm/src \
    && test -x /opt/xestrata/engine/strata \
    && test -f /opt/xestrata/engine/BUILD.json \
    && echo '#include <sycl/sycl.hpp>' \
         | /opt/xestrata/.tools/intel-llvm/install/bin/clang++ \
             -fsycl -dM -E -x c++ - 2>/dev/null \
         | grep -q '__LIBSYCL_MAJOR_VERSION 9' \
    && ! (LD_LIBRARY_PATH=/opt/xestrata/.tools/intel-llvm/install/lib \
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
