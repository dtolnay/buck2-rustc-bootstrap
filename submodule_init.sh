#!/bin/bash

set -e -x
cd -P -- "$(dirname -- "$0")"

git submodule update --init rust
cd rust
git submodule update --init library/backtrace
