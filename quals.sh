#!/bin/bash
# Quals for scrumblib.sh, sweep.sh, crumbloop.sh, and crumbudget.sh.
# Run: ./quals.sh
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
(parsedur 0s  2>/dev/null); q "parsedur rejects a zero duration" 1 $?
(parsedur 05s 2>/dev/null); q "parsedur rejects a leading zero" 1 $?

#-------------------------------------------------------------------------------
# bandsparse: bands line to edge/period lists in seconds; bad lines die.
# The last band's max-age MUST be inf: there is no horizon, nothing ever ages
# out, and so the oldest-screenshot-never-deleted invariant holds structurally
# rather than by enforcement code.
#-------------------------------------------------------------------------------

bandsparse "1h:5s 1d:1m 7d:5m 30d:1h inf:1d"
q "bandsparse edges" "3600 86400 604800 2592000 inf " "$edges"
q "bandsparse pers"  "5 60 300 3600 86400 "           "$pers"
(bandsparse "1h:5s 1d:1s inf:1s" 2>/dev/null); q "bandsparse rejects decreasing periods" 1 $?
(bandsparse "1d:5s 1h:1m inf:1h" 2>/dev/null); q "bandsparse rejects non-increasing ages" 1 $?
(bandsparse "1h:5s bogus inf:1m" 2>/dev/null); q "bandsparse rejects malformed pair" 1 $?
(bandsparse "1h:5s 1y:1m"        2>/dev/null); q "bandsparse rejects a finite horizon" 1 $?
(bandsparse "inf:1m"             2>/dev/null); q "bandsparse rejects a lone inf band" 1 $?
(bandsparse "inf:5s 1y:1m"       2>/dev/null); q "bandsparse rejects bands after inf" 1 $?
(bandsparse "1h:5s 1d:inf"       2>/dev/null); q "bandsparse rejects inf as a period" 1 $?
(bandsparse "1h:0s inf:1s"       2>/dev/null); q "bandsparse rejects a zero keep-period" 1 $?
(bandsparse "0s:3s inf:1h"       2>/dev/null); q "bandsparse rejects a zero max-age" 1 $?

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
# epoch2stamp: a wall-time epoch back to the wall-clock digits it was made
# from, ie name2epoch's inverse on the timestamp part. Same gdate -u oracle,
# since both ends live in local-wall-time space.
#-------------------------------------------------------------------------------

ep=$(echo "s2026-07-23-THU-15-55-33-d1.jpg" | name2epoch | cut -d' ' -f1)
q "epoch2stamp inverts name2epoch" "2026-07-23 15:55:33" "$(epoch2stamp "$ep")"
q "epoch2stamp at the epoch"       "1970-01-01 00:00:00" "$(epoch2stamp 0)"

#-------------------------------------------------------------------------------
# cullwalk: the anchor walk. Bands "100s:10s inf:100s", now=10000.
# Files at ages 1100,950,890,600,550,505,150,50,45,40,5. Nothing is deleted
# for age (there is no horizon; the oldest screenshot in particular is
# immortal, so the history-span number stays honest). The one rule: delete a
# file iff its surviving neighbors end up within one target gap -- the
# README's sliding-window criterion. Hand-walked: age-550 dies (its
# neighbors close to 9495-9400 = 95 <= 100) and age-45 dies (its neighbors
# close to 9960-9950 = 10 <= 10, the ideal gap exactly); everything else
# would gape wider than its target gap and so survives.
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
q "cullwalk deletions" "f-age550 f-age45" \
  "$(echo "$cullin" | cullwalk 10000 "100 inf" "10 100" | tr '\n' ' ' | sed 's/ $//')"
q "cullwalk keeps everything when n<=2" "" \
  "$(echo "9995 f-solo" | cullwalk 10000 "100 inf" "10 100")"
# The boundary is <=: a deletion that leaves its neighbors exactly one
# target gap apart is safe (and ideal); one second wider is not.
q "cullwalk deletes onto a gap of exactly the target" "x-mid" \
  "$(printf '9800 x-a\n9850 x-mid\n9900 x-b\n' | cullwalk 10000 "100 inf" "10 100")"
q "cullwalk keeps when the gap would exceed the target" "" \
  "$(printf '9800 y-a\n9850 y-mid\n9901 y-b\n' | cullwalk 10000 "100 inf" "10 100")"
