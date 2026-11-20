import type { Plugin } from 'vite';

export const FICHIER_SQUELETTE: string;
export function squeletteApplication(shell: string): string;
export function ecrireSquelette(dist: string): void;
export function estRequeteDePage(methode: string | undefined, accept: string | undefined): boolean;
export function cibleStatique(dist: string, url: string | undefined): string | null;
export function pagesStatiquesJolene(options: { dist: string; natif?: boolean }): Plugin;
