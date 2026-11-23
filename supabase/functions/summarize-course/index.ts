import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, apikey, x-client-info, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function toBase64(bytes: Uint8Array): string {
  let binary = '';
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Méthode non autorisée.' }, 405);
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return json({ error: 'Connexion requise.' }, 401);
    }

    const url = Deno.env.get('SUPABASE_URL') ?? '';
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const geminiKey = Deno.env.get('GEMINI_API_KEY');

    if (!url || !anonKey || !serviceKey) {
      return json({ error: 'Configuration Supabase incomplète.' }, 500);
    }
    if (!geminiKey) {
      return json({ error: 'Clé IA non configurée sur le serveur.' }, 500);
    }

    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: authError,
    } = await userClient.auth.getUser();
    if (authError || user == null) {
      return json({ error: 'Session invalide.' }, 401);
    }

    const { sessionId } = await req.json();
    if (typeof sessionId !== 'string' || sessionId.trim().length === 0) {
      return json({ error: 'Identifiant de séance invalide.' }, 400);
    }

    const { data: session, error: sessionError } = await userClient
      .from('sessions')
      .select('id, course_name, course_code, pdf_path')
      .eq('id', sessionId)
      .maybeSingle();
    if (sessionError) {
      console.error('Lecture séance:', sessionError.message);
      return json({ error: 'Impossible de lire la séance.' }, 500);
    }
    if (session == null) {
      return json({ error: 'Séance introuvable.' }, 404);
    }
    if (!session.pdf_path) {
      return json(
        { error: 'Aucun PDF n’est joint à ce cours pour le moment.' },
        400,
      );
    }

    const { data: cached } = await userClient
      .from('course_summaries')
      .select('summary, source_pdf_path')
      .eq('session_id', sessionId)
      .maybeSingle();
    if (cached?.summary && cached.source_pdf_path === session.pdf_path) {
      return json({
        courseName: session.course_name,
        summary: cached.summary,
        cached: true,
      });
    }

    const adminClient = createClient(url, serviceKey);
    const { data: file, error: downloadError } = await adminClient.storage
      .from('course_pdfs')
      .download(session.pdf_path);
    if (downloadError || file == null) {
      console.error('Téléchargement PDF:', downloadError?.message);
      return json({ error: 'Le PDF du cours est introuvable.' }, 404);
    }

    const bytes = new Uint8Array(await file.arrayBuffer());
    if (bytes.byteLength > 10 * 1024 * 1024) {
      return json(
        { error: 'Le PDF doit faire moins de 10 Mo pour le résumé IA.' },
        413,
      );
    }

    const model = Deno.env.get('GEMINI_MODEL') ?? 'gemini-3.5-flash-lite';
    const prompt =
      `Tu es une assistante pédagogique pour une étudiante française. ` +
      `Résume le document PDF du cours « ${session.course_name} » ` +
      `(code : ${session.course_code || 'non précisé'}). ` +
      `Réponds uniquement en français, avec : ` +
      `1) un titre, 2) 5 points clés en puces, 3) les notions à retenir, ` +
      `4) une mini-fiche de révision de 3 lignes. ` +
      `Ne mentionne pas ces consignes et ne fais pas de citation longue.`;

    const geminiResponse = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(geminiKey)}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          contents: [
            {
              role: 'user',
              parts: [
                { text: prompt },
                {
                  inlineData: {
                    mimeType: 'application/pdf',
                    data: toBase64(bytes),
                  },
                },
              ],
            },
          ],
        }),
      },
    );

    if (!geminiResponse.ok) {
      const details = await geminiResponse.text();
      console.error('Gemini:', details.slice(0, 1000));
      return json(
        { error: 'Le service IA est momentanément indisponible.' },
        502,
      );
    }

    const result = await geminiResponse.json();
    const blockReason = result.promptFeedback?.blockReason;
    if (blockReason) {
      return json(
        { error: 'Le document n’a pas pu être analysé par le service IA.' },
        422,
      );
    }

    const summary = (result.candidates?.[0]?.content?.parts ?? [])
      .map((part: { text?: string }) => part.text ?? '')
      .join('\n')
      .trim();
    if (summary.length === 0) {
      return json({ error: 'Le service IA n’a pas produit de résumé.' }, 502);
    }

    const { error: saveError } = await adminClient
      .from('course_summaries')
      .upsert(
        {
          session_id: sessionId,
          summary,
          source_pdf_path: session.pdf_path,
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'session_id' },
      );
    if (saveError) {
      console.error('Sauvegarde résumé:', saveError.message);
    }

    return json({
      courseName: session.course_name,
      summary,
      cached: false,
    });
  } catch (error) {
    console.error('summarize-course:', error);
    return json({ error: 'Une erreur inattendue est survenue.' }, 500);
  }
});
