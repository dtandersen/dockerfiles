# XeStrata runtime, built from source (contrib-llvm). Intel-only:
# XMX target, no NVIDIA/AMD code, text-only (no vision encoders).
# Pre-warmed tree: engine prebuilt and stamped, first start only fetches
# the model. Builder and runtime paths must match; NVIDIA/AMD hosts need
# their own build.

ARG UBUNTU_RELEASE=26.04
# Upstream git tag (release name, e.g. xe0.1.43.1).
ARG XESTRATA_REF=xe0.1.43.1
# Source repository (override to build a fork/branch, e.g. a fix branch).
ARG XESTRATA_REPO=https://github.com/MistVVK/XeStrata.git
# intel/llvm build parallelism (default: all builder CPUs).
ARG XESTRATA_JOBS=""
# intel/llvm release. Must be 7+ (needs libsycl 9).
ARG XESTRATA_LLVM_TAG="v7.1.1"
# NVIDIA architectures for device code and the cuBLAS backend (contrib).
# Empty: Intel-only, fastest (default). Set for NVIDIA, e.g.
# --build-arg XESTRATA_CUDA_ARCHS=sm_90, or upstream's CUDA 13.1 set
# sm_75;sm_80;sm_86;sm_89;sm_90 from tools/package/container.sh.
ARG XESTRATA_CUDA_ARCHS=""

# ---------------------------------------------------------------- builder
FROM ubuntu:${UBUNTU_RELEASE} AS builder
ARG XESTRATA_REPO
ARG XESTRATA_REF
ARG XESTRATA_JOBS
ARG XESTRATA_LLVM_TAG
ARG XESTRATA_CUDA_ARCHS
ENV DEBIAN_FRONTEND=noninteractive

