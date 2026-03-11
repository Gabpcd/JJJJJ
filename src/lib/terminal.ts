export function genererIdTerminal(): string {
  const raw = [
    navigator.userAgent,
    screen.width, screen.height, screen.colorDepth,
    navigator.language,
    new Date().getTimezoneOffset(),
  ].join('|');
  let hash = 0;
  for (let i = 0; i < raw.length; i++) {
    const char = raw.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash |= 0;
  }
  return `TERM_${Math.abs(hash).toString(36)}`;
}
