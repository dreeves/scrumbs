#!/bin/bash
# By Daniel Reeves. See https://github.com/dreeves/scrumbs
# Version of crumbshot that runs in a loop, no cron.

#-------------------------------------------------------------------------------
# Settings and Paths -----------------------------------------------------------
#-------------------------------------------------------------------------------

path="/Users/dreeves/scrumbs2"     # where all the screenshots live    [EDIT ME]
freq=5                             # technically period; seconds betw screencaps
scap="/usr/sbin/screencapture"     # standard macOS command-line screenshot tool
BIL=1000000000                     # a billion, 10^9, for nanoseconds conversion

#-------------------------------------------------------------------------------
# Utility / Helper Functions ---------------------------------------------------
#-------------------------------------------------------------------------------

# Query for the number of connected, online displays
numdisplays() {
  /usr/sbin/system_profiler SPDisplaysDataType | /usr/bin/grep -c 'Online: Yes'
  # NB: this has returned 0 once or twice; could be safer to add retries?
}

# Machine idle time in nanoseconds, ie how long since you touched keyboard/mouse
idletime() {
  local ns=$(/usr/sbin/ioreg -c IOHIDSystem 2>/dev/null | \
    /usr/bin/awk '/HIDIdleTime/{print $NF;exit}')
  # Very rarely we get an error ("ioreg: error: can't obtain class") so we just
  # default to zero in that case:
  echo "${ns:-0}"
}

# Take a number of nanoseconds and format it like 4h20m59s
nanoHMS() {
  local ns="$1"
  if ! [[ $ns =~ ^[0-9]+$    ]]; then echo "[ERROR: $ns NaN?]"; return 1; fi
  if   [[ $ns -lt       1000 ]]; then echo "${ns}ns";           return 0; fi
  if   [[ $ns -lt    1000000 ]]; then echo "$((ns/1000))us";    return 0; fi # µ
  if   [[ $ns -lt 1000000000 ]]; then echo "$((ns/1000000))ms"; return 0; fi
  awk -v ns="$ns" 'BEGIN{
    total_seconds = ns / 1e9;
    hours             = int(total_seconds / 3600);
    minutes           = int((total_seconds - hours*3600) / 60);
    remaining_seconds = total_seconds - hours*3600 - minutes*60;
    if (hours > 0)                { printf "%dh", hours; }
    if (minutes > 0 || hours > 0) { printf "%dm", minutes; }
    if (hours == 0)               { printf "%ds", remaining_seconds; }
    printf "\n";
  }'
}

# Compute how many nanoseconds to sleep so that we'll wake up exactly freq
# seconds after the start time (ini). Then log it to stdout and do the sleeping.
sleepytime() {
  local fin=$(/opt/homebrew/bin/gdate +%s%N)
  local dur=$((fin-ini))           # elapsed time so far, in nanoseconds
  local t=$((fns-dur))             # freq minus the ini->fin elapsed time so far
  (( t < BIL )) && t=$BIL          # sleep at least 1 second
  local s
  printf -v s '%d.%09d' $((t/BIL)) $((t%BIL))    # hack for non-integer division
  printf "sleeping %ss - %s = %s" "$freq" "$(nanoHMS $dur)" "$(nanoHMS $t)"
  /bin/sleep "$s"
  printf "\n"
}

#-------------------------------------------------------------------------------
# Main -------------------------------------------------------------------------
#-------------------------------------------------------------------------------

fns=$(awk -v f="$freq" 'BEGIN{printf "%.0f\n", f*1e9}')    # freq in nanoseconds
# To be safe we'd get the number of displays inside the loop, since it can
# change any time. But in practice it rarely does. Maybe it should recheck like
# every minute?
smax=$(numdisplays) 
[[ $smax -gt 0 ]] || { echo "ERROR: zero displays??"; exit 1; }

while(true); do #---------------------------------------------------------------

read -r ini mm ss < <(/opt/homebrew/bin/gdate '+%s%N %M %S')
timetag=$(printf -- "dow-hh-%s-%s" "$mm" "$ss")
echo -n "$timetag "
idle=$(idletime)
printf "%7s " "~$(nanoHMS $idle)"

if (( idle > fns )); then
  printf "idle over %ss => skipping screencaps. " "$freq"
  sleepytime
  continue;
fi

#smax=$(numdisplays)
#[[ $smax -gt 0 ]] || { echo "ERROR: zero displays??"; sleepytime; continue; }
printf "d%s " $smax

for ((i=1; i<=smax; i++)); do X[i]="$path/scd${i}-$timetag.png";  done

# Grab a screenshot for every monitor (up to 4 currently; add more to taste)
echo -n "S"
$scap -x -r -T0 ${X[@]}
echo -n ". "

sleepytime

done # end while(true) ---------------------------------------------------------

#-------------------------------------------------------------------------------
# Bad ideas go down here
#-------------------------------------------------------------------------------

# gdate +%s%N  # GNU date for nanoseconds
# %u for day-of-week where Monday=1, not sure if Sunday is 0 or 7
# %w also has Monday=1 and maybe Sunday is whatever %u isn't?

H=12; ref=$(mktemp); touch -t "$(date -v-"$H"H '+%Y%m%d%H%M.%S')" "$ref"; find . -type d -name . -prune -o \( -type f -name '*.png' ! -newer "$ref" -print \); rm -f "$ref"

H=12; ref=$(mktemp); touch -t "$(date -v-"$H"H '+%Y%m%d%H%M.%S')" "$ref"; find . -type d -name . -prune -o \( -type f -name '*.png' ! -newer "$ref" -print \); rm -f "$ref"
