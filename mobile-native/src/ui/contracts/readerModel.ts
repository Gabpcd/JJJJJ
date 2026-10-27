import { parse, type DefaultTreeAdapterMap } from 'parse5';

type Node = DefaultTreeAdapterMap['childNode'];
type Element = DefaultTreeAdapterMap['element'];
export interface ContractRun { text: string; bold: boolean; italic: boolean }
export interface ContractBlock { kind: 'h1' | 'h2' | 'paragraph' | 'pre' | 'notice'; runs: ContractRun[] }
export type NativeContractDocument = { supported: true; title: string; blocks: ContractBlock[] }
  | { supported: false; reason: string };

// Exact stylesheet emitted by generate-contrat-mission-pdf.wrapInDocument.
// The native renderer implements its semantic formatting, not arbitrary CSS.
export const CONTRACT_WRAPPER_CSS = `
  body { font-family: 'Helvetica Neue', Arial, sans-serif; color: #0f172a; line-height: 1.6; padding: 40px; max-width: 900px; margin: 0 auto; }
  h1 { color: #d6336c; font-size: 22px; border-bottom: 2px solid #fce7f3; padding-bottom: 8px; }
  h2 { color: #4b1d3a; font-size: 16px; margin-top: 24px; }
  p { margin: 8px 0; }
  strong { color: #1e293b; }
  em { color: #64748b; font-size: 12px; }
  .header-mention { background: #fef3f7; border-left: 4px solid #d6336c; padding: 12px 16px; margin-bottom: 24px; font-size: 13px; }
`;
const compactCss = (value: string) => value.replace(/\s+/g, ' ').trim();
const MAX_HTML_CHARACTERS = 1_000_000, MAX_NODES = 10_000, MAX_DEPTH = 32;
const unsupported = () => { throw new Error('unsupported'); };
const isElement = (node: Node): node is Element => 'tagName' in node;
const isWhitespace = (node: Node) => node.nodeName === '#text' && !/[^\t\n\f\r ]/.test((node as DefaultTreeAdapterMap['textNode']).value);
function attrs(element: Element, allowed: Record<string, (value: string) => boolean> = {}) {
  if (element.namespaceURI !== 'http://www.w3.org/1999/xhtml') unsupported();
  for (const attr of element.attrs) if (attr.namespace || attr.prefix || !allowed[attr.name]?.(attr.value)) unsupported();
}
function textOnly(element: Element): string {
  return element.childNodes.map(node => {
    if (node.nodeName !== '#text') return unsupported();
    return (node as DefaultTreeAdapterMap['textNode']).value;
  }).join('');
}

