#!/bin/bash
# By Daniel Reeves. See https://github.com/dreeves/scrumbs

#-------------------------------------------------------------------------------
# Settings and Paths -----------------------------------------------------------
#-------------------------------------------------------------------------------

path="/Users/dreeves/scrumbs"      # where all the screenshots live    [EDIT ME]
imgq=32                            # image quality; lower yields smaller files
fuzz="4%"                          # fuzz factor for comparing images
scap="/usr/sbin/screencapture"     # standard macOS command-line screenshot tool
mick="/opt/homebrew/bin/magick"    # ImageMagick can compress and compare images
freq=60                            # technically period; seconds betw screencaps

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
  echo $(/usr/sbin/ioreg -c IOHIDSystem | \
    /usr/bin/awk '/HIDIdleTime/{print $NF;exit}')
  # NB: Got this error once: "ioreg: error: can't obtain class". Add retries?
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

# Generate a placeholder image for a display if the image file doesn't exist
genpim() {
  local -r file=$1
  local -a args=(-size 80x60 -background '#7FFF00' -gravity Center)
  local -r caption="(Screen inaccessible)"
  [[ -e "$file" ]] || { "$mick" "${args[@]}" "caption:$caption" "$file"; }
}

# Image diff in absolute pixels 
imgdif() {
  local -r img1=$1
  local -r img2=$2
  local -a args=(-metric AE -fuzz "$fuzz")
  /opt/homebrew/bin/compare "${args[@]}" "$img1" "$img2" null: 2>&1 | \
    awk '{print int($1)}' # the awk/int handles conversion from sci. notation
}

#-------------------------------------------------------------------------------
# Main -------------------------------------------------------------------------
#-------------------------------------------------------------------------------

HM=$(/bin/date +%H-%M)   # eg "19-59" when it's 7:59pm
idle=$(idletime)         # machine idle time in nanoseconds

DBG=$path/debug.log  # maybe ditch this when everything is working

echo -n "$HM " >>$DBG
printf "%7s " "~$(nanoHMS $idle)" >>$DBG

smax=$(numdisplays)
[[ $smax -gt 0 ]] || { printf "ERROR01: no online displays?\n" >>$DBG; exit 1; }
printf "d%s " $smax >>$DBG

# Arrays for the temporary, latest/head, and archived/compressed image files
# (Note that it might be better to use mktemp for temp files)
for ((i=1; i<=smax; i++)); do T[i]="$path/scr${i}cap-TMP.png";  done # Temporary
for ((i=1; i<=smax; i++)); do H[i]="$path/scr${i}cap-HEAD.png"; done # Head
for ((i=1; i<=smax; i++)); do C[i]="$path/scr${i}cap-$HM.webp"; done # Compressd

# Initialize the heads w/ placeholders iff they don't already exist
for ((i=1; i<=smax; i++)); do genpim ${H[$i]}; done

# If we don't do this then we'll eventually have a fully 24 hours' worth:
#/bin/rm -f ${C[@]} # clean up previous captures -- optional

if (( idle > freq * 10**9 )); then
  printf "idle over ${freq}s => skipping screencaps\n" >>$DBG
  exit 0;
fi

# Grab a screenshot for every monitor (up to 4 currently; add more to taste)
echo -n "S" >>$DBG
$scap -x -r -T0 ${T[@]}
echo -n ". " >>$DBG

# Placeholders for any displays that failed to capture
for ((i=1; i<=smax; i++)); do genpim ${T[$i]}; done

# Get the image diffs, tmp vs head
echo -n "D" >>$DBG
for ((i=1; i<=smax; i++)); do D[i]=$(imgdif ${T[$i]} ${H[$i]}); done
echo -n ". " >>$DBG

printf "fuzz%3s " "$fuzz" >>$DBG
for ((i=1; i<=smax; i++)); do printf "%11s " "${D[i]}\\$i" >>$DBG; done

# For each display, if there's an image difference, do two things: 
# (1) copy tmp to head, and 
# (2) copy tmp to a compressed archive image for HH-MM. 
# If no image difference, do nothing. 
# Either way, blow away the tmp files before exit.
# For the compression, see gensamples.sh for picking the webp settings.
echo -n "C" >>$DBG
args="-quality $imgq"
for ((i=1; i<=smax; i++)); do
  if [ ${D[i]} -ne 0 ]; then 
    echo -n "c" >>$DBG
    /bin/cp ${T[$i]} ${H[$i]}
    echo -n "." >>$DBG
    $mick ${T[$i]} $args ${C[$i]}
    echo -n ";" >>$DBG
  fi
done
echo -n "." >>$DBG

/bin/rm -f -- "${T[@]}" # clean up the temp files

printf "\n" >>$DBG

#-------------------------------------------------------------------------------
# Bad ideas go down here
#-------------------------------------------------------------------------------

