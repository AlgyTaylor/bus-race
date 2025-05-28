#!/usr/bin/env bash

# Requirements: jq, node

CHECKPOINTS=4
while [[ $# -gt 0 ]]; do
  case "$1" in
    --checkpoints)
      CHECKPOINTS="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

CHECKPOINTS=$CHECKPOINTS node <<'EOF'
const fs = require('fs');
const crypto = require('crypto');

// Parse checkpoints from environment or default to 4
const checkpoints = parseInt(process.env.CHECKPOINTS || "4", 10);

// Load cities.json
const cities = JSON.parse(fs.readFileSync('cities.json', 'utf8'));

// Filter cities with latitude and longitude
const validCities = cities.filter(
  c => typeof c.latitude === 'number' && typeof c.longitude === 'number'
);

// Pick 4 random cities (robust shuffle)
function pickRandom(arr, n) {
  if (arr.length < n) {
    throw new Error('Not enough cities with coordinates');
  }
  const copy = arr.slice();
  for (let i = copy.length - 1; i > 0; i--) {
    const j = crypto.randomInt(i + 1);
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy.slice(0, n);
}

const picked = pickRandom(validCities, checkpoints);

// Calculate distance between two cities (Haversine formula)
function haversine(a, b) {
  const toRad = x => (x * Math.PI) / 180;
  const R = 6371;
  const dLat = toRad(b.latitude - a.latitude);
  const dLon = toRad(b.longitude - a.longitude);
  const lat1 = toRad(a.latitude);
  const lat2 = toRad(b.latitude);
  const aVal =
    Math.sin(dLat / 2) ** 2 +
    Math.sin(dLon / 2) ** 2 * Math.cos(lat1) * Math.cos(lat2);
  return 2 * R * Math.asin(Math.sqrt(aVal));
}

// Generate all permutations of an array
function permute(arr) {
  if (arr.length <= 1) return [arr];
  const result = [];
  for (let i = 0; i < arr.length; i++) {
    const rest = arr.slice(0, i).concat(arr.slice(i + 1));
    for (const p of permute(rest)) {
      result.push([arr[i]].concat(p));
    }
  }
  return result;
}

// Find the pair of cities with the greatest distance
let maxDist = -Infinity, cityPair = [null, null];
for (let i = 0; i < picked.length; i++) {
  for (let j = i + 1; j < picked.length; j++) {
    const dist = haversine(picked[i], picked[j]);
    if (dist > maxDist) {
      maxDist = dist;
      cityPair = [picked[i], picked[j]];
    }
  }
}

// Randomly pick one of the two as the starting city
const startCity = cityPair[crypto.randomInt(2)];
const others = picked.filter(c => c !== startCity || picked.filter(x => x === startCity).length > 1 ? true : false);
const startCityCount = picked.filter(c => c === startCity).length;
let routes = [];
if (startCityCount > 1) {
  // If there are duplicates of the starting city, treat each instance as unique
  // This ensures all 4 cities are included in permutations
  routes = permute(picked);
} else {
  routes = permute(others).map(route => [startCity, ...route]);
}

// Find the route with the shortest total distance
let minDist = Infinity, bestRoute = null;
for (const route of routes) {
  let dist = 0;
  for (let i = 0; i < route.length - 1; i++) {
    dist += haversine(route[i], route[i + 1]);
  }
  if (dist < minDist) {
    minDist = dist;
    bestRoute = route;
  }
}

// Print the ordered list of city names
console.log('Ordered cities:');
bestRoute.forEach(c => console.log(c.city));
EOF
