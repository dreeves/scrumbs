# scrumblib.sh -- functions shared by crumbloop.sh, sweep.sh, crumbudget.sh, and
# quals.sh.
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
# Zero is no duration (a 0 keep-period divides a span somewhere downstream,
# and a 0 max-age is an empty band), and neither is a leading zero.
parsedur() {
  [[ $1 =~ ^([1-9][0-9]*)([smhdwy])$ ]] || die "unparseable duration: '$1'"
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

# Parse a bands line like "1h:5s 1d:1m 7d:5m 30d:1h inf:1d" into two globals,
# both space-separated seconds: edges (band max-ages, strictly increasing)
# and pers (keep-periods, non-decreasing; the first one is the capture
# frequency). The last band's max-age MUST be the literal "inf": there is no
# horizon, nothing ever ages out, and in particular the oldest screenshot is
# immortal by construction -- no code enforces that invariant because no code
# path can violate it. "inf" stays as-is in edges, which awk's strtod reads
# as IEEE infinity, so every age comparison downstream just works; bash
# arithmetic never sees it because this only does arithmetic on the finite
# (non-last) pairs.
bandsparse() {
  edges=""; pers=""
  local -a bl=($1)
  local n=${#bl[@]}
  (( n >= 2 )) || die "need at least a raw band and the inf band: '$1'"
  [[ ${bl[$((n-1))]} =~ ^inf:([1-9][0-9]*[smhdwy])$ ]] || \
    die "the last band's max-age must be inf: '${bl[$((n-1))]}'"
  local infper=${BASH_REMATCH[1]}
  local pair a p preva=0 prevp=0
  for pair in "${bl[@]:0:$((n-1))}"; do
    [[ $pair =~ ^([1-9][0-9]*[smhdwy]):([1-9][0-9]*[smhdwy])$ ]] || die "bad band: '$pair'"
    a=$(parsedur "${BASH_REMATCH[1]}") || exit 1
    p=$(parsedur "${BASH_REMATCH[2]}") || exit 1
    (( a > preva ))  || die "band max-ages must increase: '$pair'"
    (( p >= prevp )) || die "keep-periods must not decrease: '$pair'"
    preva=$a; prevp=$p
    edges="$edges$a "; pers="$pers$p "
  done
  p=$(parsedur "$infper") || exit 1
  (( p >= prevp )) || die "keep-periods must not decrease: 'inf:$infper'"
  edges="${edges}inf "; pers="$pers$p "
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

# Affirm that an edges list ends in inf, as bandsparse guarantees. The awk
# walkers below lean on that (an age is always inside some band), so a finite
# last edge from any other caller dies here rather than walking wrong.
haltunlessinf() {
  local e=${1% }                 # bandsparse emits a trailing space; shed it
  [[ ${e##* } == inf ]] || die "last band max-age must be inf: '$1'"
}

# The cull walk: cullwalk <nowepoch> <edges> <pers>
# Stdin:  "epoch name" lines sorted oldest first (one display's timeline).
# Stdout: names of files to delete.
# Nothing dies for age -- there is no horizon, so the oldest screenshot is
# immortal by construction and the history-span number stays honest. This is
# the anchor walk from the README: keep the first and last file; keep an
# interior file iff its successor is at least one keep-period past the last
# kept file, where the keep-period comes from the file's own age band. This
# avoids the too-big-gap flaw of naive walk-and-delete.
cullwalk() {
  haltunlessinf "$2"
  awk -v now="$1" -v edg="$2" -v per="$3" '
  BEGIN { nb = split(edg, E, " "); split(per, P, " ") }
  function G(age,   i) {
    for (i = 1; i <= nb; i++) if (age < E[i]) return P[i]
    return -1  # unreachable: every age is under the inf edge
  }
  { ep[NR] = $1; nm[NR] = $2 }
  END {
    if (NR <= 2) exit 0  # no interior points => nothing to cull
    anchor = ep[1]
    for (i = 2; i < NR; i++) {
      if (ep[i+1] - anchor >= G(now - ep[i])) anchor = ep[i]
      else print nm[i]
    }
  }'
}

# What the screenshots on disk actually cost: crumbstat <nowepoch> <edges> <pers>
# Stdin:  "epoch name size" lines, one per screenshot file, in any order.
# Stdout: one line, "<jpgb> <webpb> <occup> <span> <rawmom> <arcmom>":
#   jpgb    mean bytes per capture moment (ie across all displays) while the
#           moment is still raw jpg
#   webpb   ditto once the moment has been archived to webp
#   occup   moments on disk over capture slots the bands have room for. Idle
#           time and dedupe both land here, so it's the fraction of the model's
#           slots that a real screenshot occupies.
#   span    seconds of history on disk, ie the age of the oldest screenshot
#   rawmom  how many moments the jpgb mean rests on
#   arcmom  ditto webpb
# Every file counts: there is no horizon and nothing is ever too old. Except
# a 0-byte file (a disk-full or killed capture, or one mid-write): it joins
# nothing, so membership here is by bytes, the same definition crumbmoms and
# the page's cross-checks use -- one definition, no way to disagree.
crumbstat() {
  haltunlessinf "$2"
  awk -v now="$1" -v edg="$2" -v per="$3" '
  BEGIN { nb = split(edg, E, " "); split(per, P, " ") }
  {
    if ($3 == 0) next
    age = now - $1
    if (age > span) span = age
    mom[$1] = 1
    if ($2 ~ /\.jpg$/) { jb += $3; jm[$1] = 1 } else { wb += $3; wm[$1] = 1 }
  }
  END {
    for (t in mom) nm++
    for (t in jm)  nj++
    for (t in wm)  nw++
    for (i = 1; i <= nb; i++) {
      lo = (i == 1 ? 0 : E[i-1])
      if (span > lo) slots += ((span < E[i] ? span : E[i]) - lo) / P[i]
    }
    if (!nj || !nw || !slots) {
      printf "nothing to measure: %d raw and %d archived moments in %g slots\n", \
        nj, nw, slots > "/dev/stderr"
      exit 1
    }
    printf "%.0f %.0f %.4f %d %d %d\n", jb/nj, wb/nw, nm/slots, span, nj, nw
  }'
}

# The same stream, kept whole: crumbmoms <nowepoch>
# Stdin:  "epoch name size" lines, one per screenshot file, in any order.
# Stdout: one "agesec jpgbytes webpbytes" line per moment, ages ascending.
# Bytes are summed across displays and split by format, so a moment caught
# mid-archival (jpg converted, not yet removed) carries both. A moment whose
# files hold zero bytes is omitted, matching crumbstat's bytes-are-membership
# rule. crumbudget.sh exports these lines so the page can bucket today's
# actual bytes under whatever band edges the reader types -- pre-bucketed
# totals would go stale on the first keystroke that moves an edge.
crumbmoms() {
  awk -v now="$1" '
  {
    if ($2 ~ /\.jpg$/) jb[$1] += $3; else wb[$1] += $3
    seen[$1] = 1
  }
  END {
    for (ep in seen) if (jb[ep] + wb[ep] > 0) print now - ep, jb[ep]+0, wb[ep]+0
  }' | sort -n
}