q "cullwalk keeps ancient files, thinned by the last band" "" \
  "$(printf '5000 h-age5000\n9990 h-age10\n9995 h-age5\n' | \
     cullwalk 10000 "100 inf" "10 100")"
(echo "9995 x" | cullwalk 10000 "100 1000" "10 100" >/dev/null 2>&1)
q "cullwalk dies on a finite last edge" 1 $?

#-------------------------------------------------------------------------------
# crumbstat: what the screenshots on disk actually cost, from "epoch name size"
# lines. Bands "100s:10s inf:100s", now=10000. Every file counts: there is no
# horizon and nothing is ever too old.
#   age   30, jpg of 500 + webp of 50        -> one moment caught mid-archival,
#                                               counting as raw AND archived
#   age   50, two jpgs  of 1000 + 2000 bytes -> one raw moment of 3000
#   age   40, one jpg   of 3000 bytes        -> one raw moment of 3000
#   age 1000, one webp  of 9999 bytes        -> one archived moment of 9999
#   age  500, two webps of  100 +  200 bytes -> one archived moment of 300
#   age  800, two webps of  300 +  400 bytes -> one archived moment of 700
#   age   60, one jpg   of 0 bytes           -> a dead capture (disk full or a
#                                              killed screencapture): invisible
#                                              everywhere, so both aggregations
#                                              and the page agree on membership
# Hand-computed: jpgb 6500/3 = 2166.67, webpb 11049/4 = 2762.25, span 1000
# (the oldest file), slots 100/10 + (1000-100)/100 = 19, and so occupancy
# 6 moments / 19 slots = 0.3158.
#-------------------------------------------------------------------------------

statin="9970 f-d1.jpg 500
9970 f-d1.webp 50
9940 g-d1.jpg 0
9950 a-d1.jpg 1000
9950 a-d2.jpg 2000
9960 b-d1.jpg 3000
9000 c-d1.webp 9999
9500 d-d1.webp 100
9500 d-d2.webp 200
9200 e-d1.webp 300
9200 e-d2.webp 400"
q "crumbstat measures jpgb, webpb, occupancy, span, moment counts" \
  "2167 2762 0.3158 1000 3 4" \
  "$(echo "$statin" | crumbstat 10000 "100 inf" "10 100")"

#-------------------------------------------------------------------------------
# crumbmoms: the same stream reduced to one "agesec jpgbytes webpbytes" line
# per moment, ages ascending, bytes summed across displays and split by
# format so the mid-archival moment carries both. crumbudget.sh exports these
# so the page can bucket today's actual bytes under any edges the reader
# types. Hand-derived from the statin fixture above.
#-------------------------------------------------------------------------------

q "crumbmoms emits per-moment ages and split bytes, oldest last" \
  "30 500 50|40 3000 0|50 3000 0|500 0 300|800 0 700|1000 0 9999" \
  "$(echo "$statin" | crumbmoms 10000 | paste -sd'|' -)"
(echo "9950 a-d1.webp 100" | crumbstat 10000 "100 inf" "10 100" >/dev/null 2>&1)
q "crumbstat rejects a directory with no raw jpgs" 1 $?
(echo "9950 a-d1.jpg 100" | crumbstat 10000 "100 inf" "10 100" >/dev/null 2>&1)
q "crumbstat rejects a directory with no archived webps" 1 $?
(: | crumbstat 10000 "100 inf" "10 100" >/dev/null 2>&1)
q "crumbstat rejects an empty directory" 1 $?
(echo "9950 a-d1.jpg 100" | crumbstat 10000 "100 1000" "10 100" >/dev/null 2>&1)
q "crumbstat dies on a finite last edge" 1 $?

#-------------------------------------------------------------------------------
# sweep.sh end to end. Bands "1m:5s inf:1m" in a temp dir -- no horizon, so
# nothing dies for age; the cull keeps everything here (all gaps exceed 1m)
# and dedupe does the deleting:
#   F red jpg aged ~500s   -> the oldest; crossed band 0: the first archive
#   E red jpg aged ~400s   -> identical to F's webp: deduped
#   A red jpg aged ~200s   -> ditto: deduped
#   B red jpg aged ~130s   -> ditto: deduped
#   C blue jpg aged ~90s   -> differs from F: archived to webp
#   D red jpg aged ~20s    -> still in band 0: untouched
# 64x64 images so a full-frame color change (4096 px) clears dedupethresh=1000.
#-------------------------------------------------------------------------------

