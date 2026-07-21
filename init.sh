#!/bin/bash
# Touch all possible `24*60*numscreens` files, if you don't want missing files 
# when the display is off.
# It's safe to run this any time -- it only touches files that don't exist. 
# And the only reason to bother is that it can be handy for treating the 
# screenshot timestamps as quantified-self data, like, "I've never been awake at
# 4am since I started running this on such-and-such date".
# (Also this only makes sense if crumbshot.sh never deletes, only overwrites, 
# existing screencap images.)

# This is currently janky and slow. For one thing, we should generate the
# placeholder image once and copy it to each missing file.

set -euo pipefail

path="$HOME/scrumbs"
smax=3 # or use numdisplays() below
mick="/opt/homebrew/bin/magick"    # ImageMagick can compress and compare images


# unDRY warning: copied from crumbshot.sh
# Query for the number of connected, online displays
numdisplays() {
  /usr/sbin/system_profiler SPDisplaysDataType | /usr/bin/grep -c 'Online: Yes'
  # NB: this has returned 0 once or twice; could be safer to add retries?
}

# unDRY warning: adapted from crumbshot.sh
# Generate a placeholder image if the file doesn't exist.
# Returns 0 iff it created the file; non-zero otherwise.
genpim() {
  local -r file=$1
  [[ -e "$file" ]] && return 1
  local -a args=(-size 80x60 -background '#7FFF00' -gravity center -fill black)
  local -r caption="(Screen never accessed)"
  "$mick" "${args[@]}" "caption:$caption" "$file"
  #/bin/cp $path/tmp2.webp "$file"
}

#smax=$(numdisplays)

numcreated=0
echo "Screens: $smax"

for ((h=0; h<24; h++)); do
  printf -v hh '%02d' "$h"
  for ((m=0; m<60; m++)); do
    printf -v mm '%02d' "$m"
    for ((d=1; d<=smax; d++)); do
      f="$path/scr${d}cap-${hh}-${mm}.webp"
      if [[ ! -e "$f" ]]; then
        if genpim "$f"; then
        ((numcreated++))
        fi
      fi
    done
  done
done

echo "Files created: $numcreated"