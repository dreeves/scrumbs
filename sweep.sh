#!/bin/bash
# By Daniel Reeves. See https://github.com/dreeves/scrumbs
# Compress and cull redundant screenshots

# Maybe for starters I could just make a compress.sh that replaces all the PNGs 
# with WEBPs, plus cull.sh that applies the algorithm that reduces the frequency
# as a function of age. Or, simpler, something like this to just remove anything
# too old:
# find . -mtime +12h -iname "*.png" -delete
# Then I could decide later whether to run that in a loop or not.

#-------------------------------------------------------------------------------
# Settings and Paths -----------------------------------------------------------
#-------------------------------------------------------------------------------

path="/Users/dreeves/scrumbs2"     # where all the screenshots live    [EDIT ME]
imgq=32                            # image quality; lower yields smaller files
fuzz="4%"                          # fuzz factor for comparing images
mick="/opt/homebrew/bin/magick"    # ImageMagick can compress and compare images

#-------------------------------------------------------------------------------
# Utility / Helper Functions ---------------------------------------------------
#-------------------------------------------------------------------------------

# Generate a placeholder image for a display if the image file doesn't exist
# See also init.sh which uses a nice lime green (#7FFF00) background.
genpim() {
  local -r file=$1
  local -a args=(-size 80x60 -background cyan -gravity Center)
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
