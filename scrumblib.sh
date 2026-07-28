# scrumblib.sh -- functions shared by crumbloop.sh, sweep.sh, and quals.sh.
# Pure functions only; sourcing this has no side effects.
#
# Timestamps here live in "local wall-time epoch" space: seconds since
# 1970-01-01 00:00:00 *local* time, computed from the wall-clock digits in a
# filename (or from the current wall clock) with no timezone conversion.
# Deltas between two such epochs are exact except across a DST jump, where
# they're off by an hour twice a year. For culling granularity that's fine.

# Complain and die. Fail loudly, never fix up inputs.
die() { echo "ERROR: $*" >&2; exit 1; }

# Duration token to seconds, eg "5s" -> 5, "1h" -> 3600. Units: s m h d w y.
parsedur() {
  [[ $1 =~ ^([0-9]+)([smhdwy])$ ]] || die "unparseable duration: '$1'"
  local n=${BASH_REMATCH[1]}
  case ${BASH_REMATCH[2]} in
    s) echo "$n"           ;;
    m) echo $((n*60))      ;;
    h) echo $((n*3600))    ;;
    d) echo $((n*86400))   ;;
    w) echo $((n*604800))  ;;
    y) echo $((n*31536000));;
  esac
}

# Parse a bands line like "1h:5s 1d:1m 7d:5m 30d:1h 1y:1d" into two globals,
# both space-separated seconds: edges (band max-ages, strictly increasing;
# the last one is the horizon) and pers (keep-periods, non-decreasing; the
# first one is the capture frequency).
bandsparse() {
  edges=""; pers=""
  local pair atok ptok a p preva=0 prevp=0
  for pair in $1; do
    [[ $pair =~ ^([0-9]+[smhdwy]):([0-9]+[smhdwy])$ ]] || die "bad band: '$pair'"
    atok=${BASH_REMATCH[1]}; ptok=${BASH_REMATCH[2]}
    a=$(parsedur "$atok") || exit 1
    p=$(parsedur "$ptok") || exit 1
    (( a > preva ))  || die "band max-ages must increase: '$pair'"
    (( p >= prevp )) || die "keep-periods must not decrease: '$pair'"
    preva=$a; prevp=$p
    edges="$edges$a "; pers="$pers$p "
  done
  [[ -n $edges ]] || die "empty bands line"
}

# Days from 1970-01-01 for a civil date (Howard Hinnant's algorithm), as an
# awk function body shared by name2epoch and localnow.
CIVILAWK='
function dfc(y, m, d,   era, yoe, doy, doe) {
  y = y - (m <= 2)
  era = int((y >= 0 ? y : y - 399) / 400)
  yoe = y - era*400
  doy = int((153*(m + (m > 2 ? -3 : 9)) + 2)/5) + d - 1
  doe = yoe*365 + int(yoe/4) - int(yoe/100) + doy
  return era*146097 + doe - 719468
}'

# Read screenshot basenames on stdin, one per line, and emit "epoch name" for
# each. Names must match sYYYY-MM-DD-DOW-HH-MM-SS-dN.(jpg|webp) exactly --
# date first so lexical order is chronological, display number last so it
# doesn't break that ordering. Anything else, including legacy filenames,
# kills the whole run.
name2epoch() {
  awk -F'[-.]' "$CIVILAWK"'
  {
    if (NF != 9 || $1 !~ /^s[0-9][0-9][0-9][0-9]$/ \
        || $4 !~ /^[A-Z][A-Z][A-Z]$/ || $8 !~ /^d[0-9]+$/ \
        || ($9 != "jpg" && $9 != "webp") \
        || $2 < 1 || $2 > 12 || $3 < 1 || $3 > 31 \
        || $5 > 23 || $6 > 59 || $7 > 59) {
      printf "unparseable screenshot filename: %s\n", $0 > "/dev/stderr"
      exit 1
    }
    print dfc(substr($1, 2)+0, $2+0, $3+0)*86400 + $5*3600 + $6*60 + $7, $0
  }'
}

# Current wall clock as a local wall-time epoch (see header comment).
localnow() {
  /opt/homebrew/bin/gdate '+%Y %m %d %H %M %S' | \
    awk "$CIVILAWK"'{ print dfc($1+0, $2+0, $3+0)*86400 + $4*3600 + $5*60 + $6 }'
}

# The cull walk: cullwalk <nowepoch> <edges> <pers>
# Stdin:  "epoch name" lines sorted oldest first (one display's timeline).
# Stdout: names of files to delete.
# Anything at or beyond the horizon (last edge) dies. The rest get the
# anchor walk from the README: keep the first and last file; keep an interior
# file iff its successor is at least one keep-period past the last kept file,
# where the keep-period comes from the file's own age band. This avoids the
# too-big-gap flaw of naive walk-and-delete.
cullwalk() {
  awk -v now="$1" -v edg="$2" -v per="$3" '
  BEGIN { nb = split(edg, E, " "); split(per, P, " ") }
  function G(age,   i) {
    for (i = 1; i <= nb; i++) if (age < E[i]) return P[i]
    return -1  # unreachable: horizon files are filtered before the walk
  }
  { ep[NR] = $1; nm[NR] = $2 }
  END {
    n = 0
    for (i = 1; i <= NR; i++) {
      if (now - ep[i] >= E[nb]) print nm[i]
      else { n++; e[n] = ep[i]; m[n] = nm[i] }
    }
    if (n <= 2) exit 0  # no interior points => nothing to cull
    anchor = e[1]
    for (i = 2; i < n; i++) {
      if (e[i+1] - anchor >= G(now - e[i])) anchor = e[i]
      else print m[i]
    }
  }'
}
