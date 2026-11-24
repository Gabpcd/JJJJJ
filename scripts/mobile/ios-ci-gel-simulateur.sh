#!/usr/bin/env bash
# Gel iPhone de la CI iOS (docs/mobile-swift/DECISIONS_LOT2.md, section « Gel iPhone CI — 16/11/2026 » ; run
# 43889328109) : outils des éclats XCUITest des jobs `ui` et `ui-lot1` de `.github/workflows/ios-swift-ci.yml`. Le fil
# principal de l'app y attend le serveur de rendu du simulateur (`CA::Render::Message::send_message`, aucune fonction Jolene) ; le
# simulateur ne relance plus l'app ensuite et les éclats suivants mouraient à 30 min sans preuve.
#
#   relancer-si-gel <éclat>     Au début de chaque éclat qui suit le premier de son job (socle, lot1-missions). Si
#                               l'éclat précédent a gelé ou dépassé son délai, redémarre le simulateur (`simctl shutdown`,
#                               `boot`, `bootstatus -b`) en 2 min au
#                               plus (`JOLENE_RELANCE_BORNE_S`, 120 par défaut), dans les 30 min de l'éclat courant, pour
#                               qu'il s'exécute et garde ses preuves. Gel ou dépassement : éclat précédent en échec dont
#                               le journal contient « main thread busy », « failed to quiesce », « Failed to get launch
#                               progress » ou « exceeded execution time allowance » (casse ignorée ; un éclat vert, code 0,
#                               n'est jamais redémarré pour une attente absorbée) ; étape précédente interrompue
#                               ou en échec (issue autre que success ou skipped : délai de 30 min dépassé, sans code de
#                               sortie) ; xcodebuild tué (code 124, 130, 137 ou 143). L'éclat gelé reste en échec : rien
#                               n'est masqué, le résumé xcresult exige toujours chaque éclat vert.
#                               Environnement : UDID, JOLENE_UI_OUTPUT, ECLAT_PRECEDENT, ECLAT_PRECEDENT_ISSUE
#                               (`steps.<id>.outcome`), ECLAT_PRECEDENT_CODE (`steps.<id>.outputs.code`).
#   veiller <éclat> <journal>   En tâche de fond des éclats socle, presences et pointage. Dès que le journal xcodebuild
#                               signale une app qui ne redevient pas inactive, ou qu'un test y est en cours depuis plus
#                               de JOLENE_VEILLEUR_SEUIL_TEST_S (420 s : 1,6 fois le plus long test mesuré de ces éclats,
#                               264 s, et 3 min avant le délai d'exécution de 600 s ; à la tentative 2 du run
#                               45239724447, un test a duré dix minutes, un événement toutes les 2 min 8 s, sans relevé
#                               lisible), trois passes à 60 s d'écart : `sample` de l'app
#                               Jolene, de backboardd et de SpringBoard du simulateur, capture d'écran du simulateur
#                               (30 s au plus), journal du simulateur des 10 dernières minutes (passes 1 et 3), rapports
#                               .ips récents de l'hôte et du simulateur, mémoire de l'hôte (vm_stat, swap, top). Fichiers
#                               `gel-<éclat>-*` dans JOLENE_UI_OUTPUT, conservés par l'artefact du job.
#   borne <secondes> <commande…> Exécute la commande au plus <secondes> (SIGTERM, puis SIGKILL 2 s après) ; rend son code.
#                               macOS n'a pas `timeout` : chien de garde en shell, compatible bash 3.2.
#
# Aucune sous-commande de relevé ne fait échouer l'étape appelante : `relancer-si-gel` et `veiller` rendent toujours 0,
# même si un outil échoue ou dépasse sa borne. Garde : tests/node/ios-swift-ci-eclats.node.mjs (outils simulés).
# Réglages des gardes Node seulement : JOLENE_VEILLEUR_PAS_S (10 s), JOLENE_VEILLEUR_PAUSE_S (60 s),
# JOLENE_VEILLEUR_SEUIL_TEST_S (420 s), JOLENE_IPS_HOTE.

set -u
UDID="${UDID:-}"

