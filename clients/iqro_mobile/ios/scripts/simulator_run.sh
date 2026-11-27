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

run_test() {
  local id="$1" app="$2" target="$3" out="$4"
  mkdir -p "$out"
  out="$(cd "$out" && pwd)"
  rm -f "$out/video.pid"

  # The driver starts the recording once the app runs (NO_VIDEO=1: none).
  local status=0
  IQRO_SIMULATOR="$id" IQRO_SCREENSHOTS="$out" flutter drive \
    --driver=integration_test/driver/iqro_driver.dart \
    --target="$target" \
    --use-application-binary="$app" \
    -d "$id" \
    2>&1 | tee "$out/test.log" || status=$?
  # tee hides flutter's exit code unless pipefail catches it.
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
