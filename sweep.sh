#!/bin/bash
# By Daniel Reeves. See https://github.com/dreeves/scrumbs
# Compress and cull redundant screenshots
#
# Three passes per display, in the order that shrinks the work for the next:
#   1. Cull: thin screenshots per the age bands in scrumbs.conf, judging
#      strictly by the timestamp in the filename (mtimes lie once we start
#      recompressing). The last band's max-age is the horizon; anything
#      older is deleted.
#   2. Dedup: a jpg that has aged out of the raw band and matches the newest
#      archived image (within dedupethresh pixels at the configured fuzz)
#      is deleted. A missing timestamp then *means* "unchanged since the
#      previous screenshot" -- there are no placeholder files.
#   3. Compress: surviving jpgs beyond the raw band become webp. The .webp
#      extension is what marks a file as fully processed, so the sweep needs
#      no state between runs.

#-------------------------------------------------------------------------------
# Settings and Paths -----------------------------------------------------------
#-------------------------------------------------------------------------------

srcdir=$(cd "$(dirname "$0")" && pwd)
. "$srcdir/scrumblib.sh"
. "${SCRUMBSCONF:-$srcdir/scrumbs.conf}"  # path, bands, imgq, fuzz, dedupethresh

mick="/opt/homebrew/bin/magick"    # ImageMagick can compress and compare images

#-------------------------------------------------------------------------------
# Utility / Helper Functions ---------------------------------------------------
#-------------------------------------------------------------------------------

# Image diff in absolute pixels
imgdif() {
  local -r img1=$1
  local -r img2=$2
  local -a args=(-metric AE -fuzz "$fuzz")
  local out
  out=$(/opt/homebrew/bin/compare "${args[@]}" "$img1" "$img2" null: 2>&1)
  # compare prints just the metric, eg "1925 (0.000249)" or "1.07e+06 (16.3)";
  # anything wordier is an error and int()ing it would yield a bogus 0, aka
  # "identical", so die instead
  [[ $out =~ ^[0-9][0-9.e+]*( \([0-9.e+-]+\))?$ ]] || \
    die "compare failed on $img1 vs $img2: $out"
  echo "$out" | \
    awk '{print int($1)}' # the awk/int handles conversion from sci. notation
}

#-------------------------------------------------------------------------------
# Main -------------------------------------------------------------------------
#-------------------------------------------------------------------------------

[[ -d $path ]] || die "no such directory: $path"
bandsparse "$bands"
edge0=${edges%% *}                 # raw band boundary in seconds: jpgs older
                                   # than this get deduped/compressed; finite
                                   # by construction (bandsparse wants >= 2
                                   # bands and lets only the last be inf)
now=$(localnow)

# Allow only one sweep at a time. (A stale lock after a crash needs removing
# by hand -- better that than two sweeps racing.)
/bin/mkdir "$path/.sweeplock" 2>/dev/null || \
  die "sweep lock held: $path/.sweeplock"
trap '/bin/rmdir "$path/.sweeplock"' EXIT

# The s prefix followed by a year marks a file as ours; anything else in the
# directory (debug logs etc) is none of our business. Validate every claimed
# filename up front -- one that doesn't parse kills the run, courtesy of
# name2epoch -- so the passes below can trust them all.
(cd "$path" && ls | grep -- '^s[0-9][0-9][0-9][0-9]-' | name2epoch >/dev/null) \
  || exit 1

# One display's screenshots, oldest first (dates lead the filenames, so
# lexical order is chronological). Subshell body so the cd doesn't stick.
lsdisp() (
  cd "$path" && ls | grep -E -- "^s[0-9]{4}-.*-${1}\.(jpg|webp)$"
)

# Each display is its own timeline, swept independently
for d in $(cd "$path" && ls | \
           /usr/bin/sed -nE 's/^s[0-9]{4}-.*-(d[0-9]+)\.(jpg|webp)$/\1/p' | \
           sort -u); do

  # Pass 1: cull. Filenames and arithmetic only -- no image ops.
  ncull=0
  while read -r f; do
    [[ -n $f ]] || continue
    /bin/rm -- "$path/$f"
    ncull=$((ncull+1))
  done < <(lsdisp "$d" | name2epoch | cullwalk "$now" "$edges" "$pers")

  # Passes 2+3: walk the survivors oldest first. A webp is already archived
  # and just becomes ref, the newest archived image. A jpg past the raw band
  # is either a duplicate of ref (delete it; the gap in the timeline is the
  # record that nothing changed) or a keeper (compress to webp).
  ndedup=0; narch=0; ref=""
  while read -r ep f; do
    if [[ $f == *.webp ]]; then ref=$f; continue; fi
    (( now - ep >= edge0 )) || continue    # still in the raw band
    if [[ -n $ref ]]; then
      ae=$(imgdif "$path/$f" "$path/$ref") || exit 1
    else
      ae=$dedupethresh   # nothing archived yet, so nothing to be a dup of
    fi
    if (( ae < dedupethresh )); then
      /bin/rm -- "$path/$f"
      ndedup=$((ndedup+1))
    else
      $mick "$path/$f" -quality "$imgq" "$path/${f%.jpg}.webp" \
        || die "magick failed on $f"
      /bin/rm -- "$path/$f"
      ref="${f%.jpg}.webp"
      narch=$((narch+1))
    fi
  done < <(lsdisp "$d" | name2epoch)

  echo "$d: culled $ncull, deduped $ndedup, archived $narch"
done
