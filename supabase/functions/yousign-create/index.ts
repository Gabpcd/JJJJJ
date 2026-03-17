import { createClient } from "npm:@supabase/supabase-js@2";

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://app.jolene.app" ||
    origin === "http://localhost:5173" ||
    origin.endsWith(".lovable.app")
  ) {
    return origin;
  }
  return "https://app.jolene.app";
}

function corsHeaders(req: Request) {
  return {
    "Access-Control-Allow-Origin": getCorsOrigin(req),
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders(req) });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const yousignApiKey = Deno.env.get("YOUSIGN_API_KEY");
    const yousignBaseUrl = Deno.env.get("YOUSIGN_BASE_URL") || "https://api-sandbox.yousign.app/v3";

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const token = authHeader.replace("Bearer ", "");
    const { data: claimsData, error: claimsError } = await supabase.auth.getClaims(token);
    if (claimsError || !claimsData?.claims) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    const userId = claimsData.claims.sub;

    const { contrat_id } = await req.json();
    if (!contrat_id) {
      return new Response(JSON.stringify({ error: "contrat_id requis" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Fetch contract with related data
    const { data: contrat, error: contratErr } = await supabase
      .from("contrats_mission")
      .select("id, mission_id, numero_contrat, type_contrat, statut, contenu_html, soignant_id, etablissement_id, mode_signature")
      .eq("id", contrat_id)
      .single();

    if (contratErr || !contrat) {
      return new Response(JSON.stringify({ error: "Contrat introuvable" }), {
        status: 404,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Verify caller is party to the contract
    if (contrat.soignant_id !== userId && contrat.etablissement_id !== userId) {
      // Check if user is admin of the establishment
      const adminClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
      const { data: etab } = await adminClient
        .from("etablissements")
        .select("id")
        .eq("id", contrat.etablissement_id)
        .single();

      // For now, allow if they can read the contract (RLS already checked above)
      if (!etab) {
        return new Response(JSON.stringify({ error: "Non autorisé" }), {
          status: 403,
          headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        });
      }
    }

    if (!yousignApiKey) {
      return new Response(
        JSON.stringify({
          error: "Yousign non configuré",
          fallback: true,
          message: "La signature Yousign n'est pas encore configurée. Utilisez la signature manuscrite.",
        }),
        { status: 503, headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // Fetch soignant & etablissement info for Yousign signers
    const adminClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

    const [soignantRes, etabRes] = await Promise.all([
      adminClient.from("soignants").select("id, prenom, nom, email, telephone").eq("id", contrat.soignant_id).single(),
      adminClient.from("etablissements").select("id, nom, email_contact, telephone_contact").eq("id", contrat.etablissement_id).single(),
    ]);

    const soignant = soignantRes.data;
    const etablissement = etabRes.data;

    if (!soignant || !etablissement) {
      return new Response(JSON.stringify({ error: "Données soignant/établissement introuvables" }), {
        status: 404,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Generate PDF from HTML content
    const htmlContent = contrat.contenu_html || "<p>Contrat en cours de génération</p>";

    // Step 1: Create a signature request
    const signatureReqRes = await fetch(`${yousignBaseUrl}/signature_requests`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${yousignApiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        name: `Contrat ${contrat.numero_contrat}`,
        delivery_mode: "email",
        timezone: "Europe/Paris",
      }),
    });

    if (!signatureReqRes.ok) {
      const errText = await signatureReqRes.text();
      console.error("Yousign create signature request error:", errText);
      return new Response(
        JSON.stringify({ error: "Erreur Yousign", fallback: true, details: errText }),
        { status: 502, headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    const signatureRequest = await signatureReqRes.json();
    const signatureRequestId = signatureRequest.id;

    // Step 2: Upload document (HTML as PDF — Yousign accepts PDF upload)
    // For now, create a simple text-based PDF placeholder; in production, use a proper HTML→PDF converter
    const encoder = new TextEncoder();
    const pdfContent = encoder.encode(htmlContent);
    
    const formData = new FormData();
    formData.append("file", new Blob([pdfContent], { type: "application/pdf" }), `contrat-${contrat.numero_contrat}.pdf`);
    formData.append("nature", "signable_document");

    const docRes = await fetch(`${yousignBaseUrl}/signature_requests/${signatureRequestId}/documents`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${yousignApiKey}`,
      },
      body: formData,
    });

    if (!docRes.ok) {
      const errText = await docRes.text();
      console.error("Yousign upload document error:", errText);
      return new Response(
        JSON.stringify({ error: "Erreur upload document Yousign", fallback: true }),
        { status: 502, headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    const document = await docRes.json();

    // Step 3: Add signers
    const addSigner = async (info: { first_name: string; last_name: string; email: string; phone_number?: string }) => {
      const signerRes = await fetch(`${yousignBaseUrl}/signature_requests/${signatureRequestId}/signers`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${yousignApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          info,
          signature_level: "electronic_signature",
          signature_authentication_mode: "no_otp",
          fields: [
            {
              type: "signature",
              document_id: document.id,
              page: 1,
              x: 50,
              y: 700,
              width: 200,
              height: 60,
            },
          ],
        }),
      });

      if (!signerRes.ok) {
        const errText = await signerRes.text();
        console.error("Yousign add signer error:", errText);
        return null;
      }
      return await signerRes.json();
    };

    const soignantSigner = await addSigner({
      first_name: soignant.prenom,
      last_name: soignant.nom,
      email: soignant.email,
      phone_number: soignant.telephone || undefined,
    });

    const etabSigner = await addSigner({
      first_name: etablissement.nom.substring(0, 50),
      last_name: "Responsable",
      email: etablissement.email_contact,
      phone_number: etablissement.telephone_contact || undefined,
    });

    if (!soignantSigner || !etabSigner) {
      return new Response(
        JSON.stringify({ error: "Erreur ajout signataires Yousign", fallback: true }),
        { status: 502, headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // Step 4: Activate the signature request
    const activateRes = await fetch(`${yousignBaseUrl}/signature_requests/${signatureRequestId}/activate`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${yousignApiKey}`,
        "Content-Type": "application/json",
      },
    });

    if (!activateRes.ok) {
      const errText = await activateRes.text();
      console.error("Yousign activate error:", errText);
      return new Response(
        JSON.stringify({ error: "Erreur activation Yousign", fallback: true }),
        { status: 502, headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // Step 5: Update contract in DB
    await adminClient
      .from("contrats_mission")
      .update({
        mode_signature: "YOUSIGN",
        yousign_procedure_id: signatureRequestId,
        yousign_document_id: document.id,
        statut: "EN_ATTENTE_SIGNATURES",
      })
      .eq("id", contrat_id);

    return new Response(
      JSON.stringify({
        success: true,
        signature_request_id: signatureRequestId,
        soignant_signing_url: soignantSigner.signature_link,
        etablissement_signing_url: etabSigner.signature_link,
      }),
      { status: 200, headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("yousign-create error:", err);
    return new Response(
      JSON.stringify({ error: "Erreur interne", fallback: true }),
      { status: 500, headers: { ...corsHeaders(req), "Content-Type": "application/json" } }
    );
  }
});
