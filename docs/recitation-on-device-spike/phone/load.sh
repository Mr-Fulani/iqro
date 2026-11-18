#!/bin/sh
A="adb -s 91aedea7"
OUT=$(dirname "$0")/load.txt
PID=$($A shell pidof forum.iqro.app.test)
echo "pid $PID" > $OUT
sample() { echo "--- $1 $(date +%H:%M:%S)" >> $OUT; $A shell "dumpsys battery | grep -E 'temperature|level|AC powered|USB powered'" >> $OUT; $A shell "top -b -n 1 -p $PID | tail -2" >> $OUT; $A shell "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -3 | tr '\n' ' '" >> $OUT; echo >> $OUT; }
sample before
for i in 1 2 3 4; do $A shell input swipe 540 700 540 2000 200; done
$A shell input tap 863 156
for m in 1 2 3 4 5 6 7 8 9 10; do sleep 60; sample "minute $m"; done
$A shell input tap 863 156
sleep 60; sample "one minute after"
touch $(dirname "$0")/load.done
