#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = true
test "${NATIVE_RECETTE:-}" = 1
test "$(git rev-parse HEAD)" = bf1c0ebf771533bb1666ae5f2bfd09560e4b0c84
proof="$PWD/test-results/ios-native"
derived="$RUNNER_TEMP/jolene-ios-derived"
mkdir -p "$proof"
xcodebuild -version >"$proof/xcode.txt"
xcrun simctl list devices available --json >"$proof/available-devices.json"
python3 - "$proof" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]); data=json.loads((p/'available-devices.json').read_text())
def version(key):
 return tuple(int(part) for part in key.split('.iOS-')[-1].split('-'))
runtimes=sorted((r for r in data['devices'] if '.iOS-' in r),key=version,reverse=True)
for runtime in runtimes:
 selected=[]
 for kind in ['iPhone','iPad']:
  matches=[d for d in data['devices'][runtime] if d.get('isAvailable') and d['name'].startswith(kind) and d.get('deviceTypeIdentifier')]
  if matches: selected.append((kind,runtime,matches[0]['deviceTypeIdentifier'],matches[0]['name']))
 if len(selected)==2:
  (p/'devices.tsv').write_text(''.join('\t'.join(d)+'\n' for d in selected))
  break
else: raise SystemExit('Aucun runtime installé avec iPhone et iPad disponibles')
PY
xcodebuild -project ios/App/App.xcodeproj -scheme JoleneRecette -configuration Release \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build-for-testing 2>&1 | tee "$proof/build.log"
python3 - "$derived" "$proof" <<'PY'
import json,sys,plistlib,hashlib
from pathlib import Path
d,p=map(Path,sys.argv[1:]); app=d/'Build/Products/Release-iphonesimulator/App.app'
info=plistlib.loads((app/'Info.plist').read_bytes())
assert info['CFBundleShortVersionString']=='1.0.7',info['CFBundleShortVersionString']
assert info['CFBundleVersion']=='24',info['CFBundleVersion']
assert info['CFBundleIdentifier']=='app.jolene.recette',info['CFBundleIdentifier']
executable=app/info['CFBundleExecutable']; stamp=json.loads((p/'build-input.json').read_text())
stamp.update(binarySha256=hashlib.sha256(executable.read_bytes()).hexdigest(),sdk=info.get('DTSDKName'),
 version=info['CFBundleShortVersionString'],build=info['CFBundleVersion'],bundle=info['CFBundleIdentifier'])
assert 'simulator' in (stamp['sdk'] or ''),stamp
(p/'binary-manifest.json').write_text(json.dumps(stamp,indent=2)+'\n')
plans=list((d/'Build/Products').glob('*.xctestrun'));assert len(plans)==1,plans
(p/'testplan.txt').write_text(str(plans[0])+'\n')
PY
testplan=$(cat "$proof/testplan.txt")
api_pid=''
simulator=''
cleanup() {
  if [ -n "$api_pid" ]; then kill "$api_pid" 2>/dev/null || true; wait "$api_pid" 2>/dev/null || true; api_pid=''; fi
  if [ -n "$simulator" ]; then xcrun simctl shutdown "$simulator" >/dev/null 2>&1 || true; simulator=''; fi
}
trap cleanup EXIT
node ../tooling/scripts/ci/auth107-staging.mjs begin
failed=0
while IFS=$'\t' read -r kind runtime device_type device_name; do
  output="$proof/$kind"
  mkdir -p "$output"
  simulator=$(xcrun simctl create "Jolene 1.0.7-24 $kind" "$device_type" "$runtime")
  printf '%s\n' "$simulator" >"$output/simulator-id.txt"
  xcrun simctl boot "$simulator"
  xcrun simctl bootstatus "$simulator" -b
  python3 ../tooling/scripts/native/auth107-monitor.py >"$output/api-server.log" 2>&1 &
  api_pid=$!
  for attempt in $(seq 1 30); do
    kill -0 "$api_pid"
    if curl --fail --silent http://127.0.0.1:8904/__recette/bilan >"$output/api-initial.json"; then break; fi
    sleep 1
  done
  test -s "$output/api-initial.json"
  kill -0 "$api_pid"
  set +e
  xcodebuild test-without-building -xctestrun "$testplan" \
    -destination "platform=iOS Simulator,id=$simulator" \
    -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
    -resultBundlePath "$output/recette.xcresult" 2>&1 | tee "$output/test.log"
  result=${PIPESTATUS[0]}
  set -e
  printf '%s\n' "$result" >"$output/xctest-exit.txt"
  if [ "$result" != 0 ]; then failed=1; fi
  if [ -d "$output/recette.xcresult" ]; then
    xcrun xcresulttool export attachments --path "$output/recette.xcresult" --output-path "$output/attachments" || failed=1
    xcrun xcresulttool get test-results summary --path "$output/recette.xcresult" >"$output/xctest-summary.json" || failed=1
    python3 - "$output" "$proof/review/$kind" <<'PY' || failed=1
