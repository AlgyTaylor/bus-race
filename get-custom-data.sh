#!/bin/bash

set -e

# Parse --input argument
INPUT="my-towns.txt"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# If no --input and stdin is not a tty, read from stdin to a temp file
if [[ "$INPUT" == "my-towns.txt" && ! -t 0 ]]; then
  INPUT="temp/stdin-towns.txt"
  mkdir -p temp
  cat > "$INPUT"
fi

mkdir -p temp

dms_to_decimal() {
  dms="$1"
  if [[ -z "$dms" ]]; then
    echo ""
    return
  fi
  # Extract degrees, minutes, seconds, hemisphere
  if [[ "$dms" =~ ([0-9]+)°([0-9]+)?′?([0-9]+)?″?([NSEW]) ]]; then
    deg="${BASH_REMATCH[1]}"
    min="${BASH_REMATCH[2]:-0}"
    sec="${BASH_REMATCH[3]:-0}"
    hem="${BASH_REMATCH[4]}"
  elif [[ "$dms" =~ ([0-9]+)°([0-9]+)?′?([NSEW]) ]]; then
    deg="${BASH_REMATCH[1]}"
    min="${BASH_REMATCH[2]:-0}"
    sec="0"
    hem="${BASH_REMATCH[3]}"
  elif [[ "$dms" =~ ^([0-9]+\.[0-9]+)[[:space:]]*([NSEW])$ ]]; then
    dec="${BASH_REMATCH[1]}"
    hem="${BASH_REMATCH[2]}"
    if [[ "$hem" == "S" || "$hem" == "W" ]]; then
      dec=$(echo "-1 * $dec" | bc)
    fi
    echo "$dec"
    return
  else
    echo ""
    return
  fi
  dec=$(echo "scale=8; $deg + $min/60 + $sec/3600" | bc)
  if [[ "$hem" == "S" || "$hem" == "W" ]]; then
    dec=$(echo "-1 * $dec" | bc)
  fi
  echo "$dec"
}

echo "["

first=1
while read -r url; do
  [ -z "$url" ] && continue
  name=$(basename "$url" | sed 's/_/ /g')
  curl -s "$url" -o temp/page.html

  # Extract latitude and longitude (DMS)
  lat_dms=$(xmllint --html --xpath 'string(//span[@class="latitude"])' temp/page.html 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  lon_dms=$(xmllint --html --xpath 'string(//span[@class="longitude"])' temp/page.html 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  lat=$(dms_to_decimal "$lat_dms")
  lon=$(dms_to_decimal "$lon_dms")

  # Extract region from infobox: "Principal area"
  region=$(xmllint --html --xpath '//th[contains(translate(.,"ABCDEFGHIJKLMNOPQRSTUVWXYZ","abcdefghijklmnopqrstuvwxyz"),"principal area")]/following-sibling::td[1]' temp/page.html 2>/dev/null | \
    sed -E 's/<[^>]+>//g;s/\[[^]]*\]//g;s/^[[:space:]]*//;s/[[:space:]]*$//')

  # Fallback: if region is empty, try "Unitary authority" or "County"
  if [[ -z "$region" ]]; then
    region=$(xmllint --html --xpath '//th[contains(translate(.,"ABCDEFGHIJKLMNOPQRSTUVWXYZ","abcdefghijklmnopqrstuvwxyz"),"unitary authority")]/following-sibling::td[1]' temp/page.html 2>/dev/null | \
      sed -E 's/<[^>]+>//g;s/\[[^]]*\]//g;s/^[[:space:]]*//;s/[[:space:]]*$//')
  fi
  if [[ -z "$region" ]]; then
    region=$(xmllint --html --xpath '//th[contains(translate(.,"ABCDEFGHIJKLMNOPQRSTUVWXYZ","abcdefghijklmnopqrstuvwxyz"),"county")]/following-sibling::td[1]' temp/page.html 2>/dev/null | \
      sed -E 's/<[^>]+>//g;s/\[[^]]*\]//g;s/^[[:space:]]*//;s/[[:space:]]*$//')
  fi

  # Only output if lat/lon and region are present
  if [[ -n "$lat" && -n "$lon" && -n "$region" ]]; then
    if [[ $first -eq 0 ]]; then
      echo ","
    fi
    printf '{"city":"%s","region":"%s","latitude":%s,"longitude":%s}' \
      "$(echo "$name" | sed 's/"/\\"/g')" \
      "$(echo "$region" | sed 's/"/\\"/g')" \
      "$lat" "$lon"
    first=0
  fi
  sleep 1
done < "$INPUT"

echo
echo "]"

# Clean up
rm -f temp/page.html temp/stdin-towns.txt
