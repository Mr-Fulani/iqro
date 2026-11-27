#!/usr/bin/env bash
# Runs an integration test of the app on an iOS simulator, with a screen
# recording and screenshots (integration_test/README.md). Used by the
# "iOS simulators" and "App Store screenshots" workflows; run from
# clients/iqro_mobile.
#
#   ios/scripts/simulator_run.sh create "iPhone 17 Pro Max|iPhone 16 Pro Max"
#       Creates and boots a fresh simulator of the first device type that
#       exists, on the newest iOS, with a 9:41 status bar. Prints its id.
#
#   ios/scripts/simulator_run.sh test <id> <app> <test file> <output folder>
#       Installs the built Runner.app on that simulator and runs the test with
#       `flutter drive`; the driver records the screen to <output folder>/video.mp4
#       and saves screenshots there, next to the log. IQRO_LOCALE=en sets the app's
#       language (the driver hands it over); NO_VIDEO=1 skips the recording.
set -euo pipefail

command="${1:-}"

create() {
  local wanted="$1"
  local runtime
  runtime="$(
    xcrun simctl list runtimes available -j | ruby -rjson -e '
      runtimes = JSON.parse(STDIN.read).fetch("runtimes").select { |r| r["platform"] == "iOS" && r["isAvailable"] }
      abort "No iOS simulator runtime" if runtimes.empty?
      print runtimes.max_by { |r| Gem::Version.new(r.fetch("version")) }.to_json
    '
  )"
  local device
  device="$(
    xcrun simctl list devicetypes -j | WANTED="$wanted" RUNTIME="$runtime" ruby -rjson -e '
      runtime = JSON.parse(ENV.fetch("RUNTIME"))
      supported = runtime.fetch("supportedDeviceTypes", []).map { |t| t["identifier"] }
      types = JSON.parse(STDIN.read).fetch("devicetypes")
      ENV.fetch("WANTED").split("|").each do |name|
        type = types.find { |t| t["name"] == name && (supported.empty? || supported.include?(t["identifier"])) }
        next unless type
        print "#{name}\t#{type.fetch("identifier")}\t#{runtime.fetch("identifier")}\t#{runtime.fetch("version")}"
        exit
      end
      abort "None of #{ENV.fetch("WANTED")} runs on iOS #{runtime.fetch("version")}"
    '
  )"
  local name type runtime_id version
  IFS=$'\t' read -r name type runtime_id version <<<"$device"
  local id
  id="$(xcrun simctl create "IQRO $name" "$type" "$runtime_id")"
  echo "Created $name, iOS $version: $id" >&2
  xcrun simctl boot "$id"
  xcrun simctl bootstatus "$id" -b >&2
  # The same clean bar as Apple's own screenshots.
  xcrun simctl status_bar "$id" override \
    --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState charged --batteryLevel 100
  echo "$id"
}

# One `flutter drive`, its output shown live and kept in test.log. Returns its
# exit code, or 124 when the app never connected or the run went on too long.
drive() {
  local id="$1" app="$2" target="$3" out="$4" log="$4/test.log"
  : > "$log"
  IQRO_SIMULATOR="$id" IQRO_SCREENSHOTS="$out" flutter drive \
    --driver=integration_test/driver/iqro_driver.dart \
    --target="$target" \
    --use-application-binary="$app" \
    -d "$id" > "$log" 2>&1 &
  local runner=$!
  tail -n +1 -f "$log" &
  local shower=$!
  local started=$SECONDS stuck=0
  while kill -0 "$runner" 2>/dev/null; do
    sleep 5
    local elapsed=$((SECONDS - started))
    if { [ "$elapsed" -gt 360 ] && ! grep -q "Connecting to Flutter application" "$log"; } ||
      [ "$elapsed" -gt 1800 ]; then
      stuck=1
      echo "::warning::flutter drive stuck after ${elapsed}s; stopping it"
      pkill -TERM -P "$runner" 2>/dev/null || true
      kill -TERM "$runner" 2>/dev/null || true
      sleep 5
      pkill -KILL -P "$runner" 2>/dev/null || true
      kill -KILL "$runner" 2>/dev/null || true
      break
    fi
  done
  local code=0
  wait "$runner" 2>/dev/null || code=$?
  sleep 1
  kill "$shower" 2>/dev/null || true
  if [ "$stuck" -eq 1 ]; then return 124; fi
  return "$code"
}

run_test() {
  local id="$1" app="$2" target="$3" out="$4"
  mkdir -p "$out"
  out="$(cd "$out" && pwd)"
  rm -f "$out/video.pid"

  # The driver starts the recording once the app runs (NO_VIDEO=1: none).
  # flutter drive sometimes never sees the app's VM service on a simulator and
  # waits for ever: give the app 6 minutes to connect, then try once more.
  local status=1 attempt
  for attempt in 1 2; do
    if drive "$id" "$app" "$target" "$out"; then
      status=0
    else
      status=$?
    fi
    [ "$status" -ne 124 ] && break
    mv "$out/test.log" "$out/test-stuck-$attempt.log"
    xcrun simctl terminate "$id" forum.iqro.app 2>/dev/null || true
  done
  if [ "$status" -eq 0 ] && ! grep -q "All tests passed" "$out/test.log"; then
    status=1
  fi

  if [ -f "$out/video.pid" ]; then
    local recorder
    recorder="$(cat "$out/video.pid")"
    sleep 2
    kill -INT "$recorder" 2>/dev/null || true
    # SIGINT makes simctl finish the file; wait for it, at most 60 s.
    for _ in $(seq 60); do
      kill -0 "$recorder" 2>/dev/null || break
      sleep 1
    done
    rm -f "$out/video.pid"
  fi
  grep -E "IQRO (STEP|ERROR|NOTE|SUMMARY|DEVICE|LOCALE)" "$out/test.log" > "$out/steps.txt" || true
  ls -la "$out" >&2
  return "$status"
}

case "$command" in
  create) create "${2:?device types}" ;;
  test) run_test "${2:?simulator id}" "${3:?Runner.app}" "${4:?test file}" "${5:?output folder}" ;;
  *)
    sed -n '2,17p' "$0"
    exit 2
    ;;
esac