import json,sys,shutil
from pathlib import Path
source,dest=map(Path,sys.argv[1:]);dest.mkdir(parents=True,exist_ok=True)
manifest=json.loads((source/'attachments/manifest.json').read_text())
assert isinstance(manifest,list),'Format des pièces XCTest inconnu'
wanted=['soignant-inscription-accueil','etab-inscription-accueil','inscription-paysage-accueil','relancement-accueil','reconnexion-accueil']
selected=[]; representative_count=0
for test in manifest:
 for a in test['attachments']:
  file=source/'attachments'/a['exportedFileName'];name=a['suggestedHumanReadableName']
  if file.suffix.lower() not in ['.png','.jpg','.jpeg','.heic'] or '-accessibilite' in name:continue
  failure=a['isAssociatedWithFailure']
  final='etat-final-meme-en-echec' in name
  representative=any(marker in name for marker in wanted)
  if not (failure or final or representative):continue
  if not (failure or final):
   if representative_count>=6:continue
   representative_count+=1
  target=f'{len(selected)+1:02d}-{file.name}'
  shutil.copyfile(file,dest/target);selected.append({'file':target,'name':name,'failure':failure,'finalState':final})
(dest/'captures.json').write_text(json.dumps(selected,ensure_ascii=False,indent=2)+'\n')
shutil.copyfile(source/'xctest-summary.json',dest/'xctest-summary.json')
PY
  else
    failed=1
  fi
  xcrun simctl io "$simulator" screenshot "$output/final.png" || failed=1
  mkdir -p "$proof/review/$kind"
  # Secours même si setUp échoue avant launch ou si xcresult n'a pas de capture.
  # Cet écran est pris après XCTest/tearDown, pas à l'instant exact de l'échec.
  if [ -f "$output/final.png" ]; then cp "$output/final.png" "$proof/review/$kind/final-after-xctest.png"; fi
  curl --fail --silent http://127.0.0.1:8904/__recette/bilan >"$output/api-report.json" || failed=1
  python3 - "$output" <<'PY' || failed=1
import json,sys
from pathlib import Path
p=Path(sys.argv[1]);data=json.loads((p/'api-report.json').read_text())
checks={'xctestPassed':(p/'xctest-exit.txt').read_text().strip()=='0',
 'noUnhandledErrors':data['errors']==[],
 'twoRealSignups':sum(c.get('path')=='/auth/v1/signup' and c.get('status')=='200' for c in data['calls'])==2,
 'realRegistrationRpc':sum(c.get('path')=='/rest/v1/rpc/fn_demarrer_inscription' and c.get('status')=='200' for c in data['calls'])==2}
(p/'summary.json').write_text(json.dumps({'mode':'SIMULATEUR_IOS_AUTH_ET_DB_STAGING_REELS','checks':checks,'diagnostics':data,'success':all(checks.values())},indent=2)+'\n')
assert all(checks.values()),checks
PY
  mkdir -p "$proof/review/$kind"
  if [ -f "$output/summary.json" ]; then cp "$output/summary.json" "$proof/review/$kind/summary.json"; fi
  cleanup
done <"$proof/devices.tsv"
cp "$proof/binary-manifest.json" "$proof/review/binary-manifest.json"
cp "$proof/devices.tsv" "$proof/review/devices.tsv"
exit "$failed"