tmpd=$(mktemp -d)
gd=/opt/homebrew/bin/gdate
mick=/opt/homebrew/bin/magick
$mick -size 64x64 xc:red  "$tmpd/red.jpg"
$mick -size 64x64 xc:blue "$tmpd/blue.jpg"
stamp() { $gd -d "$1 seconds ago" '+%Y-%m-%d-%a-%H-%M-%S' | tr a-z A-Z; }
F="s$(stamp 500)-d1.jpg"; cp "$tmpd/red.jpg"  "$tmpd/$F"
E="s$(stamp 400)-d1.jpg"; cp "$tmpd/red.jpg"  "$tmpd/$E"
A="s$(stamp 200)-d1.jpg"; cp "$tmpd/red.jpg"  "$tmpd/$A"
B="s$(stamp 130)-d1.jpg"; cp "$tmpd/red.jpg"  "$tmpd/$B"
C="s$(stamp  90)-d1.jpg"; cp "$tmpd/blue.jpg" "$tmpd/$C"
D="s$(stamp  20)-d1.jpg"; cp "$tmpd/red.jpg"  "$tmpd/$D"
rm "$tmpd/red.jpg" "$tmpd/blue.jpg"
cat > "$tmpd/conf" <<EOF
path="$tmpd"
bands="1m:5s inf:1m"
imgq=32
fuzz="4%"
dedupethresh=1000
EOF
SCRUMBSCONF="$tmpd/conf" ./sweep.sh >/dev/null 2>"$tmpd/err"
q "sweep exits 0" 0 $?
[[ -s "$tmpd/err" ]] && sed 's/^/  sweep stderr: /' "$tmpd/err"
q "sweep archives F, the oldest, to webp" "here" \
  "$([[ -e $tmpd/${F%.jpg}.webp ]] && echo here || echo gone)"
q "sweep dedupes E (same as F)"        "gone"    "$([[ -e $tmpd/$E ]] && echo here || echo gone)"
q "sweep dedupes A (same as F)"        "gone"    "$([[ -e $tmpd/$A ]] && echo here || echo gone)"
q "sweep dedupes B (same as F)"        "gone"    "$([[ -e $tmpd/$B ]] && echo here || echo gone)"
q "sweep archives C to webp"           "here"    "$([[ -e $tmpd/${C%.jpg}.webp ]] && echo here || echo gone)"
q "sweep removes C's jpg"              "gone"    "$([[ -e $tmpd/$C ]] && echo here || echo gone)"
q "sweep leaves D alone (band 0)"      "here"    "$([[ -e $tmpd/$D ]] && echo here || echo gone)"

# Sweep again: idempotent on the survivors (F.webp, C.webp, D.jpg).
SCRUMBSCONF="$tmpd/conf" ./sweep.sh >/dev/null 2>"$tmpd/err2"
q "a second sweep exits 0" 0 $?
[[ -s "$tmpd/err2" ]] && sed 's/^/  sweep stderr: /' "$tmpd/err2"
q "a second sweep deletes nothing" "3" \
  "$(ls "$tmpd" | grep -c '^s[0-9]')"

# A lone inf band would make the raw band itself inf, ie "never archive
# anything"; bandsparse refuses the conf before sweep does anything.
cat > "$tmpd/conf" <<EOF
path="$tmpd"
bands="inf:1m"
imgq=32
fuzz="4%"
dedupethresh=1000
EOF
(SCRUMBSCONF="$tmpd/conf" ./sweep.sh >/dev/null 2>&1)
q "sweep rejects a lone inf band" 1 $?
rm -rf "$tmpd"

#-------------------------------------------------------------------------------
# crumbloop end to end: run briefly with a temp conf; it should start cleanly
# and spawn a sweep right away, even when the machine is idle. No assertions
# on capture files since an idle machine legitimately skips captures.
#-------------------------------------------------------------------------------