# Various attempts to check if the screensaver is active but none work via cron:
# Prereq:
# python3 -m pip install --user --break-system-packages pyobjc-framework-Quartz
#ss=$(/opt/homebrew/bin/python3 <<'PY'
#try:              # chunk of Python code to detect if the screensaver is active
#  import Quartz   # but it doesn't work via cron
#  d = Quartz.CGSessionCopyCurrentDictionary()
#  if not d: print('?')
#  elif d.get('CGSSessionScreenSaverIsActive',0): print('1')
#  else: print('0')
#except BaseException:
#  print('E')
#PY
#)
#ss=0
#/bin/ps -ax -o comm | /usr/bin/grep -qxF 'ScreenSaverEngine' && ss=1
#/usr/bin/pgrep -qx ScreenSaverEngine 2>/dev/null && ss=1

# Sandwich idea: What if the latest screencaps (newNcap) actually record their
# HH-MM as well and then (a) if the new screencap matches it we overwrite the 
# latest, and (b) if the new screencap differs, we retroactively move 
# newNcap-HM.jpg to scrNcap-HM.jpg. That way when there's a period of the screen
# not changing we get exactly two copies of what was on the screen during that
# period: one at the start and one at the end of the period.
# Verdict: What we're doing now is better. Just have one copy of the screenshot
# and only add a new one when it changes.

# Stable, cheap image signature (downscale+gray, strip metadata)
#sig() {
#  magick "$1" -alpha off -resize 64x64\! -colorspace Gray -depth 8 -strip \
#    -format '%#\n' info:
#}

# Identifying blank images isn't needed because (a) we just abort the crumbshot 
# if the machine is idle, and (b) if we do get a blank image, we'll only get it
# once, thanks to the part where we only store a new screenshot if it's
# different from the previous one.
#imid="/opt/homebrew/bin/identify"; # part of ImageMagick for IDing blank images
#isblank() {
#  [ -s "$1" ] || return 0            # missing/empty => treat as blank
#  local m
#  m=$($imid -quiet -format '%[max]\n' -- "$1" 2>/dev/null) || return 1
#  m=${m//[[:space:]]/}               # strip any stray whitespace
#  [ "$m" -eq 0 ]
#}

# Create the directory (not currently used; better to fail if it doesn't exist)
# /bin/mkdir -p "$path"

# Alternatively and less confusingly, we could just always start by deleting the
# current scrNcap-HH-MM file. Or even all screenshots more than 24 hours 
# old. If there's no screen image to fetch, the current HH:MM will just be 
# missing. That would also save diskspace. You'd only ever have screenshots for
# the fraction of the last 24 hours for which you were actually on your 
# computer. The deconfusion advantage is that sometimes when you're flipping 
# through screenshots and you hit a period where the computer was idle, it's 
# confusing to jump further back in time. On the other hand, it's very 
# occasionally useful to be able to recover things older than 24 hours.

#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------

# VERSION BELOW WORKED FINE FOR YEARS
# The only problem with it is generating blank screenshots or screenshots of the
# screensaver.

##!/bin/bash
# By dreev, documented at doc.dreev.es/screencap
#
#jq=20; # jpeg quality (20 seems always readable, 10 not always for small fonts)
#scap="/usr/sbin/screencapture";   # standard macOS screenshot tool
#mogr="/opt/homebrew/bin/mogrify"; # part of ImageMagick for transforming images
#path="/Users/dreeves/tmp/screenshots";  # where all the screenshots live
#t=$(/bin/date +%s)                    # current time as unixtime
#hm=$(/bin/date +%H-%M);            # eg "19-59" when it's 7:59pm
#
## get the number of connected, online displays (not needed currently) 
##n=`/usr/sbin/system_profiler SPDisplaysDataType | grep -c 'Online: Yes'`;
#
#f1="$path/screen1cap-$hm.jpg"
#f2="$path/screen2cap-$hm.jpg"
#f3="$path/screen3cap-$hm.jpg"
#
## grab a screenshot for every monitor (up to 3 currently; add more to taste)
#$scap -x -d -r -T0 -tjpg $f1 $f2 $f3
#
#/bin/sleep 1 # make sure the screencapture is done
#
#t1=$(/bin/date -r $f1 +%s)
#t2=$(/bin/date -r $f2 +%s)
#t3=$(/bin/date -r $f3 +%s)
#
## drastically reduce the file sizes (for the ones just now created)
#if [ $t1 -ge $t ] ; then $mogr -quality $jq $f1 &> /dev/null ; fi
#if [ $t2 -ge $t ] ; then $mogr -quality $jq $f2 &> /dev/null ; fi
#if [ $t3 -ge $t ] ; then $mogr -quality $jq $f3 &> /dev/null ; fi
