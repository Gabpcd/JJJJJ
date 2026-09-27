#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = true
test "${NATIVE_RECETTE:-}" = 1
mkdir -p test-results/android-native
python3 tests/native/android/api.py >test-results/android-native/api-server.log 2>&1 &
recette_api_pid=$!
cleanup() {
  adb logcat -d >test-results/android-native/logcat.txt 2>&1 || true
  adb exec-out run-as app.jolene.recette cat cache/native-netlog.json >test-results/android-native/native-netlog.json 2>/dev/null || true
  adb shell iptables -L JOLENE_RECETTE -n -v -x >test-results/android-native/network-ipv4.txt 2>&1 || true
  adb shell ip6tables -L JOLENE_RECETTE -n -v -x >test-results/android-native/network-ipv6.txt 2>&1 || true
  adb shell dmesg >test-results/android-native/kernel-network.txt 2>&1 || true
  kill "$recette_api_pid" 2>/dev/null || true
}
trap cleanup EXIT
for attempt in {1..40}; do
  if curl --fail --silent http://127.0.0.1:8904/__recette/bilan >/dev/null; then break; fi
  sleep 0.25
done
curl --fail --silent http://127.0.0.1:8904/__recette/bilan >/dev/null
adb root
adb wait-for-device
adb reverse tcp:8904 tcp:8904
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
adb shell run-as app.jolene.recette mkdir -p cache
# Disable only Chromium's remote form predictions in this isolated WebView:
# native run 36327000422 proved they contacted content-autofill.googleapis.com.
# The native keyboard, local autofill and every app/plugin remain unchanged.
# Default NetLog capture excludes raw payloads; the firewall stays mandatory.
adb shell 'echo "webview --disable-features=AutofillServerCommunication --log-net-log=/data/user/0/app.jolene.recette/cache/native-netlog.json --net-log-capture-mode=Default" > /data/local/tmp/webview-command-line'
recette_uid=$(adb shell cmd package list packages -U app.jolene.recette | tr -d '\r' | sed -n 's/^package:app\.jolene\.recette uid:\([0-9][0-9]*\)$/\1/p')
[[ "$recette_uid" =~ ^[0-9]+$ ]]
# Even native plugins cannot contact a real service. Only the loopback API
# forwarded over adb is reachable by this app UID. Rules die with the emulator.
adb shell iptables -N JOLENE_RECETTE
adb shell iptables -A JOLENE_RECETTE -d 127.0.0.0/8 -j RETURN
# Log destinations if the emulator kernel offers LOG; rejection is mandatory
# even when this optional diagnostic target is unavailable.
adb shell iptables -A JOLENE_RECETTE -j LOG --log-prefix JOLENE_NATIVE_BLOCK4 --log-uid || true
adb shell iptables -A JOLENE_RECETTE -j REJECT
adb shell iptables -I OUTPUT 1 -m owner --uid-owner "$recette_uid" -j JOLENE_RECETTE
adb shell ip6tables -N JOLENE_RECETTE
adb shell ip6tables -A JOLENE_RECETTE -d ::1/128 -j RETURN
adb shell ip6tables -A JOLENE_RECETTE -j LOG --log-prefix JOLENE_NATIVE_BLOCK6 --log-uid || true
adb shell ip6tables -A JOLENE_RECETTE -j REJECT
adb shell ip6tables -I OUTPUT 1 -m owner --uid-owner "$recette_uid" -j JOLENE_RECETTE
adb shell settings put secure show_ime_with_hard_keyboard 1
node tests/native/android/navigation.mjs