MARQUES_GEL='main thread busy|failed to quiesce|Failed to get launch progress|exceeded execution time allowance'
# Le veilleur se déclenche aussi sur l'attente d'inactivité qui précède ces marques (diagnostic d'origine).
MARQUES_VEILLEUR="App event loop idle notification not received|$MARQUES_GEL"
PREDICAT_JOURNAL='process == "backboardd" OR process == "SpringBoard" OR process == "Jolene" OR subsystem BEGINSWITH "com.apple.UIKit" OR subsystem CONTAINS[c] "coreanimation" OR category CONTAINS[c] "CoreAnimation"'

horodatage() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# borne <secondes> <commande…> : code de la commande, 143 si elle est coupée par SIGTERM, 137 par SIGKILL.
borne() {
  local secondes="${1:-1}"
  shift
  case "$secondes" in '' | *[!0-9]*) secondes=1 ;; esac
  [ "$secondes" -ge 1 ] || secondes=1
  "$@" &
  local cible=$!
  # Chien de garde : `wait` (interrompu par le piège, contrairement à un `sleep` au premier plan) s'arrête dès que la
  # commande a fini ; il ne signale donc jamais un pid terminé, puis réattribué.
  (
    sleep "$secondes" &
    dormeur=$!
    trap 'kill "$dormeur" 2>/dev/null; exit 0' TERM
    wait "$dormeur"
    kill -TERM "$cible" 2>/dev/null
    sleep 2 &
    dormeur=$!
    wait "$dormeur"
    kill -KILL "$cible" 2>/dev/null
  ) >/dev/null 2>&1 &
  local garde=$!
  wait "$cible"
  local code=$?
  kill -TERM "$garde" 2>/dev/null
  wait "$garde" 2>/dev/null
  return "$code"
}

# borne_restante <échéance epoch> <commande…> : borne par le temps restant jusqu'à l'échéance commune du redémarrage.
borne_restante() {
  local fin="$1"
  shift
  local reste=$((fin - $(date +%s)))
  if [ "$reste" -lt 1 ]; then
    echo "échéance du redémarrage atteinte : « $* » non lancé"
    return 124
  fi
  borne "$reste" "$@"
}

# raison_du_gel <issue> <code> <journal> : texte de la raison, vide si l'éclat précédent n'a ni gelé ni dépassé.
raison_du_gel() {
  local issue="$1" code="$2" journal="$3" marque
  case "$issue" in
    '' | success) ;;
    *) echo "étape interrompue ou en échec (issue $issue, code ${code:-absent})"; return 0 ;;
  esac
  case "$code" in
    124 | 130 | 137 | 143) echo "xcodebuild interrompu (code $code)"; return 0 ;;
    # Éclat vert : une attente absorbée (« main thread busy » passager) n'est pas un gel, rien n'est redémarré.
    0) return 0 ;;
  esac
  if [ -f "$journal" ]; then
    marque="$(grep -oiE "$MARQUES_GEL" "$journal" 2>/dev/null | head -n 1)"
    if [ -n "$marque" ]; then echo "journal de l'éclat : « $marque »"; return 0; fi
  fi
  return 0
}

