# XeStrata runtime image from upstream's .deb (Ubuntu).
#
# Installs the prebuilt contrib package (xestrata-contrib-cuda13.1 by
# default, CUDA 13.1 PTX for Turing through Hopper — the same arch set the
# xestrata-llvm source image can build) instead of compiling intel/llvm and
# the engine. Fast build, fast start: setup.py sees
# `engine already built for this PC` and never recompiles in the pod.
#
# What the deb holds (cmake/packaging.cmake): setup.py as `xestrata` plus
# the server/web/tools in /usr/share/xestrata (read-only, PACKAGED mode —
# user files go to $XDG_CONFIG_HOME/xestrata), and the engine (strata, the
# CPU+Vulkan image encoders, intel/llvm's SYCL runtime libsycl.so.9 with
# its Level Zero/CUDA adapters, oneMath with its oneMKL/cuBLAS/rocBLAS
# backends) in <libdir>/xestrata/engine with engine/BUILD.json.
#
# GPU vendors are Suggests, not Requires: the image installs no CUDA
# toolkit, no oneMKL, no ROCm. oneMath opens cuBLAS/oneMKL and the UR
# adapters open their drivers at run time, only on hosts with those GPUs
# (upstream's container.sh does the same). Intel-only hosts need nothing
# else; NVIDIA hosts need a driver that loads the variant's PTX plus
# cuBLAS, AMD hosts need ROCm's HIP runtime/rocBLAS/hipBLASLt.
#
# Assumptions baked in (same as xestrata-llvm):
# - Own-kernel GEMMs (STRATA_NO_BLAS=1): oneMath's oneMKL backend
#   segfaulted on the intel/llvm 7.1.1 UR Level Zero v2 stack (gdb
#   backtrace 2026-10-14). Pass -e STRATA_NO_BLAS=0 to retry oneMKL on
#   Intel or for cuBLAS on NVIDIA hosts.
# - Exact expert routing (STRATA_ROUTE_TAIL_SKIP=0): the engine segfaulted
#   in MTP suffix-draft verification with tail-skip on while verify
#   captures ran nearly out of VRAM (2026-10-14). Pass
#   -e STRATA_ROUTE_TAIL_SKIP=7 to re-enable upstream's default.
# - Text-only by default (XESTRATA_VISION=no): the deb does ship the
#   Vulkan/CPU image encoders (mesa-vulkan-drivers is installed), so set
#   XESTRATA_VISION=yes|gpu|cpu to let the model read images.
#
# Verify after building (on the B70 host):
#   docker run --rm --device /dev/dri <image> xestrata --check

ARG UBUNTU_RELEASE=26.04
# Upstream git tag (release name, e.g. xe0.1.43.1). The .deb file name
# carries the Debian version (e.g. 0.1.43-2), so the build resolves it via
# the release's SHA256SUMS instead of reconstructing it from the tag.
ARG XESTRATA_REF=xe0.1.43.1
# Upstream package variant (tools/package/build.sh variant with the
# contrib prefix, e.g. contrib-cuda13.1 or contrib-cuda12.4). cuda12.4
# covers Pascal and Volta (sm_60/sm_61/sm_70); CUDA 13 builds drop them,
# so a P100/P40/V100 takes cuda12.4. Newer GPUs run the newest PTX their
# driver compiles.
ARG XESTRATA_VARIANT=contrib-cuda13.1

FROM ubuntu:${UBUNTU_RELEASE}
ARG XESTRATA_REF
ARG XESTRATA_VARIANT
ENV DEBIAN_FRONTEND=noninteractive
# Own-kernel GEMMs by default (see header note).
ENV STRATA_NO_BLAS=1
# Exact expert routing in verify windows (see header note).
ENV STRATA_ROUTE_TAIL_SKIP=0

# Upstream .deb, SHA256SUMS-verified. Resolved by variant + arch instead
# of reconstructing the Debian version from the tag (xe0.1.43.1 ->
# 0.1.43-2 is a release count, not the tag suffix).
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && cd /tmp \
    && curl -fsSLO "https://github.com/MistVVK/XeStrata/releases/download/${XESTRATA_REF}/SHA256SUMS" \
    && DEB="$(grep -o "xestrata-${XESTRATA_VARIANT}_[^ ]*_amd64\\.deb" SHA256SUMS | head -n 1)" \
    && test -n "${DEB}" \
    && echo "installing ${DEB} for ${XESTRATA_REF}" \
    && curl -fsSLO "https://github.com/MistVVK/XeStrata/releases/download/${XESTRATA_REF}/${DEB}" \
    && grep -F " ${DEB}" SHA256SUMS | sha256sum -c - \
    && apt-get update && apt-get install -y --no-install-recommends "./${DEB}" mesa-vulkan-drivers \
    && rm -f "./${DEB}" SHA256SUMS \
    && rm -rf /var/lib/apt/lists/* \
    && command -v xestrata

# Intel Level Zero userspace, pinned 26 series (verified release assets).
# Re-pin all four together. Ubuntu 26.04 ships an older compute-runtime
# (device-memory bug) and IGC 2.27-2.30 (miscompile on Arc B-series /
# Lunar / Panther Lake), so the deb's Suggests are not enough here.
# Every step is &&-chained on purpose: a failed download or install must
# fail the build here, not limp on without a GPU driver.
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

# Self-checks: the deb's layout (PACKAGED mode), contrib engine, bundled
# SYCL 9 runtime, both vision encoders, and no missing engine libs except
# the vendor ones that only exist on their hosts (cuBLAS/oneMKL/ROCm open
# at run time — see header note).
RUN ENGINE_BUILD="$(dpkg -L "xestrata-${XESTRATA_VARIANT}" 2>/dev/null | grep '/xestrata/engine/BUILD.json$' | head -n 1)" \
    && test -n "${ENGINE_BUILD}" \
    && echo "engine BUILD.json: ${ENGINE_BUILD}" \
    && test -f /usr/share/xestrata/setup.py \
    && test -f /usr/share/xestrata/PACKAGED \
    && ENGINE_DIR="$(dirname "${ENGINE_BUILD}")" \
    && test -x "${ENGINE_DIR}/strata" \
    && test -x "${ENGINE_DIR}/strata-vision-cpu" \
    && test -x "${ENGINE_DIR}/strata-vision-vulkan" \
    && test -n "$(ls "${ENGINE_DIR}"/lib/libsycl.so.9* 2>/dev/null)" \
    && test -n "$(ls "${ENGINE_DIR}"/lib/libonemath_blas_mklgpu.so* 2>/dev/null)" \
    && test -n "$(ls "${ENGINE_DIR}"/lib/libonemath_blas_cublas.so* 2>/dev/null)" \
    && /usr/bin/python3 -c 'import json, sys; build = json.load(open(sys.argv[1], encoding="utf-8")); assert build.get("license") == "contrib", build; assert build.get("source") == "package", build; print("engine:", build.get("package"), build.get("version"), build.get("license"))' "${ENGINE_BUILD}" \
    && (LD_LIBRARY_PATH="${ENGINE_DIR}/lib" ldd "${ENGINE_DIR}/strata" | grep 'not found' | grep -v -E 'libcublas|libmkl|libamdhip|librocblas|libhipblas' || true) \
    && ! (LD_LIBRARY_PATH="${ENGINE_DIR}/lib" ldd "${ENGINE_DIR}/strata" | grep 'not found' | grep -v -E 'libcublas|libmkl|libamdhip|librocblas|libhipblas')

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME ["/data", "/config"]
EXPOSE 8095
ENTRYPOINT ["/entrypoint.sh"]