tmpl=$(mktemp -d)
cat > "$tmpl/conf" <<EOF
path="$tmpl"
bands="1m:5s inf:1m"
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
# crumbudget.sh end to end, bands "1m:5s inf:1m" over a temp dir of stub files:
#   one moment aged ~20s, two jpgs of 1000 + 2000 bytes -> jpgb 3000
#   two moments aged ~100s and ~200s, one webp each of 500 and 700 -> webpb 600
# The measurements travel via a generated crumbudget.data.js beside the html,
# NOT via a url fragment: macOS `open` (Launch Services) strips #fragments and
# ?queries from file:// urls before the browser sees them. Replicata for that
# bug: run crumbudget.sh, expect the page to load with data, and instead Chrome
# showed "no bands in the url". So: copy the tool into the temp dir (the data
# file lands beside the html, and the real one shouldn't be clobbered by
# quals), stub `open` earlier on PATH, and check the data file's contents and
# that the fragment-free url reaches `open`. Occupancy and span depend on when
# the clock ticks during this run, so they're left to crumbstat's quals above.
#-------------------------------------------------------------------------------

tmpb=$(mktemp -d)
mkdir "$tmpb/bin"
printf '#!/bin/bash\necho "OPENED $1"\n' > "$tmpb/bin/open"
chmod +x "$tmpb/bin/open"
cp crumbudget.sh scrumblib.sh crumbudget.html "$tmpb/"
t20=$(stamp 20)   # one stamp for both displays, so they land on one moment
head -c 1000 /dev/zero > "$tmpb/s$t20-d1.jpg"
head -c 2000 /dev/zero > "$tmpb/s$t20-d2.jpg"
head -c  500 /dev/zero > "$tmpb/s$(stamp 100)-d1.webp"
head -c  700 /dev/zero > "$tmpb/s$(stamp 200)-d1.webp"
# Replicata for the in-flight-capture bug: screencapture writes ".sNAME.jpg"
# and renames it into place, so a capture in flight during a measurement
# matched the *.jpg glob and then either vanished before stat or reached
# name2epoch as an unparseable name -- either way killing the run. sweep.sh
# never had it; it lists by "^s[0-9]{4}-". Expectata: a dotfile is not ours,
# so it is neither measured nor fatal.
head -c 4000 /dev/zero > "$tmpb/.s$(stamp 10)-d1.jpg"
cat > "$tmpb/conf" <<EOF
path="$tmpb"
bands="1m:5s inf:1m"
EOF
out=$(SCRUMBSCONF="$tmpb/conf" PATH="$tmpb/bin:$PATH" "$tmpb/crumbudget.sh" 2>"$tmpb/err")
q "crumbudget exits 0" 0 $?
[[ -s "$tmpb/err" ]] && sed 's/^/  crumbudget stderr: /' "$tmpb/err"
q "crumbudget ignores an in-flight capture dotfile" "" "$(cat "$tmpb/err")"
data=$(cat "$tmpb/crumbudget.data.js" 2>/dev/null)
has() { [[ $2 == *"$1"* ]] && echo yes || echo no; }
q "crumbudget writes the bands line to the data file"  yes "$(has 'bands: "1m:5s inf:1m"' "$data")"
# The stamp says when the numbers were taken, so a reader can tell a fresh
# measurement from one the capture loop has since grown past. Its value moves
# with the clock, so the qual checks its shape, not its digits.
q "crumbudget stamps the measurement instant" 1 \
  "$(grep -cE 'when: "[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}"' \
     "$tmpb/crumbudget.data.js")"
q "crumbudget measures bytes per raw moment"           yes "$(has 'jpgb: 3000' "$data")"
q "crumbudget measures bytes per archived moment"      yes "$(has 'webpb: 600' "$data")"
q "crumbudget counts the moments behind each mean"     yes "$(has 'rawmom: 1, arcmom: 2' "$data")"
# The per-moment export: ages are clock-dependent here, so check the byte
# payloads of the three known moments and the field's presence.
q "crumbudget exports the raw moment"                  yes "$(has ', 3000, 0],' "$data")"
q "crumbudget exports both archived moments"           yes \
  "$([[ $data == *', 0, 500],'* && $data == *', 0, 700],'* ]] && echo yes || echo no)"
q "crumbudget opens the moms array"                    yes "$(has 'moms: [' "$data")"
q "crumbudget hands open a fragment-free url" "OPENED file://$tmpb/crumbudget.html" \
  "$(grep '^OPENED' <<< "$out")"
