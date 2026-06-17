#!/bin/sh
# Split-image CAPTCHA — hardened against bot attacks.
#
# Security layers:
#   1. Three digit-pair segments shuffled into random visual positions.
#   2. Colored dots encode reading order; dot colors shuffled each CAPTCHA.
#   3. Dot colors are jittered ±20 RGB per channel — human eye reads them
#      as red/green/blue but fixed-color-threshold detection fails.
#   4. Digit pairs rendered in random saturated colors (no two the same).
#   5. Digit horizontal position randomized across a wider range.
#   6. Wave parameters wider range — harder to train a specific inverter.
#   7. Two random arcs pass through the digit area per segment — disrupts
#      OCR character segmentation more than straight lines or uniform noise.
#   8. Header strip gets light noise + mild wave — dot-color reading from
#      the header is no longer a clean color-threshold operation.

INPUT=$1
[ -z "$INPUT" ] && exit 1

P1=$(echo "$INPUT" | cut -c1-2)
P2=$(echo "$INPUT" | cut -c3-4)
P3=$(echo "$INPUT" | cut -c5-6)

for n in $(od -A n -t u2 -N 256 /dev/urandom); do RL="$RL$n "; done
get_random() { R=${RL%% *}; RL=${RL#* }; }

# Shuffle digit pairs
DA="$P1"; DB="$P2"; DC="$P3"
IA=1; IB=2; IC=3

get_random; S1=$((R % 3))
case $S1 in
    0) TMP="$DA"; DA="$DB"; DB="$TMP"; TMP=$IA; IA=$IB; IB=$TMP ;;
    1) TMP="$DA"; DA="$DC"; DC="$TMP"; TMP=$IA; IA=$IC; IC=$TMP ;;
esac
get_random; S2=$((R % 2))
case $S2 in
    0) TMP="$DB"; DB="$DC"; DC="$TMP"; TMP=$IB; IB=$IC; IC=$TMP ;;
esac

# Shuffle which color encodes "first / second / third"
# Base colors: clearly red / green / blue to human eye.
# Jitter ±20 per channel so color-threshold bots can't rely on fixed values.
get_random; RJ1=$((R % 21 - 10)); get_random; RJ2=$((R % 21 - 10)); get_random; RJ3=$((R % 21 - 10))
get_random; GJ1=$((R % 21 - 10)); get_random; GJ2=$((R % 21 - 10)); get_random; GJ3=$((R % 21 - 10))
get_random; BJ1=$((R % 21 - 10)); get_random; BJ2=$((R % 21 - 10)); get_random; BJ3=$((R % 21 - 10))

clamp() { v=$1; [ $v -lt 0 ] && v=0; [ $v -gt 255 ] && v=255; echo $v; }

# Red base: (210,40,40), Green base: (40,160,60), Blue base: (50,90,210)
CR="rgb($(clamp $((210+RJ1))),$(clamp $((40+RJ2))),$(clamp $((40+RJ3))))"
CG="rgb($(clamp $((40+GJ1))),$(clamp $((160+GJ2))),$(clamp $((60+GJ3))))"
CB="rgb($(clamp $((50+BJ1))),$(clamp $((90+BJ2))),$(clamp $((210+BJ3))))"

COLOR1="$CR"; COLOR2="$CG"; COLOR3="$CB"
get_random; CS1=$((R % 3))
case $CS1 in
    0) TMP="$COLOR1"; COLOR1="$COLOR2"; COLOR2="$TMP" ;;
    1) TMP="$COLOR1"; COLOR1="$COLOR3"; COLOR3="$TMP" ;;
esac
get_random; CS2=$((R % 2))
case $CS2 in
    0) TMP="$COLOR2"; COLOR2="$COLOR3"; COLOR3="$TMP" ;;
esac

# Assign dot colors to visual slots based on their original position label
eval "DOT_A=\$COLOR${IA}"
eval "DOT_B=\$COLOR${IB}"
eval "DOT_C=\$COLOR${IC}"

# Legend reads in P1→P2→P3 order
LEGEND_DOT1="$COLOR1"
LEGEND_DOT2="$COLOR2"
LEGEND_DOT3="$COLOR3"

# Digit text colors (no two the same)
DPAL="rgb(150,20,20) rgb(20,100,30) rgb(20,40,150) rgb(130,30,140) rgb(20,110,110) rgb(150,75,10) rgb(90,30,110)"

