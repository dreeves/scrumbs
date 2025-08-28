#!/bin/bash
# Generate WebP files for a massive combination of ImageMagick settings.

# Compressing to webp seems better but here's a JPEG version for comparison:
#args="-blur 0x0.5 -strip -define jpeg:optimize-coding=on \
#                         -define jpeg:sampling-factor=1x1,1x1,1x1 -quality 20"
# magick $infile $args $outfile.jpg

# The lists of parameters to test. X means omit it altogether, use the default.
QUALITIES="$(seq 1 99)" # $(seq 1 20); range 1-100                             q
METHODS="X 6" # X 5 6; range 0-6 (default 4)                                   m
POSTERIZE_LEVELS="X" # 4 5 6 8 (2, 4, and 6 all look hideous)                  z
SNS_STRENGTHS="X" # range 0-100 (default 80); 0 rec'd for text                 s
FILTER_STRENGTHS="X" # range 0-100, typical 20-50; 0 rec'd for text            f
FILTER_SHARPNESS_LEVELS="X" # 0 4 6; range 0-6? but docs don't say           fsh
PREPROCESSINGS="X" # range 0-2; 0 rec'd for text                               p
SEGMENTS="X" # range 1-4; 2 rec'd for text                                     g
HINTS="X" # photo picture graph (default "default")                            h
PASSES="X" # 1-10 probably, but docs don't say                                pa
AUTO_FILTERS="X" # true false                                                 af
FILTER_TYPES="X" # range 0-1                                                  ft
YUV="X" # true/false or maybe 0-1? docs don't say                              y

