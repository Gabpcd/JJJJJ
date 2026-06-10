// Sitemap XML dynamique des missions ouvertes (Google for Jobs / indexation).
// GET public — référencé dans robots.txt :
// Sitemap: https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/sitemap-missions

import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async () => {
  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );
    const { data, error } = await admin.rpc("fn_missions_ouvertes_sitemap");
    if (error) return new Response(error.message, { status: 500 });

    const urls = ((data as any[]) || [])
      .map((m) =>
        `  <url>\n    <loc>https://jolene.app/mission/${m.id}</loc>\n    <lastmod>${new Date(m.maj).toISOString().slice(0, 10)}</lastmod>\n    <changefreq>daily</changefreq>\n  </url>`
      )
      .join("\n");

    const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>`;

    return new Response(xml, {
      headers: {
        "Content-Type": "application/xml; charset=utf-8",
        "Cache-Control": "public, max-age=3600",
      },
    });
  } catch (e) {
    return new Response((e as Error)?.message || "erreur", { status: 500 });
  }
});