pick_digit_color() {
    used1="${1:-NONE}"; used2="${2:-NONE}"
    attempts=0
    while true; do
        get_random; idx=$((R % 7))
        set -- $DPAL
        eval "candidate=\${$((idx + 1))}"
        if [ "$candidate" != "$used1" ] && [ "$candidate" != "$used2" ]; then
            echo "$candidate"; return
        fi
        attempts=$((attempts + 1))
        [ $attempts -gt 20 ] && { echo "$candidate"; return; }
    done
}

DC_A=$(pick_digit_color)
DC_B=$(pick_digit_color "$DC_A")
DC_C=$(pick_digit_color "$DC_A" "$DC_B")

# Image generation
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

gen_img() {
    text="$1"; dotcolor="$2"; digit_color="$3"; out="$4"

    # Wave parameters — wider range than before so a trained inverter fails
    get_random; WA=$((2 + R % 5));    get_random; WL=$((45 + R % 35))
    get_random; WA2=$((1 + R % 4));   get_random; WL2=$((50 + R % 35))
    get_random; ROT=$(( (R % 22) - 11 ))
    get_random; ROLL=$((R % 12))
    get_random; BGR=$((215 + R % 40)); get_random; BGG=$((215 + R % 40)); get_random; BGB=$((215 + R % 40))

    # Noise-line colors
    get_random; C1R=$((120+R%135)); get_random; C1G=$((R%80));       get_random; C1B=$((R%80))
    get_random; C2R=$((R%80));      get_random; C2G=$((120+R%135));  get_random; C2B=$((R%80))
    get_random; C3R=$((R%80));      get_random; C3G=$((R%80));       get_random; C3B=$((120+R%135))
    get_random; C4R=$((120+R%135)); get_random; C4G=$((R%80));       get_random; C4B=$((120+R%135))
    get_random; C5R=$((R%80));      get_random; C5G=$((120+R%135));  get_random; C5B=$((120+R%135))
    get_random; C6R=$((120+R%135)); get_random; C6G=$((120+R%135));  get_random; C6B=$((R%80))

    # Straight interference lines
    get_random; L1X1=$((R%15)); get_random; L1Y1=$((R%65)); get_random; L1X2=$((75+R%20)); get_random; L1Y2=$((R%65))
    get_random; L2X1=$((R%15)); get_random; L2Y1=$((R%65)); get_random; L2X2=$((75+R%20)); get_random; L2Y2=$((R%65))
    get_random; L3X1=$((R%15)); get_random; L3Y1=$((R%65)); get_random; L3X2=$((75+R%20)); get_random; L3Y2=$((R%65))
    get_random; L4X1=$((R%15)); get_random; L4Y1=$((R%65)); get_random; L4X2=$((75+R%20)); get_random; L4Y2=$((R%65))
    get_random; L5X1=$((R%15)); get_random; L5Y1=$((R%65)); get_random; L5X2=$((75+R%20)); get_random; L5Y2=$((R%65))
    get_random; L6X1=$((R%15)); get_random; L6Y1=$((R%65)); get_random; L6X2=$((75+R%20)); get_random; L6Y2=$((R%65))

    get_random; LW1=$((3+R%4)); get_random; LWL1=$((20+R%15))
    get_random; LW2=$((3+R%4)); get_random; LWL2=$((20+R%15))

    # Dot jitter
    get_random; DOT_DX=$((R%4)); get_random; DOT_DY=$((R%4))

    # Two random arcs through the digit area (center ~45,40)
    # Arc center randomized near the digit, radius 20–45, start/sweep angles random.
    get_random; ARC1_CX=$((30+R%40)); get_random; ARC1_CY=$((20+R%30))
    get_random; ARC1_R=$((20+R%26))
    get_random; ARC1_SA=$((R%360)); get_random; ARC1_EA=$(( (ARC1_SA + 80 + R%120) % 360 ))
    get_random; AR1=$((R%80)); get_random; AG1=$((R%80)); get_random; AB1=$((80+R%100))

    get_random; ARC2_CX=$((20+R%60)); get_random; ARC2_CY=$((25+R%35))
    get_random; ARC2_R=$((15+R%30))
    get_random; ARC2_SA=$((R%360)); get_random; ARC2_EA=$(( (ARC2_SA + 80 + R%120) % 360 ))
    get_random; AR2=$((80+R%100)); get_random; AG2=$((R%80)); get_random; AB2=$((R%80))

    # Digit horizontal position: wider range (15–45 instead of fixed 30)
    get_random; DIGIT_X=$((15+R%31))

    /usr/bin/convert -size 100x80 "xc:rgb(${BGR},${BGG},${BGB})" \
        -stroke "rgb(${C1R},${C1G},${C1B})" -strokewidth 2 -draw "line ${L1X1},${L1Y1} ${L1X2},${L1Y2}" \
        -stroke "rgb(${C2R},${C2G},${C2B})" -strokewidth 1 -draw "line ${L2X1},${L2Y1} ${L2X2},${L2Y2}" \
        -stroke "rgb(${C3R},${C3G},${C3B})" -strokewidth 2 -draw "line ${L3X1},${L3Y1} ${L3X2},${L3Y2}" \
        -stroke "rgb(${C4R},${C4G},${C4B})" -strokewidth 1 -draw "line ${L4X1},${L4Y1} ${L4X2},${L4Y2}" \
        -stroke "rgb(${C5R},${C5G},${C5B})" -strokewidth 2 -draw "line ${L5X1},${L5Y1} ${L5X2},${L5Y2}" \
        -stroke "rgb(${C6R},${C6G},${C6B})" -strokewidth 1 -draw "line ${L6X1},${L6Y1} ${L6X2},${L6Y2}" \
        -wave "${LW1}x${LWL1}" -wave "${LW2}x${LWL2}" \
        +noise Impulse \
        -fill none -stroke "rgb(${AR1},${AG1},${AB1})" -strokewidth 2 \
        -draw "arc $((ARC1_CX-ARC1_R)),$((ARC1_CY-ARC1_R)) $((ARC1_CX+ARC1_R)),$((ARC1_CY+ARC1_R)) ${ARC1_SA},${ARC1_EA}" \
        -stroke "rgb(${AR2},${AG2},${AB2})" -strokewidth 2 \
        -draw "arc $((ARC2_CX-ARC2_R)),$((ARC2_CY-ARC2_R)) $((ARC2_CX+ARC2_R)),$((ARC2_CY+ARC2_R)) ${ARC2_SA},${ARC2_EA}" \
        -fill none -stroke "${digit_color}" -strokewidth 2 -pointsize 38 \
        -gravity NorthWest -annotate "${ROT}x${ROT}+${DIGIT_X}+45" "$text" \
        -fill "${dotcolor}" -stroke none \
        -draw "circle $((10+DOT_DX)),$((12+DOT_DY)) $((10+DOT_DX)),$((5+DOT_DY))" \
        -roll "+${ROLL}+0" \
        -wave "${WA}x${WL}" \
        -roll "-${ROLL}+0" \
        -wave "${WA2}x${WL2}" \
        -crop 100x72+0+0 +repage \
        -background white -flatten \
        -quality 90 -depth 8 "${out}"
}