# Max Width: Calculate the maximum string length of any value in a list
mw() {
  local maxw=0
  for val in "$@"; do [ ${#val} -gt $maxw ] && maxw=${#val}; done
  echo "$maxw"
}

# pad <string> <width> [pad_char] [dir]
# dir: -1 = left-pad (default), +1 = right-pad
pad() {
  (( $# >= 2 && $# <= 4 )) || { printf 'ERROR902'; return 1; } # wrong # of args
  local s=$1 w=$2 ch=${3:-' '} dir=${4:- -1}

  [[ $w =~ ^[0-9]+$ ]] || { printf 'ERROR903'; return 2; } # width a non-integer
  [[ $dir == -1 || $dir == +1 ]] || { printf 'ERROR904'; return 3; } # bad dir
  [[ ${#ch} -eq 1 ]] || { printf 'ERROR905'; return 4; } # pad char not 1 char

  local padlen=$(( w - ${#s} ))
  (( padlen <= 0 )) && { printf '%s' "$s"; return; } # no room for padding

  local pad
  printf -v pad '%*s' "$padlen" ''       # make padlen number of spaces
  [[ $ch != ' ' ]] && pad=${pad// /$ch}  # swap in the pad character

  (( dir == -1 )) && printf '%s' "$pad$s" || printf '%s' "$s$pad"
}

lpad(){ pad "$1" "$2" "${3:-0}" -1; } # default pad character is a zero
rpad(){ pad "$1" "$2" "${3:- }" +1; } # default pad character is a space

# Calculate total number of combinations
TOTAL_FILES=$(( $(echo $QUALITIES               | wc -w) * \
                $(echo $METHODS                 | wc -w) * \
                $(echo $POSTERIZE_LEVELS        | wc -w) * \
                $(echo $SNS_STRENGTHS           | wc -w) * \
                $(echo $FILTER_STRENGTHS        | wc -w) * \
                $(echo $FILTER_SHARPNESS_LEVELS | wc -w) * \
                $(echo $PREPROCESSINGS          | wc -w) * \
                $(echo $SEGMENTS                | wc -w) * \
                $(echo $HINTS                   | wc -w) * \
                $(echo $PASSES                  | wc -w) * \
                $(echo $AUTO_FILTERS            | wc -w) * \
                $(echo $FILTER_TYPES            | wc -w) * \
                $(echo $YUV                     | wc -w) ))

# -define webp:use-sharp-yuv=true

echo "Generating $TOTAL_FILES files..."

if [ -z "$1" ] || [ ! -f "$1" ]; then echo "Usage: $0 <input_image>"; exit 1; fi
INFILE="$1"

OUTDIR="samples"
[ -e "$OUTDIR" ] || { echo "Error: output directory $OUTDIR missing"; exit 1; }
echo "Input file: $INFILE"
echo "Outputting files to: $OUTDIR/"

COUNT=0

# This loop is way too nested to actually indent
for Q   in $QUALITIES;               do
for M   in $METHODS;                 do
for Z   in $POSTERIZE_LEVELS;        do
for S   in $SNS_STRENGTHS;           do
for F   in $FILTER_STRENGTHS;        do
for FSH in $FILTER_SHARPNESS_LEVELS; do
for P   in $PREPROCESSINGS;          do
for G   in $SEGMENTS;                do
for H   in $HINTS;                   do
for PA  in $PASSES;                  do
for AF  in $AUTO_FILTERS;            do
for FT  in $FILTER_TYPES;            do
for Y   in $YUV;                     do

((COUNT++))

FILENAME="\
q$(pad   "$Q"   "$(mw $QUALITIES)"               "0" -1)-\
m$(pad   "$M"   "$(mw $METHODS)"                 "0" -1)-\
z$(pad   "$Z"   "$(mw $POSTERIZE_LEVELS)"        "0" -1)-\
s$(pad   "$S"   "$(mw $SNS_STRENGTHS)"           "0" -1)-\
f$(pad   "$F"   "$(mw $FILTER_STRENGTHS)"        "0" -1)-\
fsh$(pad "$FSH" "$(mw $FILTER_SHARPNESS_LEVELS)" "0" -1)-\
p$(pad   "$P"   "$(mw $PREPROCESSINGS)"          "0" -1)-\
g$(pad   "$G"   "$(mw $SEGMENTS)"                "0" -1)-\
h$(pad   "$H"   "$(mw $HINTS)"                   "X" +1)-\
pa$(pad  "$PA"  "$(mw $PASSES)"                  "0" -1)-\
af$(pad  "$AF"  "$(mw $AUTO_FILTERS)"            "X" +1)-\
ft$(pad  "$FT"  "$(mw $FILTER_TYPES)"            "0" -1)-\
y$(pad   "$Y"   "$(mw $YUV)"                     "X" +1).webp"

OUTFILE="${OUTDIR}/${FILENAME}"

# echo "DEBUG $FILENAME"; exit 0 # for debugging

printf "%*s/%s: %s" ${#TOTAL_FILES} $COUNT $TOTAL_FILES $FILENAME
if [ -f "$OUTFILE" ]; then echo " EXISTS"; continue; fi # skip if already exists
printf "\n"

margs=()
if [ "$Q"   != "X" ]; then margs+=(-quality "$Q");                        fi
if [ "$M"   != "X" ]; then margs+=(-define "webp:method=$M");             fi
if [ "$Z"   != "X" ]; then margs+=(-posterize "$Z");                      fi
if [ "$S"   != "X" ]; then margs+=(-define "webp:sns-strength=$S");       fi
if [ "$F"   != "X" ]; then margs+=(-define "webp:filter-strength=$F");    fi
if [ "$FSH" != "X" ]; then margs+=(-define "webp:filter-sharpness=$FSH"); fi
if [ "$P"   != "X" ]; then margs+=(-define "webp:preprocessing=$P");      fi
if [ "$G"   != "X" ]; then margs+=(-define "webp:segments=$G");           fi
if [ "$H"   != "X" ]; then margs+=(-define "webp:image-hint=$H");         fi
if [ "$PA"  != "X" ]; then margs+=(-define "webp:pass=$PA");              fi
if [ "$AF"  != "X" ]; then margs+=(-define "webp:auto-filter=$AF");       fi
if [ "$FT"  != "X" ]; then margs+=(-define "webp:filter-type=$FT");       fi
if [ "$Y"   != "X" ]; then margs+=(-define "webp:use-sharp-yuv=$Y");      fi

magick "$INFILE" "${margs[@]}" "$OUTFILE"

done; done; done; done; done; done; done; done; done; done; done; done; done

echo "Done. Files generated: $COUNT/$TOTAL_FILES"