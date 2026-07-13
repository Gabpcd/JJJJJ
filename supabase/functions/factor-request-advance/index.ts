// Edge function : factor-request-advance
// Demande une avance d'affacturage pour une facture d'honoraires.
// Provider par défaut : Defacto. L'architecture est extensible (Aria, Hero, etc.)
// via la variable FACTOR_PROVIDER.
//
// Configuration requise (secrets Supabase) :
//   FACTOR_PROVIDER=defacto             (par défaut)
//   FACTOR_ENVIRONMENT=sandbox|production
//   DEFACTO_API_KEY=<clé API fournie par Defacto>
//   DEFACTO_API_URL=https://api.defacto.com  (à confirmer avec Defacto)
//   FACTOR_MARGE_JOLENE=0.5             (% de marge ajoutée par Jolene au taux Defacto)

import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

// Interface générique provider
interface FactorProvider {
  name: string;
  submitInvoice(invoice: InvoiceData): Promise<FactorResponse>;
}

interface InvoiceData {
  invoice_number: string;
  invoice_date: string;
  due_date: string;
  amount_ttc: number;
  currency: string;
  // Émetteur (le soignant)
  seller: {
    name: string;
    siren?: string;
    rpps?: string;
    email?: string;
    iban?: string;
  };
  // Débiteur (l'établissement)
  debtor: {
    name: string;
    siret?: string;
    address?: string;
    email?: string;
  };
  description: string;
}

interface FactorResponse {
  success: boolean;
  provider_advance_id?: string;
  provider_invoice_id?: string;
  status: "DEMANDEE" | "EN_ANALYSE" | "APPROUVEE" | "REJETEE";
  fee_amount?: number;
  fee_rate?: number;
  net_amount?: number;
  rejection_reason?: string;
  raw_response?: unknown;
}

// === Adapter Defacto ===
// NOTE : Les endpoints et la structure exacte sont à confirmer avec la doc Defacto.
// Cette implémentation suit les patterns RESTful standard des factors marketplace.
class DefactoProvider implements FactorProvider {
  name = "defacto";
  apiKey: string;
  apiUrl: string;

  constructor(apiKey: string, apiUrl: string) {
    this.apiKey = apiKey;
    this.apiUrl = apiUrl;
  }

  async submitInvoice(invoice: InvoiceData): Promise<FactorResponse> {
    try {
      const res = await fetch(`${this.apiUrl}/v1/invoices`, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${this.apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          external_id: invoice.invoice_number,
          invoice_date: invoice.invoice_date,
          due_date: invoice.due_date,
          amount: Math.round(invoice.amount_ttc * 100), // en centimes
          currency: invoice.currency,
          description: invoice.description,
          seller: {
            name: invoice.seller.name,
            tax_id: invoice.seller.siren,
            professional_id: invoice.seller.rpps,
            email: invoice.seller.email,
            iban: invoice.seller.iban,
          },
          debtor: {
            name: invoice.debtor.name,
            tax_id: invoice.debtor.siret,
            address: invoice.debtor.address,
            email: invoice.debtor.email,
          },
        }),
      });

      const data = await res.json();

      if (!res.ok) {
        return {
          success: false,
          status: "REJETEE",
          rejection_reason: data.error || `HTTP ${res.status}`,
          raw_response: data,
        };
      }

      return {
        success: true,
        provider_advance_id: data.id,
        provider_invoice_id: data.invoice_id || data.id,
        status: this.mapStatus(data.status),
        fee_amount: data.fee_amount ? data.fee_amount / 100 : undefined,
        fee_rate: data.fee_rate,
        net_amount: data.net_amount ? data.net_amount / 100 : undefined,
        raw_response: data,
      };
    } catch (err) {
      return {
        success: false,
        status: "REJETEE",
        rejection_reason: err instanceof Error ? err.message : "Erreur réseau",
      };
    }
  }

  private mapStatus(status: string): "DEMANDEE" | "EN_ANALYSE" | "APPROUVEE" | "REJETEE" {
    const s = (status || "").toLowerCase();
    if (s.includes("approved") || s.includes("financed")) return "APPROUVEE";
    if (s.includes("reject") || s.includes("declined")) return "REJETEE";
    if (s.includes("review") || s.includes("analys")) return "EN_ANALYSE";
    return "DEMANDEE";
  }
}

