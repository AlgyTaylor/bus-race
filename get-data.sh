#!/bin/bash

# Create temp directory
mkdir -p temp

# Download the Wikipedia page HTML
curl -s "https://en.wikipedia.org/wiki/List_of_cities_in_the_United_Kingdom" -o temp/page.html

# Extract city names, regions, and city URLs from the first wikitable
xmllint --html --xpath '//table[contains(@class,"wikitable")][1]//tr[position()>1]' temp/page.html 2>/dev/null \
  | perl -0777 -ne '
      while (/<tr.*?<\/tr>/sg) {
        my $row = $&;
        my @tds = $row =~ /<td[^>]*>(.*?)<\/td>/sg;
        next unless @tds >= 2;
        # Extract city name and link
        my $city_html = $tds[0];
        my ($city_url) = $city_html =~ /<a[^>]+href="([^"]+)"/;
        $city_url = defined $city_url ? $city_url : "";
        for (@tds[0,1]) {
          s/<[^>]+>//g;      # Remove HTML tags
          s/\[[^\]]*\]//g;   # Remove references
          s/^\s+|\s+$//g;    # Trim
        }
        print "$tds[0]\t$tds[1]\t$city_url\n";
      }
    ' > temp/cities.tsv

dms_to_decimal() {
  # $1: DMS string, $2: N/S/E/W
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
  else
    echo ""
    return
  fi
  dec=$(echo "scale=8; $deg + $min/60 + $sec/3600" | bc)
  # South and West are negative
  if [[ "$hem" == "S" || "$hem" == "W" ]]; then
    dec=$(echo "-1 * $dec" | bc)
  fi
  echo "$dec"
}

# For each city, fetch coordinates and output JSON
> temp/cities.jsonl
while IFS=$'\t' read -r city region city_url; do
  if [[ -n "$city_url" ]]; then
    full_city_url="https://en.wikipedia.org${city_url}"
  else
    city_url_name=$(echo "$city" | sed 's/ /_/g')
    full_city_url="https://en.wikipedia.org/wiki/${city_url_name}"
  fi

  curl -s "$full_city_url" -o temp/city.html

  lat_dms=$(xmllint --html --xpath 'string(//span[@class="latitude"])' temp/city.html 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  lon_dms=$(xmllint --html --xpath 'string(//span[@class="longitude"])' temp/city.html 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  lat=$(dms_to_decimal "$lat_dms")
  lon=$(dms_to_decimal "$lon_dms")

  # Only write if both lat and lon are not empty
  if [[ -n "$lat" && -n "$lon" ]]; then
    echo "{\"city\":\"$city\",\"region\":\"$region\",\"latitude\":$lat,\"longitude\":$lon}" >> temp/cities.jsonl
  fi
  sleep 1
done < temp/cities.tsv

jq 'select(.latitude != null and .longitude != null and .latitude != "" and .longitude != "")' temp/cities.jsonl | jq -s '.' > temp/cities.json

# Parse --output argument
OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -n "$OUTPUT" ]]; then
  mv temp/cities.json "$OUTPUT"
  echo "Exported city names and regions to $OUTPUT"
else
  cat temp/cities.json
fi

# Clean up
rm -f temp/page.html temp/cities.jsonl temp/city.html temp/cities.tsv temp/cities.json
