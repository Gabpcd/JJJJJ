import { EXPO_URL } from './policy.mjs';

// Every returned flow is private; credentials are literals only in 0600 temporary
// files, never CLI arguments, Expo environment, source control or public reports.
export function androidFlows(cohort) {
  const q = JSON.stringify;
  const regex = value => `^${value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`;
  const text = value => `    text: ${q(regex(value))}\n`;
  const visibleId = id => `- assertVisible:\n    id: ${q(id)}\n`;
  const absentId = id => `- assertNotVisible:\n    id: ${q(id)}\n`;
  const tapId = id => `- tapOn:\n    id: ${q(id)}\n`;
  const waitId = id => `- extendedWaitUntil:\n    visible:\n      id: ${q(id)}\n    timeout: 90000\n`;
  const scrollId = id => `- scrollUntilVisible:\n    element:\n      id: ${q(id)}\n    direction: DOWN\n    timeout: 15000\n    centerElement: true\n`;
  const identity = (actor, other) => waitId('account-scroll')
    + `- assertVisible:\n${text(actor.email)}- assertNotVisible:\n${text(other.email)}`
    + absentId('login-email') + absentId('login-password') + absentId('missions-list') + absentId('tab-profile')
    + absentId('tab-establishment-home') + absentId('tab-contracts')
    + visibleId('account-environment') + '- assertVisible: "Environnement TEST · votre compte de test"\n'
    + '- assertVisible: "Reprendre mon inscription"\n' + absentId('enter-demo')
    + absentId('onboarding-save') + absentId('onboarding-complete');
  // Runner first force-stops and verifies pidof is empty. No state is cleared.
  const restart = '- launchApp:\n    clearState: false\n- openLink: ' + q(EXPO_URL) + '\n';
  const signedOut = waitId('login-scroll') + absentId('account-scroll')
    + absentId('enter-demo') + '- assertVisible: "Environnement TEST"\n' + scrollId('login-email')
    + visibleId('login-email') + visibleId('login-password')
    + `- assertVisible:\n    id: "login-email"\n    text: ${q('^vous@exemple\\.fr$|^$')}\n`
    + '- assertVisible:\n    id: "login-password"\n    text: "^$"\n';
  const bootstrap = `- openLink: ${q(EXPO_URL)}\n- extendedWaitUntil:\n    visible: "Continue|Continuer|Pixel Launcher isn't responding"\n    timeout: 120000\n`
    + '- runFlow:\n    when:\n      visible: "Pixel Launcher isn\'t responding"\n    commands:\n      - tapOn: "Close app"\n      - assertNotVisible: "Pixel Launcher isn\'t responding"\n'
    + '- assertVisible: "Continue|Continuer"\n- waitForAnimationToEnd:\n    timeout: 10000\n'
    + '- tapOn: "Continue|Continuer"\n- extendedWaitUntil:\n    notVisible: "Continue|Continuer"\n    timeout: 15000\n'
    + '- extendedWaitUntil:\n    visible: "SDK version: 57.0.0"\n    timeout: 30000\n'
    + '- scrollUntilVisible:\n    element:\n      text: "Tools button"\n    direction: DOWN\n    timeout: 15000\n'
    + '- tapOn: "Tools button"\n- tapOn: "Close"\n- assertNotVisible: "SDK version: 57.0.0"\n- assertNotVisible: "^Tools$"\n';
  const result = [];
  const add = (phase, commands, restartProcess = false, capture = null) => result.push({ phase, restartProcess, capture,
    flow: `appId: host.exp.exponent\nname: Native Auth STAGING ${phase}\n---\n${commands}${capture ? `- takeScreenshot: ${capture}\n` : ''}` });
  add('initial_signed_out', bootstrap + signedOut);
  for (const [index, actor] of cohort.actors.entries()) {
    const other = cohort.actors[1 - index];
    add(`${actor.alias}_login`, tapId('login-email') + `- inputText: ${q(actor.email)}\n`
      + scrollId('login-password') + tapId('login-password') + `- inputText: ${q(actor.password)}\n- hideKeyboard\n`
      + scrollId('sign-in') + tapId('sign-in') + identity(actor, other), false, `auth-${actor.alias}-login`);
    add(`${actor.alias}_process_restart`, restart + identity(actor, other), true, `auth-${actor.alias}-restart`);
    add(`${actor.alias}_logout`, tapId('sign-out') + '- tapOn: "Quitter"\n' + signedOut);
    add(`${actor.alias}_logout_process_restart`, restart + signedOut
      + `- assertNotVisible:\n${text(actor.email)}- assertNotVisible:\n${text(other.email)}`, true);
  }
  return result;
}
