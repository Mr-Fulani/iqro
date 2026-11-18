#!/bin/sh
# live.sh <name> <wav>: mic on (model), play the wav from the Mac's speakers, mic off, keep the phone's sound and log
S=$(dirname "$0")/..
A="adb -s 91aedea7"
for i in 1 2 3 4; do $A shell input swipe 540 700 540 2000 200; done
sleep 1
T0=$($A shell date +%s.%N | cut -c1-14)
$A shell input tap 863 156
sleep 4
afplay "$2"
sleep 4
$A shell input tap 863 156
sleep 2
$A logcat -d -v epoch -T $T0 2>/dev/null | grep -E "IQRO model|E flutter" | sed 's/ *\([0-9.]*\) .*IQRO model /\1 /' > $S/live/$1.log
$A pull /storage/emulated/0/Android/data/forum.iqro.app.test/files/recitation.pcm $S/live/$1.pcm >/dev/null 2>&1
grep -c " step " $S/live/$1.log; grep -cE " place .*wrong=false" $S/live/$1.log; grep -E "wrong=true|tajweed [0-9]|E flutter" $S/live/$1.log | head -5
