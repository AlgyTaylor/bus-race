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

  # Try to extract latitude and longitude (DMS) from span.latitude/span.longitude
  lat_dms=$(xmllint --html --xpath 'string(//span[@class="latitude"])' temp/page.html 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  lon_dms=$(xmllint --html --xpath 'string(//span[@class="longitude"])' temp/page.html 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  lat=""
  lon=""

  if [[ -n "$lat_dms" && -n "$lon_dms" ]]; then
    lat=$(dms_to_decimal "$lat_dms")
    lon=$(dms_to_decimal "$lon_dms")
  else
    # Try to extract decimal degrees from span.geo-dec (e.g. "55.423°N 5.608°W")
    geo_dec=$(xmllint --html --xpath 'string(//span[contains(@class,"geo-dec")])' temp/page.html 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ -n "$geo_dec" ]]; then
      # Example: "55.423°N 5.608°W"
      lat_part=$(echo "$geo_dec" | awk '{print $1}')
      lon_part=$(echo "$geo_dec" | awk '{print $2}')
      lat=$(dms_to_decimal "$lat_part")
      lon=$(dms_to_decimal "$lon_part")
    else
      # Try to extract from span.geo (e.g. "55.423; -5.608")
      geo=$(xmllint --html --xpath 'string(//span[contains(@class,"geo")])' temp/page.html 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [[ "$geo" =~ ^([0-9\.\-]+)[\;\,[:space:]]+([0-9\.\-]+) ]]; then
        lat="${BASH_REMATCH[1]}"
        lon="${BASH_REMATCH[2]}"
      else
        # Try to extract from JS variable wgCoordinates
        coords=$(grep -o '"wgCoordinates":{[^}]*}' temp/page.html | head -n1)
        if [[ "$coords" =~ \"lat\":([0-9\.\-]+) ]]; then
          lat="${BASH_REMATCH[1]}"
        fi
        if [[ "$coords" =~ \"lon\":([0-9\.\-]+) ]]; then
          lon="${BASH_REMATCH[1]}"
        fi
      fi
    fi
  fi

  # Extract region from infobox: "Principal area"
  region=$(xmllint --html --xpath '//th[contains(translate(.,"ABCDEFGHIJKLMNOPQRSTUVWXYZ","abcdefghijklmnopqrstuvwxyz"),"principal area")]/following-sibling::td[1]' temp/page.html 2>/dev/null | \
    sed -E 's/<[^>]+>//g;s/\[[^]]*\]//g;s/^[[:space:]]*//;s/[[:space:]]*$//') || region=""

  # Fallback: if region is empty, try "Unitary authority" or "County"
  if [[ -z "$region" ]]; then
    region=$(xmllint --html --xpath '//th[contains(translate(.,"ABCDEFGHIJKLMNOPQRSTUVWXYZ","abcdefghijklmnopqrstuvwxyz"),"unitary authority")]/following-sibling::td[1]' temp/page.html 2>/dev/null | \
      sed -E 's/<[^>]+>//g;s/\[[^]]*\]//g;s/^[[:space:]]*//;s/[[:space:]]*$//') || region=""
  fi
  if [[ -z "$region" ]]; then
    region=$(xmllint --html --xpath '//th[contains(translate(.,"ABCDEFGHIJKLMNOPQRSTUVWXYZ","abcdefghijklmnopqrstuvwxyz"),"county")]/following-sibling::td[1]' temp/page.html 2>/dev/null | \
      sed -E 's/<[^>]+>//g;s/\[[^]]*\]//g;s/^[[:space:]]*//;s/[[:space:]]*$//') || region=""
  fi
  # Add support for Scottish infoboxes: "Council area" and "Lieutenancy area"
  if [[ -z "$region" ]]; then
    region=$(xmllint --html --xpath '//th[contains(translate(.,"ABCDEFGHIJKLMNOPQRSTUVWXYZ","abcdefghijklmnopqrstuvwxyz"),"council area")]/following-sibling::td[1]' temp/page.html 2>/dev/null | \
      sed -E 's/<[^>]+>//g;s/\[[^]]*\]//g;s/^[[:space:]]*//;s/[[:space:]]*$//') || region=""
  fi
  if [[ -z "$region" ]]; then
    region=$(xmllint --html --xpath '//th[contains(translate(.,"ABCDEFGHIJKLMNOPQRSTUVWXYZ","abcdefghijklmnopqrstuvwxyz"),"lieutenancy area")]/following-sibling::td[1]' temp/page.html 2>/dev/null | \
      sed -E 's/<[^>]+>//g;s/\[[^]]*\]//g;s/^[[:space:]]*//;s/[[:space:]]*$//') || region=""
  fi

  # Only output if lat/lon are present (region can be empty)
  if [[ -n "$lat" && -n "$lon" ]]; then
    # Ensure leading zero for decimals (e.g. -.973 → -0.973, .973 → 0.973)
    lat=$(echo "$lat" | sed -E 's/^(-?)\./\10./')
    lon=$(echo "$lon" | sed -E 's/^(-?)\./\10./')
    if [[ $first -eq 0 ]]; then
      echo ","
    fi
    printf '{"city":"%s","region":"%s","latitude":%s,"longitude":%s}' \
      "$(echo "$name" | sed 's/"/\\"/g')" \
      "$(echo "$region" | sed 's/"/\\"/g')" \
      "$lat" "$lon"
    first=0
  else
    # Print warning to stderr but do not fail
    echo "Warning: Skipping $url (missing lat/lon)" >&2
  fi
  sleep 1
done < "$INPUT"

echo
echo "]"

# Clean up
rm -f temp/page.html temp/stdin-towns.txt