relancer_si_gel() {
  local eclat="${1:-?}"
  local precedent="${ECLAT_PRECEDENT:-?}" issue="${ECLAT_PRECEDENT_ISSUE:-}" code="${ECLAT_PRECEDENT_CODE:-}"
  local sortie="${JOLENE_UI_OUTPUT:-.}" udid="${UDID:-}"
  if [ "$issue" = skipped ]; then
    echo "Éclat $precedent sauté : simulateur conservé pour l'éclat $eclat."
    return 0
  fi
  local raison
  raison="$(raison_du_gel "$issue" "$code" "$sortie/test-without-building-$precedent.log")"
  if [ -z "$raison" ]; then
    echo "Éclat $precedent : ni gel ni dépassement constaté (issue ${issue:-absente}, code ${code:-absent}) : simulateur conservé pour l'éclat $eclat."
    return 0
  fi
  local borne_s="${JOLENE_RELANCE_BORNE_S:-120}"
  case "$borne_s" in '' | *[!0-9]*) borne_s=120 ;; esac
  echo "::warning::Éclat $precedent : gel ou dépassement constaté ($raison). Simulateur ${udid:-?} redémarré avant l'éclat $eclat (${borne_s} s au plus) ; l'éclat $precedent reste en échec."
  mkdir -p "$sortie" 2>/dev/null
  local trace="$sortie/relance-simulateur-avant-$eclat.txt"
  local debut fin c_arret c_demarrage c_attente
  debut=$(date +%s)
  fin=$((debut + borne_s))
  {
    echo "Redémarrage du simulateur ${udid:-?} avant l'éclat $eclat ($(horodatage))"
    echo "Éclat précédent : $precedent (issue ${issue:-absente}, code ${code:-absent}) ; raison : $raison"
    borne_restante "$fin" xcrun simctl shutdown "$UDID"
    c_arret=$?
    echo "simctl shutdown : code $c_arret"
    borne_restante "$fin" xcrun simctl boot "$UDID"
    c_demarrage=$?
    echo "simctl boot : code $c_demarrage"
    borne_restante "$fin" xcrun simctl bootstatus "$UDID" -b
    c_attente=$?
    echo "simctl bootstatus -b : code $c_attente"
  } >>"$trace" 2>&1
  local duree=$(($(date +%s) - debut))
  local bilan
  if [ "${c_demarrage:-1}" -eq 0 ] && [ "${c_attente:-1}" -eq 0 ]; then
    bilan="simulateur redémarré avant l'éclat $eclat en ${duree} s"
    echo "Éclat $precedent : $bilan (shutdown $c_arret, boot $c_demarrage, bootstatus $c_attente)."
  else
    bilan="redémarrage non abouti avant l'éclat $eclat en ${duree} s (shutdown ${c_arret:-?}, boot ${c_demarrage:-?}, bootstatus ${c_attente:-?}) : l'éclat tourne sur le simulateur en l'état"
    echo "::warning::Éclat $precedent : $bilan."
  fi
  echo "Bilan : $bilan ($(horodatage))" >>"$trace" 2>&1
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "- éclat $precedent : gel ou dépassement constaté ($raison) ; $bilan ; l'éclat $precedent reste en échec." >>"$GITHUB_STEP_SUMMARY" 2>/dev/null
  fi
  return 0
}

# pid_simulateur <backboardd|SpringBoard> : pid hôte du service du simulateur (launchctl du simulateur, sinon pgrep sur
# le chemin du runtime ; un seul simulateur est démarré par job).
pid_simulateur() {
  local nom="$1" label motif pid
  case "$nom" in
    backboardd) label="com.apple.backboardd"; motif="RuntimeRoot/usr/libexec/backboardd" ;;
    *) label="com.apple.SpringBoard"; motif="RuntimeRoot/System/Library/CoreServices/SpringBoard.app/SpringBoard" ;;
  esac
  pid="$(borne 20 xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | awk -v l="$label" '$3 == l && $1 ~ /^[0-9]+$/ { print $1; exit }')"
  [ -n "$pid" ] || pid="$(pgrep -n -f "$motif" 2>/dev/null | head -n 1)"
  echo "$pid"
}

# echantillonner <pid> <fichier> <nom> : `sample` de 5 s (sudo -n en repli), 30 s au plus ; l'échec est consigné.
echantillonner() {
  local pid="$1" fichier="$2" nom="$3"
  if [ -z "$pid" ]; then
    echo "$nom : processus introuvable ($(horodatage))" >"$fichier" 2>/dev/null
    return 0
  fi
  borne 30 sample "$pid" 5 -file "$fichier" >/dev/null 2>&1 && [ -s "$fichier" ] && return 0
  borne 30 sudo -n sample "$pid" 5 -file "$fichier" >/dev/null 2>&1 && [ -s "$fichier" ] && return 0
  echo "$nom (pid $pid) : sample a échoué ou dépassé 30 s ($(horodatage))" >>"$fichier" 2>/dev/null
  return 0
}

memoire() {
  echo "# Mémoire de l'hôte ($(horodatage))"
  echo "## vm_stat"
  borne 15 vm_stat
  echo "## sysctl vm.swapusage"
  borne 15 sysctl vm.swapusage
  echo "## top -l 1"
  borne 30 top -l 1
  return 0
}

