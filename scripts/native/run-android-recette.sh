#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = true
test "${NATIVE_RECETTE:-}" = 1
recette_variant=${NATIVE_RECETTE_VARIANT:-debug}
case "$recette_variant" in
  debug) recette_apk=android/app/build/outputs/apk/debug/app-debug.apk ;;
  optimized) recette_apk=android/app/build/outputs/apk/recetteOptimized/app-recetteOptimized.apk ;;
  *) exit 1 ;;
esac
mkdir -p test-results/android-native
python3 tests/native/android/api.py >test-results/android-native/api-server.log 2>&1 &
recette_api_pid=$!
# Best-effort evidence must also finish if the Android transport is stuck.
collect_cleanup_adb() {
  timeout --signal=TERM --kill-after=2s 10s adb "$@"
}
cleanup() {
  collect_cleanup_adb shell dumpsys window >test-results/android-native/android-windows.txt 2>&1 || true
  collect_cleanup_adb shell dumpsys activity lastanr >test-results/android-native/android-last-anr.txt 2>&1 || true
  collect_cleanup_adb exec-out screencap -p >test-results/android-native/android-final-screen.png 2>/dev/null || true
  # Startup attachment diagnostics contain only process/socket metadata from
  # this fictional emulator, captured even when Playwright cannot attach.
  collect_cleanup_adb shell ps -A >test-results/android-native/android-processes.txt 2>&1 || true
  collect_cleanup_adb shell cat /proc/net/unix >test-results/android-native/android-unix-sockets.txt 2>&1 || true
  collect_cleanup_adb logcat -d >test-results/android-native/logcat.txt 2>&1 || true
  if [ "$recette_variant" = optimized ]; then
    collect_cleanup_adb exec-out cat /data/user/0/app.jolene.recette/cache/native-netlog.json >test-results/android-native/native-netlog.json 2>/dev/null || true
  else
    collect_cleanup_adb exec-out run-as app.jolene.recette cat cache/native-netlog.json >test-results/android-native/native-netlog.json 2>/dev/null || true
  fi
  collect_cleanup_adb shell iptables -L JOLENE_RECETTE -n -v -x >test-results/android-native/network-ipv4.txt 2>&1 || true
  collect_cleanup_adb shell ip6tables -L JOLENE_RECETTE -n -v -x >test-results/android-native/network-ipv6.txt 2>&1 || true
  collect_cleanup_adb shell dmesg >test-results/android-native/kernel-network.txt 2>&1 || true
  kill "$recette_api_pid" 2>/dev/null || true
}
trap cleanup EXIT
for attempt in {1..40}; do
  if curl --fail --silent http://127.0.0.1:8904/__recette/bilan >/dev/null; then break; fi
  sleep 0.25
done
curl --fail --silent http://127.0.0.1:8904/__recette/bilan >/dev/null
node tests/native/android/adb-readiness.mjs
adb reverse tcp:8904 tcp:8904
node tests/native/android/emulator-preflight.mjs
# Prove the installed binary identity and non-debuggable optimization variant.
recette_analyzer="$ANDROID_HOME/cmdline-tools/latest/bin/apkanalyzer"
test "$("$recette_analyzer" manifest application-id "$recette_apk")" = app.jolene.recette
if [ "$recette_variant" = optimized ]; then
  test "$("$recette_analyzer" manifest debuggable "$recette_apk")" = false
fi
adb install -r "$recette_apk"
# Disable only Chromium's remote form predictions in this isolated WebView:
# native run 36327000422 proved they contacted content-autofill.googleapis.com.
# The native keyboard, local autofill and every app/plugin remain unchanged.
# Default NetLog capture excludes raw payloads; the firewall stays mandatory.
adb shell 'echo "webview --disable-features=AutofillServerCommunication --log-net-log=/data/user/0/app.jolene.recette/cache/native-netlog.json --net-log-capture-mode=Default" > /data/local/tmp/webview-command-line'
recette_uid=$(adb shell cmd package list packages -U app.jolene.recette | tr -d '\r' | sed -n 's/^package:app\.jolene\.recette uid:\([0-9][0-9]*\)$/\1/p')
[[ "$recette_uid" =~ ^[0-9]+$ ]]
if [ "$recette_variant" = optimized ]; then
  # adb is already root in this disposable emulator; run-as intentionally cannot
  # open a non-debuggable app. Only this fixture UID's cache is prepared/read.
  adb shell mkdir -p /data/user/0/app.jolene.recette/cache
  adb shell chown "$recette_uid:$recette_uid" /data/user/0/app.jolene.recette/cache
else
  adb shell run-as app.jolene.recette mkdir -p cache
fi
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
# Bound the entire child, including screenshot/driver shutdown on failure.
# This never retries a scenario or changes any UI assertion deadline.
recette_navigation_exit=0
if timeout --signal=TERM --kill-after=15s 600s node tests/native/android/navigation.mjs; then
  recette_navigation_outcome=completed
else
  recette_navigation_exit=$?
  case "$recette_navigation_exit" in
    124) recette_navigation_outcome=timeout_exit ;;
    137) recette_navigation_outcome=killed_exit ;;
    *) recette_navigation_outcome=failed ;;
  esac
fi
# A killed child may never reach its own failure.json; retain a closed receipt.
# killed_exit does not assert whether SIGKILL came from timeout, OOM or elsewhere.
if ! printf '{"schema":1,"scope":"navigation-process-only","outcome":"%s","exitCode":%s,"limitSeconds":600,"killAfterSeconds":15,"uiValidated":false}\n' \
  "$recette_navigation_outcome" "$recette_navigation_exit" >test-results/android-native/navigation-process.json; then
  if [ "$recette_navigation_exit" -eq 0 ]; then recette_navigation_exit=1; fi
fi
exit "$recette_navigation_exit"
