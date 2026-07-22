import type { LucideIcon } from 'lucide-react';
import {
  Activity,
  AlertTriangle,
  Building2,
  CalendarDays,
  ClipboardList,
  Code2,
  Coins,
  CreditCard,
  FileCheck,
  FileSearch,
  FileSignature,
  FileStack,
  Flag,
  Flame,
  Gift,
  Home,
  Mail,
  Megaphone,
  MessageCircle,
  Rocket,
  Scale,
  Settings,
  Shield,
  ShieldCheck,
  Target,
  Trash2,
  TrendingUp,
  UserPlus,
  Users,
  Zap,
} from 'lucide-react';
import { ADMIN_ACCESS, type AdminAccessGroup } from '@/lib/adminAccess';

export interface AdminNavItem {
  icone: LucideIcon;
  label: string;
  route: string;
  acces: AdminAccessGroup;
}

export interface AdminNavGroup {
  id: 'pilotage' | 'acquisition' | 'operations' | 'comptes' | 'finances' | 'conformite' | 'plateforme';
  icone: LucideIcon;
  label: string;
  description: string;
  items: AdminNavItem[];
}

export interface AdminLegalItem {
  icone: LucideIcon;
  label: string;
  route: string;
}

const ACCES = ADMIN_ACCESS;

export const ADMIN_NAV_GROUPS: AdminNavGroup[] = [
  {
    id: 'pilotage',
    icone: Home,
    label: 'Pilotage',
    description: 'Priorités et stratégie',
    items: [
      { icone: Home, label: 'Quotidien', route: '/admin', acces: ACCES.DASHBOARD },
      { icone: Rocket, label: 'Vue dirigeante', route: '/admin/fondateur', acces: ACCES.FONDATEUR },
      { icone: Target, label: 'Lancement', route: '/admin/fondateur/lancement', acces: ACCES.FONDATEUR },
      { icone: TrendingUp, label: 'Cohortes', route: '/admin/cohort', acces: ACCES.FONDATEUR },
      { icone: UserPlus, label: 'Équipe', route: '/admin/fondateur/equipe', acces: ACCES.FONDATEUR },
      { icone: FileStack, label: 'Investisseurs', route: '/admin/fondateur/levee', acces: ACCES.FONDATEUR },
    ],
  },
  {
    id: 'acquisition',
    icone: Target,
    label: 'Acquisition',
    description: 'Besoins externes et prospects',
    items: [
      { icone: Megaphone, label: 'Marchés externes', route: '/admin/fondateur/acquisition', acces: ACCES.FONDATEUR },
      { icone: MessageCircle, label: 'Prospection & CRM', route: '/admin/fondateur/sales', acces: ACCES.FONDATEUR },
    ],
  },
  {
    id: 'operations',
    icone: ClipboardList,
    label: 'Opérations',
    description: 'Missions, planning et support',
    items: [
      { icone: ClipboardList, label: 'Missions', route: '/admin/missions', acces: ACCES.MISSIONS },
      { icone: CalendarDays, label: 'Calendrier mensuel', route: '/admin/calendrier', acces: ACCES.MISSIONS },
      { icone: CalendarDays, label: 'Planning par période', route: '/admin/planning-global', acces: ACCES.MISSIONS },
      { icone: Flame, label: 'Pool urgence', route: '/admin/pool-urgence', acces: ACCES.MISSIONS },
      { icone: AlertTriangle, label: 'Alertes de pointage', route: '/admin/alertes-pointage', acces: ACCES.MISSIONS },
      { icone: MessageCircle, label: 'Conversations', route: '/admin/messagerie', acces: ACCES.MESSAGERIE },
      { icone: Mail, label: 'Demandes du site', route: '/admin/messages-contact', acces: ACCES.MESSAGERIE },
    ],
  },
  {
    id: 'comptes',
    icone: Users,
    label: 'Comptes',
    description: 'Utilisateurs et contrôles',
    items: [
      { icone: Users, label: 'Utilisateurs', route: '/admin/utilisateurs', acces: ACCES.UTILISATEURS },
      { icone: ShieldCheck, label: 'Vérification établissements', route: '/admin/verification-etablissements', acces: ACCES.UTILISATEURS },
      { icone: FileSearch, label: 'Contrôles manuels', route: '/admin/revues-manuelles', acces: ACCES.UTILISATEURS },
      { icone: Shield, label: 'Documents & identité', route: '/admin/moderation', acces: ACCES.UTILISATEURS },
      { icone: Flag, label: 'Signalements', route: '/admin/signalements', acces: ACCES.UTILISATEURS },
      { icone: MessageCircle, label: 'Réclamations & scores', route: '/admin/reclamations', acces: ACCES.UTILISATEURS },
      { icone: Scale, label: 'Litiges & arbitrages', route: '/admin/litiges', acces: ACCES.LITIGES },
      { icone: FileCheck, label: 'Heures 3 200 h', route: '/admin/heures-externes', acces: ACCES.UTILISATEURS },
      { icone: Building2, label: 'Groupes de santé', route: '/admin/groupes', acces: ACCES.UTILISATEURS },
    ],
  },
  {
    id: 'finances',
    icone: Coins,
    label: 'Finances',
    description: 'Revenus, factures et paiements',
    items: [
      { icone: Coins, label: 'Pilotage financier', route: '/admin/finances', acces: ACCES.FINANCES },
      { icone: CreditCard, label: 'Facturation', route: '/admin/facturation', acces: ACCES.FINANCES },
      { icone: AlertTriangle, label: 'Factures impayées', route: '/admin/impayees', acces: ACCES.FINANCES },
      { icone: FileStack, label: 'Chorus Pro', route: '/admin/chorus-pro', acces: ACCES.FINANCES },
      { icone: FileCheck, label: 'Mandats de facturation', route: '/admin/mandats-facturation', acces: ACCES.FINANCES },
      { icone: Zap, label: 'Affacturage', route: '/admin/affacturage', acces: ACCES.FINANCES },
      { icone: Coins, label: 'Taux de commission', route: '/admin/taux-commission', acces: ACCES.FINANCES },
      { icone: Gift, label: 'Paliers BFA', route: '/admin/bfa', acces: ACCES.FINANCES },
    ],
  },
  {
    id: 'conformite',
    icone: Scale,
    label: 'Conformité',
    description: 'Risques, contrats et traçabilité',
    items: [
      { icone: ShieldCheck, label: 'Conformité', route: '/admin/conformite', acces: ACCES.TECHNIQUE },
      { icone: FileCheck, label: 'DPIA', route: '/admin/dpia', acces: ACCES.TECHNIQUE },
      { icone: Shield, label: 'Outils RGPD', route: '/admin/rgpd-tools', acces: ACCES.TECHNIQUE },
      { icone: Shield, label: 'Journaux', route: '/admin/audit', acces: ACCES.TECHNIQUE },
      { icone: Shield, label: 'Sécurité RLS', route: '/admin/audit-rls', acces: ACCES.TECHNIQUE },
      { icone: FileSignature, label: 'Contrats', route: '/admin/contrats', acces: ACCES.LITIGES },
      { icone: FileStack, label: 'Modèles', route: '/admin/templates-contrats', acces: ACCES.LITIGES },
    ],
  },
  {
    id: 'plateforme',
    icone: Settings,
    label: 'Plateforme',
    description: 'État et configuration',
    items: [
      { icone: Activity, label: 'État du système', route: '/admin/status', acces: ACCES.TECHNIQUE },
      { icone: Settings, label: 'Configuration', route: '/admin/config', acces: ACCES.TECHNIQUE },
      { icone: Mail, label: 'Emails', route: '/admin/emails', acces: ACCES.TECHNIQUE },
      { icone: Code2, label: 'API', route: '/admin/api', acces: ACCES.TECHNIQUE },
      { icone: Zap, label: 'Externalisations', route: '/admin/externalisations-actions', acces: ACCES.TECHNIQUE },
      { icone: Code2, label: 'Données démo', route: '/admin/demo', acces: ACCES.TECHNIQUE },
    ],
  },
];

export const ADMIN_LEGAL_ITEMS: AdminLegalItem[] = [
  { icone: ShieldCheck, label: 'Confidentialité', route: '/confidentialite' },
  { icone: Scale, label: 'CGU', route: '/cgu' },
  { icone: FileStack, label: 'Mentions légales', route: '/mentions-legales' },
  { icone: Trash2, label: 'Suppression du compte', route: '/supprimer-mon-compte' },
];

export const ADMIN_MOBILE_PRIMARY_GROUP_IDS = new Set<AdminNavGroup['id']>([
  'pilotage',
  'acquisition',
  'operations',
  'comptes',
]);

export function flattenAdminNavigation(groups: AdminNavGroup[]): AdminNavItem[] {
  return groups.flatMap((group) => group.items);
}
