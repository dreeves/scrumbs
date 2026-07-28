#!/bin/bash
# Quals for scrumblib.sh and sweep.sh. Run: ./quals.sh
# Each qual states what we did (replicata), what we expected (expectata), and
# on failure what we got instead (resultata).

cd "$(dirname "$0")" || exit 1
fails=0

# q <description> <expectata> <resultata>
q() {
  if [[ "$2" == "$3" ]]; then echo "PASS: $1"
  else echo "FAIL: $1 -- expected [$2] got [$3]"; fails=$((fails+1)); fi
}

. ./scrumblib.sh || { echo "FAIL: cannot source scrumblib.sh"; exit 1; }

#-------------------------------------------------------------------------------
# parsedur: duration tokens to seconds; garbage dies loudly
#-------------------------------------------------------------------------------

q "parsedur 5s"  5        "$(parsedur 5s)"
q "parsedur 1m"  60       "$(parsedur 1m)"
q "parsedur 1h"  3600     "$(parsedur 1h)"
q "parsedur 1d"  86400    "$(parsedur 1d)"
q "parsedur 1w"  604800   "$(parsedur 1w)"
q "parsedur 1y"  31536000 "$(parsedur 1y)"
(parsedur 5x  2>/dev/null); q "parsedur rejects 5x"  1 $?
(parsedur s5  2>/dev/null); q "parsedur rejects s5"  1 $?
(parsedur ""  2>/dev/null); q "parsedur rejects ''"  1 $?

#-------------------------------------------------------------------------------
# bandsparse: bands line to edge/period lists in seconds; bad lines die
#-------------------------------------------------------------------------------

bandsparse "1h:5s 1d:1m 7d:5m 30d:1h 1y:1d"
q "bandsparse edges" "3600 86400 604800 2592000 31536000 " "$edges"
q "bandsparse pers"  "5 60 300 3600 86400 "                "$pers"
(bandsparse "1h:5s 1d:1s"     2>/dev/null); q "bandsparse rejects decreasing periods" 1 $?
(bandsparse "1d:5s 1h:1m"     2>/dev/null); q "bandsparse rejects non-increasing ages" 1 $?
(bandsparse "1h:5s bogus"     2>/dev/null); q "bandsparse rejects malformed pair" 1 $?

#-------------------------------------------------------------------------------
# name2epoch: filename to "epoch name" using the wall-clock time in the name.
# Oracle: gdate -u, since our epochs live in local-wall-time space.
#-------------------------------------------------------------------------------

want=$(/opt/homebrew/bin/gdate -u -d "2026-07-23 15:55:33" +%s)
got=$(echo "s2026-07-23-THU-15-55-33-d1.jpg" | name2epoch)
q "name2epoch vs gdate oracle" "$want s2026-07-23-THU-15-55-33-d1.jpg" "$got"
want=$(/opt/homebrew/bin/gdate -u -d "1970-01-01 00:00:00" +%s)
got=$(echo "s1970-01-01-THU-00-00-00-d2.webp" | name2epoch)
q "name2epoch at the epoch" "$want s1970-01-01-THU-00-00-00-d2.webp" "$got"
(echo "scd1-dow-hh-00-00.png" | name2epoch >/dev/null 2>&1)
q "name2epoch rejects legacy dow-hh names" 1 $?
(echo "scd1-2026-07-23-THU-15-55-33.jpg" | name2epoch >/dev/null 2>&1)
q "name2epoch rejects retired scdN-first names" 1 $?
(echo "s2026-07-23-THU-15-55-33-d1.png" | name2epoch >/dev/null 2>&1)
q "name2epoch rejects png (jpg/webp only)" 1 $?

#-------------------------------------------------------------------------------
# cullwalk: the anchor walk. Bands "100s:10s 1000s:100s", now=10000.
# Files at ages 1100 (beyond horizon) and 950,890,600,550,505,150,50,45,40,5.
# Hand-walked: the horizon file dies, age-550 dies (9495-9400 < 100),
# everything else survives.
#-------------------------------------------------------------------------------

cullin="8900 f-age1100
9050 f-age950
9110 f-age890
9400 f-age600
9450 f-age550
9495 f-age505
9850 f-age150
9950 f-age50
9955 f-age45
9960 f-age40
9995 f-age5"
q "cullwalk deletions" "f-age1100 f-age550" \
  "$(echo "$cullin" | cullwalk 10000 "100 1000" "10 100" | tr '\n' ' ' | sed 's/ $//')"
