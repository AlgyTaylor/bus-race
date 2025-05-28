#!/bin/bash

# Usage: ./combine-data.sh file1.json file2.json ...

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 file1.json [file2.json ...]" >&2
  exit 1
fi

jq -s 'add' "$@"