# Build tools + ccache (30G; CI lowers it). No ROCm/Vulkan: Intel-only, text-only.
ARG CCACHE_MAXSIZE=30G
ENV CCACHE_DIR=/var/cache/ccache CCACHE_MAXSIZE=${CCACHE_MAXSIZE}
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip gpg \
      cmake ninja-build build-essential lld pkg-config patchelf ccache \
      python3 python3-venv \
      libhwloc-dev libzstd-dev libblosc2-dev \
      cuda-toolkit-13-1 \
    && rm -rf /var/lib/apt/lists/*
ENV PATH=/usr/local/cuda-13.1/bin:${PATH}

# oneMKL for the oneMKL backend (Intel oneAPI repo).
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

# llama.cpp at setup.py's pinned commit.
RUN commit=$(sed -n 's/^LLAMA_CPP_COMMIT = "\([0-9a-f]*\)"$/\1/p' setup.py) \
    && curl -fsSL -o /tmp/llama.zip \
         "https://github.com/ggml-org/llama.cpp/archive/${commit}.zip" \
    && unzip -q /tmp/llama.zip -d /tmp/llama \
    && mv "/tmp/llama/llama.cpp-${commit}" third_party/main/llama.cpp \
    && rm -rf /tmp/llama /tmp/llama.zip

# Fail fast if the CUDA toolkit layout moves (needed by the llvm build).
RUN command -v nvcc && nvcc --version \
    && test -n "$(ls /usr/local/cuda-13.1/nvvm/libdevice/libdevice*.bc 2>/dev/null)"

# intel/llvm --contrib (CUDA target needs the toolkit above). -w: GCC 15
# floods the build with warnings until CI cuts logs; errors still fail.
RUN --mount=type=cache,target=/var/cache/ccache \
    export CMAKE_C_COMPILER_LAUNCHER=ccache CMAKE_CXX_COMPILER_LAUNCHER=ccache \
      CXXFLAGS="-w" CFLAGS="-w" \
    && python3 tools/intel_llvm_build.py --contrib --yes --tag "${XESTRATA_LLVM_TAG}" --jobs "${XESTRATA_JOBS:-$(nproc)}" \
    && grep -q "\"tag\": \"${XESTRATA_LLVM_TAG}\"" /opt/xestrata/.tools/intel-llvm-contrib/install/XESTRATA.json \
    && test -n "$(ls /opt/xestrata/.tools/intel-llvm-contrib/install/lib/libur_adapter_cuda.so* 2>/dev/null)"

# Pre-install pip deps + stamp so first start skips pip.
RUN python3 -m venv .venv \
    && .venv/bin/pip install --no-cache-dir -r requirements.txt \
    && .venv/bin/python -c "import json; from pathlib import Path; import setup; Path('.venv/.strata-pip.json').write_text(json.dumps(sorted(set(setup.requirement_lines())), indent=0))"

# Engine (contrib-llvm). Empty CUDA archs = Intel-only.
RUN --mount=type=cache,target=/var/cache/ccache \
    export PATH="/usr/local/cuda-13.1/bin:${PATH}" \
    && cmake -G Ninja -S /opt/xestrata -B /build/engine \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
      -DCMAKE_CXX_COMPILER=/opt/xestrata/.tools/intel-llvm-contrib/install/bin/clang++ \
      -DCMAKE_C_COMPILER=/opt/xestrata/.tools/intel-llvm-contrib/install/bin/clang \
      -DSTRATA_LICENSE=contrib \
      -DSTRATA_CUDA_ARCHS="${XESTRATA_CUDA_ARCHS}" \
      -DSTRATA_CUDA_PATH=/usr/local/cuda-13.1 -DSTRATA_CUDA_PTX= \
      -DSTRATA_HIP_ARCHS= \
      -DSTRATA_ONEMKL=ON -DMKL_ROOT=/opt/intel/oneapi/mkl/latest \
      -DSTRATA_ENABLE_XE=ON -DSTRATA_NATIVE_EXPERTS=ON \
      -DSTRATA_BUILD_TESTS=OFF -DSTRATA_PORTABLE=ON \
      -DSTRATA_GGML_DIR=/opt/xestrata/third_party/main/llama.cpp \
    && cmake --build /build/engine --target strata -j "${XESTRATA_JOBS:-$(nproc)}"

# Stage engine libs into the tree, fix RPATHs, trim oneMKL to what oneMath uses.
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

# Stamp engine/BUILD.json as setup.py would, so the pod accepts the engine.
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
# oneMKL segfault 2026-10-14; 0 retries it.
ENV STRATA_NO_BLAS=1

# MTP verify segfault 2026-10-14; 7 is upstream default.
ENV STRATA_ROUTE_TAIL_SKIP=0

# Runtime deps (re-check names when bumping UBUNTU_RELEASE).
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl \
      python3 python3-venv \
      python3-numpy python3-jinja2 python3-regex python3-yaml python3-tqdm \
      python3-requests python3-pil python3-psutil \
      libze1 ocl-icd-libopencl1 ocl-icd-opencl-dev \
      libstdc++-15-dev libblosc2-7 binutils libhwloc15 \
    && rm -rf /var/lib/apt/lists/*

# Pinned Intel userspace (see xestrata/Dockerfile).
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

# Pre-warmed tree + trimmed oneMKL closure; smoke-test the toolchain.
COPY --from=builder /opt/xestrata /opt/xestrata
COPY --from=builder /mkl-stage/opt/intel/oneapi/mkl/latest /opt/intel/oneapi/mkl/latest
RUN rm -rf /opt/xestrata/.git /opt/xestrata/bench \
      /opt/xestrata/.tools/intel-llvm-contrib/src \
    && test -x /opt/xestrata/engine/strata \
    && test -f /opt/xestrata/engine/BUILD.json \
    && test -n "$(ls /opt/xestrata/engine/lib/libonemath_blas_mklgpu.so* 2>/dev/null)" \
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

# `xestrata` wrapper against the tree venv.
RUN printf '#!/bin/sh\nPYTHONDONTWRITEBYTECODE=1\nexport PYTHONDONTWRITEBYTECODE\nif [ "$1" = chat ]; then shift; exec /opt/xestrata/.venv/bin/python /opt/xestrata/chat.py "$@"; fi\nexec /opt/xestrata/.venv/bin/python /opt/xestrata/setup.py "$@"\n' \
      > /usr/local/bin/xestrata \
    && chmod +x /usr/local/bin/xestrata \
    && command -v xestrata

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/data", "/config"]
EXPOSE 8095
ENTRYPOINT ["/entrypoint.sh"]
