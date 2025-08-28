#!/usr/bin/env bash
# Show stats for a glob of files. By GPT-5.

set -euo pipefail
export LC_ALL=C

# Human-readable (SI, 1 decimal under 10, none >=10)
hr() {
  local n=${1:-0} u=(B K M G T P E) i=0 rem=0
  while (( n >= 1000 && i < ${#u[@]}-1 )); do
    rem=$(( n % 1000 ))
    n=$(( n / 1000 ))
    ((i++))
  done
  if (( i == 0 )); then echo "${n}${u[i]}"; return; fi
  local d=$(( (rem + 50) / 100 ))     # one decimal rounded
  if (( d == 10 )); then
    n=$((n+1)); d=0
    if (( n == 1000 && i < ${#u[@]}-1 )); then n=1; ((i++)); fi
  fi
  (( n >= 10 )) && echo "${n}${u[i]}" || echo "${n}.${d}${u[i]}"
}

# Collect sizes to tmp, sort
tmp=$(mktemp -t fszstats.XXXXXX); trap 'rm -f "$tmp"' EXIT
for f in "$@"; do [ -f "$f" ] && stat -f%z "$f" || true; done > "$tmp"
sort -n -o "$tmp" "$tmp"

n=$(wc -l < "$tmp" | tr -d ' ')            # count
s=$(awk '{x+=$1} END{print x+0}' "$tmp")   # sum

get_line() { sed -n "${1}p" "$tmp"; }      # index helpers

# Stats (all integer bytes; p90 = ceil(0.9n)th)
if (( n == 0 )); then
  min=0; max=0; mean=0; med=0; p90=0
else
  min=$(get_line 1)
  max=$(tail -n 1 "$tmp")
  mean=$(( (s + n/2) / n ))                # nearest int
  if (( n % 2 )); then
    med=$(get_line $(( (n+1)/2 )))
  else
    a=$(get_line $(( n/2 ))); b=$(get_line $(( n/2 + 1 )))
    med=$(( (a + b + 1) / 2 ))
  fi
  r=$(( (9*n + 9) / 10 )); (( r<1 )) && r=1; (( r>n )) && r=n
  p90=$(get_line "$r")
fi

echo "files=$n"
echo "sum=$(hr "$s")"
echo "min=$(hr "$min")"
echo "max=$(hr "$max")"
echo "mean=$(hr "$mean")"
echo "median=$(hr "$med")"
echo "p90=$(hr "$p90")"