function getProvider(): FactorProvider | null {
  const provider = (Deno.env.get("FACTOR_PROVIDER") || "defacto").toLowerCase();
  if (provider === "defacto") {
    const apiKey = Deno.env.get("DEFACTO_API_KEY");
    const apiUrl = Deno.env.get("DEFACTO_API_URL") || "https://api.defacto.com";
    if (!apiKey) return null;
    return new DefactoProvider(apiKey, apiUrl);
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), { status: 401, headers: corsHeaders(req) });
    }

    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? ""
    );
    const { data: { user }, error: authErr } = await supabaseClient.auth.getUser(authHeader.replace("Bearer ", ""));
    if (authErr || !user) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), { status: 401, headers: corsHeaders(req) });
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } }
    );

    const body = await req.json();
    const factureId = body.facture_honoraire_id;
    if (!factureId) {
      return new Response(JSON.stringify({ error: "facture_honoraire_id requis" }), { status: 400, headers: corsHeaders(req) });
    }

    // Vérifier la facture
    const { data: facture } = await supabaseAdmin
      .from("factures_honoraires")
      .select("*")
      .eq("id", factureId)
      .eq("soignant_id", user.id)
      .maybeSingle();

    if (!facture) {
      return new Response(JSON.stringify({ error: "Facture introuvable" }), { status: 404, headers: corsHeaders(req) });
    }

    if (facture.statut !== "EMISE" && facture.statut !== "EN_RETARD") {
      return new Response(JSON.stringify({ error: "Cette facture n'est pas éligible à l'affacturage" }), { status: 400, headers: corsHeaders(req) });
    }

    // Vérifier qu'il n'y a pas déjà une avance en cours
    const { data: existing } = await supabaseAdmin
      .from("factor_advances")
      .select("id, statut")
      .eq("facture_honoraire_id", factureId)
      .maybeSingle();

    if (existing && !["REJETEE", "ANNULEE"].includes(existing.statut)) {
      return new Response(JSON.stringify({ error: "Une demande d'avance existe déjà pour cette facture", advance_id: existing.id }), { status: 400, headers: corsHeaders(req) });
    }

    // Récupérer les infos soignant + établissement
    const [{ data: sg }, { data: etab }, { data: mission }] = await Promise.all([
      supabaseAdmin.from("soignants").select("prenom, nom, profession, numero_rpps, email, iban").eq("id", facture.soignant_id).maybeSingle(),
      supabaseAdmin.from("etablissements").select("nom, siret, email_contact, adresse_ligne1, adresse_code_postal, adresse_ville").eq("id", facture.etablissement_id).maybeSingle(),
      facture.mission_id ? supabaseAdmin.from("missions").select("intitule").eq("id", facture.mission_id).maybeSingle() : Promise.resolve({ data: null }),
    ]);

    if (!sg || !etab) {
      return new Response(JSON.stringify({ error: "Données soignant ou établissement manquantes" }), { status: 400, headers: corsHeaders(req) });
    }

    const provider = getProvider();
    if (!provider) {
      // Mode "non configuré" : créer la demande en attente, sans appeler l'API
      const { data: advance } = await supabaseAdmin
        .from("factor_advances")
        .insert({
          facture_honoraire_id: factureId,
          soignant_id: facture.soignant_id,
          etablissement_id: facture.etablissement_id,
          mission_id: facture.mission_id,
          provider: "defacto",
          montant_facture_ttc: facture.montant_ttc,
          statut: "DEMANDEE",
        })
        .select()
        .single();

      return new Response(JSON.stringify({
        success: true,
        configured: false,
        message: "Demande enregistrée. L'affacturage sera traité dès que l'intégration Defacto sera activée.",
        advance,
      }), { status: 200, headers: corsHeaders(req) });
    }

    // Appel à l'API factor
    const factorRes = await provider.submitInvoice({
      invoice_number: facture.numero_facture,
      invoice_date: facture.date_emission,
      due_date: facture.date_echeance,
      amount_ttc: Number(facture.montant_ttc),
      currency: "EUR",
      description: mission?.intitule || `Mission Jolene ${facture.numero_facture}`,
      seller: {
        name: `${sg.prenom} ${sg.nom}`,
        rpps: sg.numero_rpps,
        email: sg.email,
        iban: sg.iban,
      },
      debtor: {
        name: etab.nom,
        siret: etab.siret,
        address: [etab.adresse_ligne1, etab.adresse_code_postal, etab.adresse_ville].filter(Boolean).join(", "),
        email: etab.email_contact,
      },
    });

    // Calcul marge Jolene
    const margeJolenePct = parseFloat(Deno.env.get("FACTOR_MARGE_JOLENE") || "0.5");
    const fraisJolene = factorRes.success ? Math.round(Number(facture.montant_ttc) * margeJolenePct / 100 * 100) / 100 : 0;
    const netSoignant = factorRes.success && factorRes.net_amount ? factorRes.net_amount - fraisJolene : null;

    // Insérer ou mettre à jour la demande
    const advanceData = {
      facture_honoraire_id: factureId,
      soignant_id: facture.soignant_id,
      etablissement_id: facture.etablissement_id,
      mission_id: facture.mission_id,
      provider: provider.name,
      provider_advance_id: factorRes.provider_advance_id,
      provider_invoice_id: factorRes.provider_invoice_id,
      montant_facture_ttc: facture.montant_ttc,
      frais_factor: factorRes.fee_amount,
      frais_jolene: fraisJolene,
      montant_net_soignant: netSoignant,
      statut: factorRes.status,
      motif_rejet: factorRes.rejection_reason,
      raw_response: factorRes.raw_response as any,
      ...(factorRes.status === "APPROUVEE" ? { approuvee_le: new Date().toISOString() } : {}),
    };

    let advanceId: string;
    if (existing) {
      const { data: updated } = await supabaseAdmin
        .from("factor_advances")
        .update(advanceData)
        .eq("id", existing.id)
        .select("id")
        .single();
      advanceId = updated!.id;
    } else {
      const { data: inserted } = await supabaseAdmin
        .from("factor_advances")
        .insert(advanceData)
        .select("id")
        .single();
      advanceId = inserted!.id;
    }

    return new Response(JSON.stringify({
      success: factorRes.success,
      advance_id: advanceId,
      statut: factorRes.status,
      net_soignant: netSoignant,
      frais_factor: factorRes.fee_amount,
      frais_jolene: fraisJolene,
      message: factorRes.success
        ? `Demande envoyée à ${provider.name}. Statut : ${factorRes.status}`
        : factorRes.rejection_reason,
    }), { status: 200, headers: corsHeaders(req) });
  } catch (err: unknown) {
    console.error("factor-request-advance error:", err);
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : "Erreur interne" }), { status: 500, headers: corsHeaders(req) });
  }
});
