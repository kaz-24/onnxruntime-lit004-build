#!/usr/bin/env bash
set -euxo pipefail

ORT_VERSION="1.16.3"
PYBIN="/opt/python/cp310-cp310/bin"
PYTHON="$PYBIN/python"
WORK="/tmp/ort-lit004-build"
SRC="$WORK/onnxruntime"
OUT="/work/dist"

export PATH="$PYBIN:$PATH"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export CMAKE_BUILD_PARALLEL_LEVEL=2

rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"
rm -f "$OUT"/*.whl "$OUT/build-info.txt" "$OUT/test-output.txt"

# manylinux2014 = CentOS 7 / glibc 2.17 baseline.
# Install only build utilities that may not be present in the image.
yum install -y git which make patch

"$PYTHON" -m pip install --upgrade \
  "pip<25" \
  "setuptools<76" \
  wheel \
  "cmake>=3.26,<4" \
  ninja \
  packaging \
  "numpy==1.26.4" \
  "onnx==1.14.1"

# Clone exact ONNX Runtime release including its pinned submodules.
git clone --branch "v${ORT_VERSION}" --recursive \
  https://github.com/microsoft/onnxruntime.git "$SRC"

cd "$SRC"

# Build CPU-only Python wheel. CPUINFO is explicitly disabled because
# Lolipop lit004 cannot provide /proc/cpuinfo in the form cpuinfo expects.
./build.sh \
  --config Release \
  --update \
  --build \
  --build_wheel \
  --skip_tests \
  --parallel 2 \
  --allow_running_as_root \
  --cmake_extra_defines onnxruntime_ENABLE_CPUINFO=OFF

CACHE="$SRC/build/Linux/Release/CMakeCache.txt"
if [[ ! -f "$CACHE" ]]; then
  echo "CMakeCache.txt not found: $CACHE" >&2
  exit 1
fi

if ! grep -Eq '^onnxruntime_ENABLE_CPUINFO:BOOL=OFF$' "$CACHE"; then
  echo "ERROR: CPUINFO was not disabled in CMakeCache.txt" >&2
  grep -n 'onnxruntime_ENABLE_CPUINFO' "$CACHE" || true
  exit 1
fi

RAW_WHEEL="$(find "$SRC/build" -path '*/dist/*.whl' -type f -print -quit)"
if [[ -z "${RAW_WHEEL:-}" || ! -f "$RAW_WHEEL" ]]; then
  echo "ERROR: wheel was not produced" >&2
  find "$SRC/build" -name '*.whl' -print || true
  exit 1
fi

# Repair/tag for the CentOS 7 / glibc 2.17 manylinux2014 baseline.
# The manylinux image already contains auditwheel.
mkdir -p "$WORK/repaired"
auditwheel show "$RAW_WHEEL"
auditwheel repair \
  --plat manylinux2014_x86_64 \
  -w "$WORK/repaired" \
  "$RAW_WHEEL"

FINAL_WHEEL="$(find "$WORK/repaired" -name '*.whl' -type f -print -quit)"
if [[ -z "${FINAL_WHEEL:-}" || ! -f "$FINAL_WHEEL" ]]; then
  echo "ERROR: repaired wheel was not produced" >&2
  exit 1
fi

cp "$FINAL_WHEEL" "$OUT/"

# Install the custom wheel in the CPython 3.10 environment and verify that
# ONNX Runtime can initialize a real CPU InferenceSession without cpuinfo.
"$PYTHON" -m pip uninstall -y onnxruntime onnxruntime-gpu || true
"$PYTHON" -m pip install --no-deps --force-reinstall "$FINAL_WHEEL"

"$PYTHON" /work/scripts/verify_ort.py 2>&1 | tee "$OUT/test-output.txt"

{
  echo "target=lit004"
  echo "onnxruntime_version=${ORT_VERSION}"
  echo "python=$($PYTHON --version 2>&1)"
  echo "architecture=$(uname -m)"
  echo "container_glibc=$(getconf GNU_LIBC_VERSION)"
  echo "manylinux_target=manylinux2014_x86_64"
  echo "cpuinfo=OFF"
  echo "wheel=$(basename "$FINAL_WHEEL")"
  echo "cmake_cache_cpuinfo=$(grep '^onnxruntime_ENABLE_CPUINFO:' "$CACHE")"
} > "$OUT/build-info.txt"

cat "$OUT/build-info.txt"
