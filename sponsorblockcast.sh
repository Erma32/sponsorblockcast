#!/bin/sh

SBCPOLLINTERVAL="${SBCPOLLINTERVAL:-30}"
SBCSCANINTERVAL="${SCANINTERVAL:-300}"
SBCDIR="${SBCDIR:-/tmp/sponsorblockcast}"
SBCCATEGORIES="${SBCCATEGORIES:-sponsor}"

# Format categories for curl by quoting words, replacing spaces with commas and surrounding with escaped brackets
categories="\\["$(echo "$SBCCATEGORIES" | sed 's/[^ ]\+/"&"/g;s/\s/,/g')"\\]"

[ -e "$SBCDIR" ] && rm -r "$SBCDIR"
mkdir "$SBCDIR" || exit
cd    "$SBCDIR" || exit

getSegments () {
  id=$1
  if [ ! -f "$id".segments ]
  then
    curl -fs "https://sponsor.ajay.app/api/skipSegments?videoID=$id&categories=$categories" |\
    jq -r '.[] | (.segment|join(" ")) + " " + .category' > "$id.segments"
  fi
}

check () {
  uuid=$1
  status=$(go-chromecast status -u "$uuid")
  state=$(echo "$status" | grep -oP '\(\K[^\)]+')
  [ "$state" != "PLAYING" ] && return
  videoId=$(echo "$status" | grep -oP '\[\K[^\]]+')
  echo Chromecast is "$state"
  getSegments "$videoId"
  progress=$(echo "$status" | grep -oP 'remaining=\K[^s]+')
  while read -r start end category; do
    if [ "$(echo "($progress > $start) && ($progress < ($end - 5))" | bc)" -eq 1 ]
    then
      echo "Skipping $category from $start -> $end"
      go-chromecast -u "$uuid" seek-to "$end"
    else
      delta=$(echo "$start - $progress" | bc)
      echo delta="$delta"
      if [ "$(echo "($delta < $maxSleepTime) && ($delta > 0)" | bc)" -eq 1 ]
      then
        maxSleepTime=$(echo "$delta / 1" | bc)
      fi
    fi
  done < "$videoId.segments"
}

listChromecasts() {
  go-chromecast ls | while read -r line; do
    echo "$line" | grep -oP 'uuid="\K[^"]+'
  done
}

scanChromecasts() {
  currentTime=$(date +%s)
  if [ -z "$lastScan" ] || [ "$lastScan" -lt "$((currentTime - SBCSCANINTERVAL))" ]
  then
    listChromecasts > devices
    lastScan=$currentTime
  fi
}

while :
do
  scanChromecasts
  maxSleepTime=$SBCPOLLINTERVAL
  while read -r uuid; do
    echo checking "$uuid"
    check "$uuid"
  done < devices
  echo sleeping "$maxSleepTime" seconds
  sleep "$maxSleepTime"
done