# copier_ips <dossier> : rapports .ips de moins d'une heure, de l'hôte et du simulateur, sans écraser.
copier_ips() {
  local dest="$1" dossier
  mkdir -p "$dest/hote" "$dest/simulateur" 2>/dev/null || return 0
  for dossier in ${JOLENE_IPS_HOTE:-$HOME/Library/Logs/DiagnosticReports /Library/Logs/DiagnosticReports}; do
    [ -d "$dossier" ] || continue
    find "$dossier" -maxdepth 2 -type f -name '*.ips' -mmin -60 -exec cp -n {} "$dest/hote/" \; 2>/dev/null
  done
  dossier="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/Logs"
  if [ -d "$dossier" ]; then
    find "$dossier" -type f -name '*.ips' -mmin -60 -exec cp -n {} "$dest/simulateur/" \; 2>/dev/null
  fi
  return 0
}

collecter() {
  local prefixe="$1" n="$2"
  echantillonner "$(pgrep -n -f '/Jolene.app/Jolene' 2>/dev/null | head -n 1)" "$prefixe-sample-$n.txt" "app Jolene"
  echantillonner "$(pid_simulateur backboardd)" "$prefixe-backboardd-sample-$n.txt" backboardd
  echantillonner "$(pid_simulateur SpringBoard)" "$prefixe-springboard-sample-$n.txt" SpringBoard
  if ! borne 30 xcrun simctl io "$UDID" screenshot "$prefixe-ecran-$n.png" >/dev/null 2>&1; then
    echo "capture d'écran du simulateur : échec ou délai de 30 s dépassé ($(horodatage))" >"$prefixe-ecran-$n.txt" 2>/dev/null
  fi
  memoire >"$prefixe-memoire-$n.txt" 2>&1
  if [ "$n" != 2 ]; then
    borne 90 xcrun simctl spawn "$UDID" log show --last 10m --style compact --predicate "$PREDICAT_JOURNAL" \
      >"$prefixe-journal-simulateur-$n.txt" 2>&1
  fi
  copier_ips "$prefixe-ips"
  return 0
}

# test_en_cours <journal> : test démarré sans ligne de conclusion au journal (« -[Cible.Classe test] »), vide sinon.
test_en_cours() {
  [ -f "$1" ] || return 0
  awk '
    /^Test Case .* started\.$/ { courant = $3 " " $4; next }
    /^Test Case .* (passed|failed) [(]/ { courant = "" }
    END { if (courant != "") { gsub("\047", "", courant); print courant } }
  ' "$1" 2>/dev/null
  return 0
}

veiller() {
  local eclat="${1:-?}" journal="${2:-}"
  local prefixe="${JOLENE_UI_OUTPUT:-.}/gel-$eclat"
  local pas="${JOLENE_VEILLEUR_PAS_S:-10}" pause="${JOLENE_VEILLEUR_PAUSE_S:-60}" n
  local seuil="${JOLENE_VEILLEUR_SEUIL_TEST_S:-420}"
  case "$seuil" in '' | *[!0-9]*) seuil=420 ;; esac
  # Test suivi, et instant où le veilleur l'a vu en cours pour la première fois (à `pas` secondes près).
  local suivi="" depuis=0 courant raison
  for n in 1 2 3; do
    while :; do
      if grep -qiE "$MARQUES_VEILLEUR" "$journal" 2>/dev/null; then
        raison="marque de gel au journal"
        break
      fi
      courant="$(test_en_cours "$journal")"
      if [ "$courant" != "$suivi" ]; then
        suivi="$courant"
        depuis=$(date +%s)
      fi
      if [ -n "$suivi" ] && [ $(($(date +%s) - depuis)) -ge "$seuil" ]; then
        raison="test $suivi en cours depuis plus de $seuil s"
        break
      fi
      sleep "$pas"
    done
    echo "Passe $n du veilleur ($eclat) : $(horodatage) — $raison"
    collecter "$prefixe" "$n"
    echo "Passe $n terminée : $(horodatage)"
    [ "$n" -lt 3 ] && sleep "$pause"
  done
  return 0
}

case "${1:-}" in
  relancer-si-gel) shift; relancer_si_gel "$@"; exit 0 ;;
  veiller) shift; veiller "$@"; exit 0 ;;
  borne) shift; borne "$@"; exit $? ;;
  *)
    echo "usage : $0 relancer-si-gel <éclat> | veiller <éclat> <journal> | borne <secondes> <commande…>" >&2
    exit 2
    ;;
esac