q "crumbudget.html loads the data file, not the url" 1 \
  "$(grep -c 'src="crumbudget.data.js"' "$tmpb/crumbudget.html")"
q "crumbudget.html no longer reads location.hash" 0 \
  "$(grep -c 'location.hash' "$tmpb/crumbudget.html")"
rm -rf "$tmpb"
#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------
# crumbudget.html redesign: the conf line is the one input, editable directly at
# the top, with its implications rendered below -- no per-band widgets, no copy
# button. And the age bands wear an ordinal one-hue ramp (ordered data takes one
# hue in monotone lightness steps, here goldenrod via oklch()), not hatches.
#-------------------------------------------------------------------------------

q "the bands line is an editable input"    1 "$(grep -c 'id="bandsline"' crumbudget.html)"

# Now-vs-projected: two bar tracks under one limit tick, and the table's
# sacred Space header splits into On disk and Projected subcolumns. The limit
# line doubles as the budget slider. And the age bands wear a rainbow -- the
# owner's call, overriding the one-hue ordinal default: hue order carries the
# age order, a two-tier lightness zigzag keeps neighbors apart under
# colorblindness, and the palette is validated at every band count.
q "the page has an on-disk track"          1 "$(grep -c 'id="nowtrack"' crumbudget.html)"
q "the page has a projected track"         1 "$(grep -c 'id="projtrack"' crumbudget.html)"
q "the single-track id is gone"            0 "$(grep -c 'id="track"' crumbudget.html)"
q "Space spans the two byte columns"       1 "$(grep -c 'colspan="2">Space<' crumbudget.html)"
q "Moments splits the same way"            1 "$(grep -c 'colspan="2">Moments<' crumbudget.html)"
q "the total row has an on-disk cell"      1 "$(grep -c 'id="totnow"' crumbudget.html)"
q "the total row counts on-disk moments"   1 "$(grep -c 'id="totmomnow"' crumbudget.html)"
q "the measured panel is stamped"          1 "$(grep -c 'id="f-when"' crumbudget.html)"
q "the limit line is draggable"            1 "$(grep -c 'pointerdown' crumbudget.html)"
q "the bands wear the rainbow, not goldenrod" 0 "$(grep -c ' 83)' crumbudget.html)"
q "per-band period widgets are gone"       0 \
  "$(grep -cE 'className = "per"|input\.per' crumbudget.html)"
q "the copy button is gone"                0 "$(grep -c 'id="copy"' crumbudget.html)"
q "bands are colored by an oklch ramp"     yes \
  "$([[ $(grep -c 'oklch(' crumbudget.html) -gt 0 ]] && echo yes || echo no)"
q "the hatch fills are gone"               0 \
  "$(grep -c 'repeating-linear-gradient(45deg' crumbudget.html)"

# crumbudget.html typography, as a spec rather than a matter of taste:
#   - sizes in rem, so a reader who raises the browser's font size gets bigger
#     text (px would ignore that; see WCAG 2.2 SC 1.4.4)
#   - nothing below 1rem, ie below the 16px browser default
#   - line-height at least 1.5, the figure WCAG 2.2 SC 1.4.12 requires content
#     to survive
#-------------------------------------------------------------------------------

q "crumbudget.html sizes text in rem, never px" 0 \
  "$(grep -cE '(font|font-size): *[0-9.]+px' crumbudget.html)"
minrem=$(grep -oE '(font|font-size): *[0-9.]+rem' crumbudget.html | \
         grep -oE '[0-9.]+' | sort -g | head -1)
q "no text in crumbudget.html is smaller than 1rem" yes \
  "$(awk -v m="$minrem" 'BEGIN { print (m >= 1) ? "yes" : "no" }')"
minlh=$(grep -oE 'font: *[0-9.]+rem/[0-9.]+' crumbudget.html | \
        sed 's|.*/||' | sort -g | head -1)
q "every line-height in crumbudget.html is at least 1.5" yes \
  "$(awk -v m="$minlh" 'BEGIN { print (m >= 1.5) ? "yes" : "no" }')"

#-------------------------------------------------------------------------------

echo
if [[ $fails -eq 0 ]]; then echo "ALL QUALS GREEN"
else echo "$fails QUAL(S) RED"; exit 1; fi
