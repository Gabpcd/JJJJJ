-- P1: template_version sur factures_honoraires
-- Permet de distinguer les factures v1 (ancien template jsPDF) des v2 (Factur-X CII)
ALTER TABLE public.factures_honoraires
  ADD COLUMN IF NOT EXISTS template_version TEXT NOT NULL DEFAULT 'v1';