q "cullwalk keeps everything when n<=2" "" \
  "$(echo "9995 f-solo" | cullwalk 10000 "100 1000" "10 100")"

#-------------------------------------------------------------------------------
# sweep.sh end to end. Bands "1m:5s 5m:1m" in a temp dir:
#   A red jpg aged ~200s   -> crossed band 0: archived to webp
#   B red jpg aged ~130s   -> identical to A: deduped away
#   C blue jpg aged ~90s   -> differs from A: archived to webp
#   D red jpg aged ~20s    -> still in band 0: untouched
#   E red jpg aged ~400s   -> beyond the 5m horizon: deleted
# 64x64 images so a full-frame color change (4096 px) clears dedupethresh=1000.
#-------------------------------------------------------------------------------

tmpd=$(mktemp -d)
gd=/opt/homebrew/bin/gdate
mick=/opt/homebrew/bin/magick
$mick -size 64x64 xc:red  "$tmpd/red.jpg"
$mick -size 64x64 xc:blue "$tmpd/blue.jpg"
stamp() { $gd -d "$1 seconds ago" '+%Y-%m-%d-%a-%H-%M-%S' | tr a-z A-Z; }
A="s$(stamp 200)-d1.jpg"; cp "$tmpd/red.jpg"  "$tmpd/$A"
B="s$(stamp 130)-d1.jpg"; cp "$tmpd/red.jpg"  "$tmpd/$B"
C="s$(stamp  90)-d1.jpg"; cp "$tmpd/blue.jpg" "$tmpd/$C"
D="s$(stamp  20)-d1.jpg"; cp "$tmpd/red.jpg"  "$tmpd/$D"
E="s$(stamp 400)-d1.jpg"; cp "$tmpd/red.jpg"  "$tmpd/$E"
rm "$tmpd/red.jpg" "$tmpd/blue.jpg"
cat > "$tmpd/conf" <<EOF
path="$tmpd"
bands="1m:5s 5m:1m"
imgq=32
fuzz="4%"
dedupethresh=1000
EOF
SCRUMBSCONF="$tmpd/conf" ./sweep.sh >/dev/null 2>"$tmpd/err"
q "sweep exits 0" 0 $?
[[ -s "$tmpd/err" ]] && sed 's/^/  sweep stderr: /' "$tmpd/err"
q "sweep deletes E (beyond horizon)"   "gone"    "$([[ -e $tmpd/$E ]] && echo here || echo gone)"
q "sweep dedupes B (same as A)"        "gone"    "$([[ -e $tmpd/$B ]] && echo here || echo gone)"
q "sweep archives A to webp"           "here"    "$([[ -e $tmpd/${A%.jpg}.webp ]] && echo here || echo gone)"
q "sweep removes A's jpg"              "gone"    "$([[ -e $tmpd/$A ]] && echo here || echo gone)"
q "sweep archives C to webp"           "here"    "$([[ -e $tmpd/${C%.jpg}.webp ]] && echo here || echo gone)"
q "sweep leaves D alone (band 0)"      "here"    "$([[ -e $tmpd/$D ]] && echo here || echo gone)"
rm -rf "$tmpd"

#-------------------------------------------------------------------------------
# crumbloop end to end: run briefly with a temp conf; it should start cleanly
# and spawn a sweep right away, even when the machine is idle. No assertions
# on capture files since an idle machine legitimately skips captures.
#-------------------------------------------------------------------------------

tmpl=$(mktemp -d)
cat > "$tmpl/conf" <<EOF
path="$tmpl"
bands="1m:5s 5m:1m"
sweepevery=5m
imgq=32
fuzz="4%"
dedupethresh=1000
EOF
SCRUMBSCONF="$tmpl/conf" ./crumbloop.sh >"$tmpl/loop.log" 2>&1 &
lpid=$!
sleep 3
kill $lpid 2>/dev/null; wait $lpid 2>/dev/null
q "crumbloop spawns a sweep on startup" "here" \
  "$([[ -e $tmpl/sweep.log ]] && echo here || echo gone)"
q "spawned sweep finished and released its lock" "gone" \
  "$([[ -d $tmpl/.sweeplock ]] && echo here || echo gone)"
rm -rf "$tmpl"

#-------------------------------------------------------------------------------

echo
if [[ $fails -eq 0 ]]; then echo "ALL QUALS GREEN"
else echo "$fails QUAL(S) RED"; exit 1; fi