gen_img "$DA" "$DOT_A" "$DC_A" "$TMPDIR/img1.png"
gen_img "$DB" "$DOT_B" "$DC_B" "$TMPDIR/img2.png"
gen_img "$DC" "$DOT_C" "$DC_C" "$TMPDIR/img3.png"

# Header legend with light noise + mild wave to disrupt color-threshold
# Humans read dots by color appearance (still clearly red/green/blue).
# Bots relying on pixel-exact color detection or clean circular blobs will fail.
get_random; HWA=$((1+R%2)); get_random; HWLEN=$((60+R%20))
/usr/bin/convert -size 300x22 "xc:rgb(245,245,245)" \
    -fill "rgb(40,40,40)" -stroke none -pointsize 11 -font DejaVu-Sans \
    -gravity NorthWest -annotate "+5+5" "Enter digits in order:" \
    -fill "${LEGEND_DOT1}" -stroke none -draw "circle 158,11 158,5" \
    -fill "rgb(40,40,40)" -stroke none -pointsize 12 -font DejaVu-Sans-Bold \
    -gravity NorthWest -annotate "+172+4" "→" \
    -fill "${LEGEND_DOT2}" -stroke none -draw "circle 200,11 200,5" \
    -fill "rgb(40,40,40)" -stroke none -pointsize 12 -font DejaVu-Sans-Bold \
    -gravity NorthWest -annotate "+218+4" "→" \
    -fill "${LEGEND_DOT3}" -stroke none -draw "circle 248,11 248,5" \
    +noise Impulse \
    -wave "${HWA}x${HWLEN}" \
    -background "rgb(245,245,245)" -flatten \
    "$TMPDIR/header.png"

# Composite
/usr/bin/convert \
    "$TMPDIR/header.png" \
    \( "$TMPDIR/img1.png" "$TMPDIR/img2.png" "$TMPDIR/img3.png" +append \) \
    -append \
    -quality 90 -depth 8 png:-
