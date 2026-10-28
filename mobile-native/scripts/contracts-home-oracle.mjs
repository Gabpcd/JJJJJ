// Supplement the real UI assertions with same-execution, demo-only lifecycle evidence.
// No input text, account identity or session token is accepted or returned here.
const fail = message => { throw new Error(`Preuve Home Contrats invalide : ${message}.`); };
const integer = value => Number.isSafeInteger(value) && value >= 0;
const stages = ['armed', 'home-visible', 'activate', 'resumed'];

function readEvents(metro) {
  if (typeof metro !== 'string' || metro.length > 8 * 1024 * 1024) fail('journal absent ou trop volumineux');
  const entries = [];
  for (const [line, text] of metro.split('\n').entries()) {
    const match = text.match(/\[jolene-native-(navigation|contract-input)\]\s+(\{.*\})\s*$/);
    if (!match) continue;
    let event;
    try { event = JSON.parse(match[2]); } catch { fail('événement JSON illisible'); }
    if (!event || !integer(event.sequence) || event.sequence < 1 || !integer(event.atMs)
      || !integer(event.startedAtMs) || event.atMs < event.startedAtMs || typeof event.event !== 'string') {
      fail('événement non horodaté ou incomplet');
    }
    entries.push({ ...event, stream: match[1], line });
  }
  return entries;
}

function orderedStream(entries, label) {
  if (!entries.length) fail(`flux ${label} absent`);
  for (let i = 1; i < entries.length; i++) {
    if (entries[i].startedAtMs !== entries[0].startedAtMs
      || entries[i].sequence !== entries[i - 1].sequence + 1
      || entries[i].atMs < entries[i - 1].atMs) fail(`flux ${label} interrompu ou réinitialisé`);
  }
}

export function verifyContractsHomeEvidence({ proof, metro, native }) {
  if (!proof || proof.schemaVersion !== 1 || !/^[0-9a-f-]{36}$/i.test(proof.id ?? '')
    || !['iphone-portrait', 'ipad-portrait', 'ipad-paysage'].includes(proof.prefix)
    || proof.homePresses !== 1 || proof.activations !== 1 || !Array.isArray(proof.markers)
    || proof.markers.length !== stages.length) fail('marqueurs XCTest absents ou ambigus');
  const markers = proof.markers;
  markers.forEach((marker, i) => {
    if (marker.stage !== stages[i] || !integer(marker.atMs)
      || (i && marker.atMs <= markers[i - 1].atMs)) fail('ordre des marqueurs XCTest');
  });
  const [armed, home, activate, resumed] = markers;
  if (armed.homeVisible !== false || armed.codeLength !== 6 || home.homeVisible !== true
    || resumed.homeVisible !== false || resumed.codeLength !== 0 || resumed.consentEnabled !== false
    || resumed.originalVisible !== true) fail('oracles visuels incomplets');
  const events = readEvents(metro);
  const input = events.filter(entry => entry.stream === 'contract-input' && entry.atMs <= resumed.atMs);
  const beforeHome = input.filter(entry => entry.atMs <= armed.atMs);
  const six = beforeHome.findLast(entry => entry.event === 'committed');
  if (!six || six.length !== 6 || six.active !== true) fail('six chiffres non confirmés avant Home');
  const scopedInput = input.filter(entry => entry.line >= six.line);
  orderedStream(scopedInput, 'saisie');
  if (scopedInput.some(entry => entry.event === 'reset' && entry.reason === 'focus-cleanup')) fail('écran remplacé pendant Home');
  if (scopedInput.some(entry => entry.line > six.line && (entry.event === 'native-change' || entry.event === 'text-change'
    || (entry.event === 'committed' && entry.length !== 0)))) fail('saisie intervenue pendant Home');
  const navigation = events.filter(entry => entry.stream === 'navigation'
    && entry.atMs >= six.atMs && entry.atMs <= resumed.atMs);
  orderedStream(navigation, 'navigation');
  const states = navigation.filter(entry => entry.event === 'appState');
  const backgrounds = states.filter(entry => entry.detail === 'background');
  if (backgrounds.length !== 1 || backgrounds[0].atMs < armed.atMs || backgrounds[0].atMs > activate.atMs) {
    fail('passage background absent ou hors du Home observé');
  }
  const background = backgrounds[0];
  const actives = states.filter(entry => entry.detail === 'active');
  if (actives.length !== 1 || actives[0].atMs < activate.atMs || actives[0].line <= background.line) {
    fail('reprise active absente ou désordonnée');
  }
  const active = actives[0];
  if (!scopedInput.some(entry => entry.event === 'reset' && entry.reason === 'app-nonactive'
    && entry.atMs >= armed.atMs && entry.line < active.line)) fail('purge de sortie absente');
  if (!scopedInput.some(entry => entry.event === 'reset' && entry.reason === 'app-active'
    && entry.line > active.line)) fail('réinitialisation de reprise absente');
  const cleared = scopedInput.findLast(entry => entry.event === 'committed');
  if (!cleared || cleared.line <= active.line || cleared.length !== 0 || cleared.active !== true) {
    fail('purge à zéro non confirmée après reprise active');
  }
  if (native !== undefined) {
    // Metro is the single complete event sequence, also used by Expo Go. Unified
    // Logging can drop a burst (28dc500: input 10..35), even with a healthy stream.
    // The separately PID-bound native stream attests its origin; it never fills
    // gaps, replaces events or rescues an incomplete Metro/UI proof.
    const key = entry => `${entry.stream}:${entry.startedAtMs}:${entry.sequence}`;
    const value = ({ line, ...entry }) => JSON.stringify(entry);
    const canonical = new Map();
    for (const entry of events.filter(entry => entry.atMs <= resumed.atMs)) {
      if (canonical.has(key(entry))) fail('événement Metro dupliqué');
      canonical.set(key(entry), value(entry));
    }
    const witnesses = readEvents(native).filter(entry => entry.atMs <= resumed.atMs);
    const seen = new Set();
    for (const entry of witnesses) {
      if (seen.has(key(entry)) || canonical.get(key(entry)) !== value(entry)) {
        fail('flux natif distinct du journal Metro');
      }
      seen.add(key(entry));
    }
    const sameInput = witnesses.filter(entry => entry.stream === 'contract-input'
      && entry.startedAtMs === six.startedAtMs);
    if (!sameInput.some(entry => entry.atMs <= armed.atMs)
      || !sameInput.some(entry => key(entry) === key(cleared))
      || !seen.has(key(background)) || !seen.has(key(active))) {
      fail('origine native de la saisie et du cycle Home non confirmée');
    }
  }
  return { schemaVersion: 1, success: true, proofId: proof.id, prefix: proof.prefix,
    homePresses: 1, activations: 1, committedBeforeHome: 6, committedAfterResume: 0,
    backgroundObserved: true, source: 'synthetic-simulator-ui-and-js',
    ...(native !== undefined ? { nativeProcessStreamMatched: true, canonicalStream: 'metro' } : {}),
    times: { armed: armed.atMs, homeVisible: home.atMs, background: background.atMs,
      activate: activate.atMs, active: active.atMs, cleared: cleared.atMs, resumed: resumed.atMs } };
}
