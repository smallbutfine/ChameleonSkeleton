#!/bin/bash
# Native Linux build of the CLAP plugin (no cross sysroot needed).
# Requires: fpc (FreePascal) on Linux/WSL. Produces clap_skeleton.clap.
set -e
cd "$(dirname "$0")"
fpc -O2 -Mdelphi clap_skeleton.lpr
# FPC names the library libclap_skeleton.so; CLAP wants <name>.clap
if [ -f libclap_skeleton.so ]; then
  cp -f libclap_skeleton.so clap_skeleton.clap
  echo "built: clap_skeleton.clap"
else
  echo "error: libclap_skeleton.so not produced" >&2
  exit 1
fi