/** Parses the verified original. It never rewrites, rehashes or partially sanitizes it. */
export function parseNativeContract(html: string): NativeContractDocument {
  try {
    if (!html || html.length > MAX_HTML_CHARACTERS || /\u0000/.test(html)) unsupported();
    const errors: string[] = [];
    const tree = parse(html, { sourceCodeLocationInfo: true, scriptingEnabled: false,
      onParseError: error => { errors.push(error.code); } });
    if (errors.length) unsupported();
    const roots = tree.childNodes.filter(node => !isWhitespace(node));
    if (roots.length !== 2 || roots[0].nodeName !== '#documentType' || !isElement(roots[1]) || roots[1].tagName !== 'html') unsupported();
    const doctype = roots[0] as DefaultTreeAdapterMap['documentType'];
    if (doctype.name !== 'html' || doctype.publicId || doctype.systemId) unsupported();
    const root = roots[1] as Element; attrs(root, { lang: value => value.toLowerCase() === 'fr' });
    const parts = root.childNodes.filter(node => !isWhitespace(node));
    if (parts.length !== 2 || !isElement(parts[0]) || parts[0].tagName !== 'head' || !isElement(parts[1]) || parts[1].tagName !== 'body') unsupported();
    const head = parts[0] as Element, body = parts[1] as Element;
    if (!head.sourceCodeLocation || !body.sourceCodeLocation) unsupported();
    attrs(head); attrs(body);
    let title = '', styleSeen = false, titleSeen = false, metaSeen = false;
    for (const node of head.childNodes) {
      if (isWhitespace(node)) continue;
      if (!isElement(node)) unsupported();
      const element = node as Element;
      if (element.tagName === 'meta') {
        attrs(element, { charset: value => value.toLowerCase() === 'utf-8' });
        if (metaSeen || element.attrs.length !== 1) unsupported(); metaSeen = true;
      } else if (element.tagName === 'title') {
        attrs(element); if (titleSeen) unsupported(); titleSeen = true; title = textOnly(element);
      } else if (element.tagName === 'style') {
        attrs(element); if (styleSeen || compactCss(textOnly(element)) !== compactCss(CONTRACT_WRAPPER_CSS)) unsupported(); styleSeen = true;
      } else unsupported();
    }
    if (!metaSeen || !titleSeen || !styleSeen) unsupported();
    let count = 0;
    const visit = (depth: number) => { if (++count > MAX_NODES || depth > MAX_DEPTH) unsupported(); };
    const inline = (nodes: Node[], pre: boolean, depth: number): ContractRun[] => {
      const result: ContractRun[] = [];
      const add = (value: string, bold: boolean, italic: boolean) => {
        // HTML collapses ASCII whitespace only. NBSP and all significant pre-wrap
        // characters survive. Never trim each inline node: that merges words.
        let text = pre ? value : value.replace(/[\t\n\f\r ]+/g, ' ');
        if (!pre && result.at(-1)?.text.endsWith(' ') && text.startsWith(' ')) text = text.slice(1);
        if (!text) return;
        const last = result.at(-1);
        if (last && last.bold === bold && last.italic === italic) last.text += text;
        else result.push({ text, bold, italic });
      };
      const walk = (items: Node[], bold: boolean, italic: boolean, level: number) => {
        for (const node of items) {
          visit(level);
          if (node.nodeName === '#text') { add((node as DefaultTreeAdapterMap['textNode']).value, bold, italic); continue; }
          if (!isElement(node)) unsupported();
          const element = node as Element; attrs(element);
          if (element.tagName === 'br') result.push({ text: '\n', bold, italic });
          else if (element.tagName === 'strong') walk(element.childNodes, true, italic, level + 1);
          else if (element.tagName === 'em') walk(element.childNodes, bold, true, level + 1);
          else unsupported(); // Links/images/tables/lists are never silently dropped.
        }
      };
      walk(nodes, false, false, depth); return result;
    };
    const blocks: ContractBlock[] = [];
    const walkBlocks = (nodes: Node[], depth: number) => {
      for (const node of nodes) {
        visit(depth); if (isWhitespace(node)) continue;
        if (node.nodeName === '#text') { blocks.push({ kind: 'paragraph', runs: inline([node], false, depth + 1) }); continue; }
        if (!isElement(node)) unsupported();
        const element = node as Element;
        if (element.tagName === 'section') {
          attrs(element, { 'data-jolene-cdd': value => value === 'employeur-v1',
            'data-cadre': value => ['PRIVE_TERME_PRECIS', 'TEXTE_EMPLOYEUR'].includes(value),
            'data-auteur': value => !!value, 'data-prepare-le': value => Number.isFinite(Date.parse(value)) });
          walkBlocks(element.childNodes, depth + 1);
        } else if (element.tagName === 'article') {
          attrs(element, { style: value => value.replace(/\s/g, '').replace(/;$/, '') === 'white-space:pre-wrap;overflow-wrap:anywhere' });
          if (element.attrs.length !== 1) unsupported();
          blocks.push({ kind: 'pre', runs: inline(element.childNodes, true, depth + 1) });
        } else if (element.tagName === 'div') {
          attrs(element, { class: value => value === 'header-mention' });
          if (element.attrs.length !== 1) unsupported();
          blocks.push({ kind: 'notice', runs: inline(element.childNodes, false, depth + 1) });
        } else if (['h1', 'h2', 'p'].includes(element.tagName)) {
          attrs(element); blocks.push({ kind: element.tagName === 'p' ? 'paragraph' : element.tagName as 'h1' | 'h2',
            runs: inline(element.childNodes, false, depth + 1) });
        } else unsupported();
      }
    };
    walkBlocks(body.childNodes, 0);
    if (!blocks.length || !blocks.some(block => block.runs.some(run => run.text.trim()))) unsupported();
    return { supported: true, title, blocks };
  } catch {
    return { supported: false, reason: 'Ce contrat utilise une mise en forme que le lecteur natif ne peut pas restituer intégralement. La signature reste indisponible ici.' };
  }
}
