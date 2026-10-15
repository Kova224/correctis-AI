// =============================================================================
// Edge Function : send-invitation-email
// =============================================================================
// Envoie un email d'invitation à un enseignant pour rejoindre un établissement.
//
// Input  : { invitation_id: string }
// Output : { ok: true, email_id: string } | { error: string }
//
// La fonction :
//   1. Vérifie que l'appelant est authentifié et admin de l'établissement
//   2. Récupère l'invitation + nom de l'école + nom de l'admin
//   3. Envoie l'email via Resend (https://resend.com)
//   4. Le mail contient un lien `correctis://invite?token=XXX` qui déclenche
//      le deep-link côté Flutter pour acceptation immédiate.
//
// Secrets requis dans Supabase (Dashboard > Settings > Edge Functions) :
//   • RESEND_API_KEY     — clé API Resend (https://resend.com/api-keys)
//   • RESEND_FROM_EMAIL  — adresse expéditeur vérifiée (ex: "Correctis <noreply@correctis.app>")
//   • APP_PUBLIC_URL     — URL web de fallback (ex: "https://correctis.app")
//   • SUPABASE_URL       — auto-injecté par Supabase
//   • SUPABASE_SERVICE_ROLE_KEY — auto-injecté
// =============================================================================

import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const RESEND_FROM_EMAIL =
  Deno.env.get("RESEND_FROM_EMAIL") ?? "Correctis <noreply@correctis.app>";
const APP_PUBLIC_URL =
  Deno.env.get("APP_PUBLIC_URL") ?? "https://correctis.app";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function escapeHtml(s: string): string {
  return s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

interface InvitationRow {
  id: string;
  establishment_id: string;
  email: string;
  matiere: string | null;
  classes: string[] | null;
  token: string;
  invited_by: string;
  expires_at: string;
  accepted_at: string | null;
}

interface EstablishmentRow {
  id: string;
  name: string;
  city: string | null;
}

interface ProfileRow {
  display_name: string | null;
  email: string | null;
}

async function loadContext(
  admin: SupabaseClient,
  invitationId: string,
): Promise<{
  invitation: InvitationRow;
  establishment: EstablishmentRow;
  inviter: ProfileRow | null;
}> {
  const { data: invRow, error: invErr } = await admin
    .from("establishment_invitations")
    .select("*")
    .eq("id", invitationId)
    .single();
  if (invErr || !invRow) {
    throw new Error("Invitation introuvable.");
  }
  const invitation = invRow as InvitationRow;

  const { data: estabRow, error: estabErr } = await admin
    .from("establishments")
    .select("id, name, city")
    .eq("id", invitation.establishment_id)
    .single();
  if (estabErr || !estabRow) {
    throw new Error("Établissement introuvable.");
  }

  const { data: profile } = await admin
    .from("profiles")
    .select("display_name, email")
    .eq("id", invitation.invited_by)
    .maybeSingle();

  return {
    invitation,
    establishment: estabRow as EstablishmentRow,
    inviter: (profile as ProfileRow | null) ?? null,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Templating HTML
// ─────────────────────────────────────────────────────────────────────────────

function buildEmail(args: {
  establishmentName: string;
  inviterName: string;
  matiere: string | null;
  classes: string[];
  deepLink: string;
  webFallback: string;
  expiresAt: Date;
}): { subject: string; html: string; text: string } {
  const subject = `${args.inviterName} vous invite à rejoindre ${args.establishmentName} sur Correctis`;
  const expiresText = args.expiresAt.toLocaleString("fr-FR", {
    dateStyle: "long",
    timeStyle: "short",
    timeZone: "Africa/Tunis",
  });

  const matiereLine = args.matiere
    ? `<p style="margin:6px 0;color:#94a3b8;font-size:14px">Matière : <strong style="color:#e2e8f0">${escapeHtml(args.matiere)}</strong></p>`
    : "";
  const classesLine = args.classes.length > 0
    ? `<p style="margin:6px 0;color:#94a3b8;font-size:14px">Classes : <strong style="color:#e2e8f0">${escapeHtml(args.classes.join(", "))}</strong></p>`
    : "";

  const html = `<!DOCTYPE html>
<html lang="fr">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${escapeHtml(subject)}</title>
  </head>
  <body style="margin:0;padding:0;background:#0b0a17;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;color:#e2e8f0">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0b0a17;padding:40px 16px">
      <tr>
        <td align="center">
          <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width:560px;background:#16142e;border:1px solid rgba(167,139,250,0.18);border-radius:18px;overflow:hidden">
            <tr>
              <td style="padding:32px 32px 0;text-align:left">
                <div style="display:inline-block;padding:6px 10px;background:rgba(167,139,250,0.12);border:1px solid rgba(167,139,250,0.35);border-radius:999px;font-size:10px;letter-spacing:2px;color:#a78bfa;font-family:'SF Mono',Menlo,Consolas,monospace">
                  CORRECTIS · INVITATION
                </div>
                <h1 style="margin:18px 0 6px;font-size:24px;font-weight:700;color:#f8fafc;line-height:1.3;font-family:Georgia,'Times New Roman',serif">
                  Vous êtes invité à rejoindre<br/>
                  <span style="color:#a78bfa">${escapeHtml(args.establishmentName)}</span>
                </h1>
                <p style="margin:0 0 18px;color:#94a3b8;font-size:14px;line-height:1.6">
                  ${escapeHtml(args.inviterName)} vous invite à rejoindre son établissement sur <strong style="color:#e2e8f0">Correctis</strong> — l'application qui corrige vos copies en quelques secondes grâce à l'IA.
                </p>
                ${matiereLine}
                ${classesLine}
              </td>
            </tr>
            <tr>
              <td style="padding:24px 32px;text-align:center">
                <a href="${escapeHtml(args.deepLink)}" style="display:inline-block;padding:14px 28px;background:linear-gradient(135deg,#6d28d9 0%,#3b82f6 100%);color:#ffffff;text-decoration:none;border-radius:999px;font-weight:600;font-size:13px;letter-spacing:1.5px">
                  ACCEPTER L'INVITATION
                </a>
                <p style="margin:14px 0 0;color:#64748b;font-size:11px">
                  Ce lien ouvre directement l'application Correctis sur votre téléphone.
                </p>
              </td>
            </tr>
            <tr>
              <td style="padding:0 32px 24px">
                <div style="height:1px;background:rgba(167,139,250,0.18);margin:8px 0 20px"></div>
                <p style="margin:0 0 8px;color:#94a3b8;font-size:12px;line-height:1.6">
                  <strong style="color:#e2e8f0">L'application n'est pas installée ?</strong><br/>
                  Téléchargez Correctis puis ouvrez le lien ci-dessous :
                </p>
                <p style="margin:0 0 6px;font-family:'SF Mono',Menlo,Consolas,monospace;font-size:11px;color:#a78bfa;word-break:break-all">
                  <a href="${escapeHtml(args.webFallback)}" style="color:#a78bfa;text-decoration:none">${escapeHtml(args.webFallback)}</a>
                </p>
              </td>
            </tr>
            <tr>
              <td style="padding:18px 32px 28px;border-top:1px solid rgba(255,255,255,0.06);background:rgba(0,0,0,0.18)">
                <p style="margin:0;color:#64748b;font-size:11px;line-height:1.6">
                  Ce lien est valable jusqu'au <strong style="color:#94a3b8">${escapeHtml(expiresText)}</strong> (48&nbsp;heures).<br/>
                  Si vous n'attendiez pas cette invitation, vous pouvez ignorer ce message en toute sécurité.
                </p>
              </td>
            </tr>
          </table>
          <p style="margin:18px 0 0;color:#475569;font-size:10px;letter-spacing:1px;font-family:'SF Mono',Menlo,Consolas,monospace">
            CORRECTIS · TUNIS
          </p>
        </td>
      </tr>
    </table>
  </body>
</html>`;

  const text = `${args.inviterName} vous invite à rejoindre ${args.establishmentName} sur Correctis.

${args.matiere ? `Matière : ${args.matiere}\n` : ""}${args.classes.length > 0 ? `Classes : ${args.classes.join(", ")}\n` : ""}
Acceptez l'invitation en ouvrant ce lien sur votre téléphone :
${args.deepLink}

Si l'application n'est pas installée, téléchargez Correctis puis ouvrez :
${args.webFallback}

Ce lien expire le ${expiresText} (48 heures).
`;

  return { subject, html, text };
}

// ─────────────────────────────────────────────────────────────────────────────
// Resend
// ─────────────────────────────────────────────────────────────────────────────

async function sendViaResend(args: {
  to: string;
  subject: string;
  html: string;
  text: string;
}): Promise<string> {
  if (!RESEND_API_KEY) {
    throw new Error(
      "RESEND_API_KEY manquant. Ajoutez-le dans Supabase Settings > Edge Functions > Secrets.",
    );
  }
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: RESEND_FROM_EMAIL,
      to: [args.to],
      subject: args.subject,
      html: args.html,
      text: args.text,
    }),
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Resend ${res.status}: ${errText}`);
  }
  const data = await res.json();
  return (data?.id as string) ?? "";
}

// ─────────────────────────────────────────────────────────────────────────────
// Handler
// ─────────────────────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Méthode non autorisée." }, 405);
  }

  try {
    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      throw new Error("Configuration Supabase manquante.");
    }

    // 1. Authentification : on lit le JWT du caller pour vérifier qu'il est admin
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return jsonResponse({ error: "Non authentifié." }, 401);
    }

    // Client "anon" pour valider le JWT du caller
    const callerClient = createClient(
      SUPABASE_URL,
      SUPABASE_SERVICE_ROLE_KEY,
      {
        global: { headers: { Authorization: authHeader } },
      },
    );
    const {
      data: { user: caller },
    } = await callerClient.auth.getUser();
    if (!caller) {
      return jsonResponse({ error: "Session invalide." }, 401);
    }

    // 2. Lecture des paramètres
    const body = await req.json().catch(() => ({}));
    const invitationId = body?.invitation_id as string | undefined;
    if (!invitationId) {
      return jsonResponse({ error: "invitation_id requis." }, 400);
    }

    // 3. Client admin (service role) pour bypasser RLS lors de la lecture
    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { invitation, establishment, inviter } = await loadContext(
      admin,
      invitationId,
    );

    // 4. Vérifie que le caller est bien admin de l'établissement
    const { data: callerMembership } = await admin
      .from("establishment_members")
      .select("role")
      .eq("user_id", caller.id)
      .eq("establishment_id", establishment.id)
      .maybeSingle();
    if (!callerMembership || callerMembership.role !== "admin") {
      return jsonResponse(
        { error: "Seul l'administrateur de l'école peut envoyer cette invitation." },
        403,
      );
    }

    // 5. Vérifie que l'invitation n'est ni expirée ni déjà acceptée
    const expiresAt = new Date(invitation.expires_at);
    if (expiresAt.getTime() < Date.now()) {
      return jsonResponse({ error: "Invitation expirée." }, 410);
    }
    if (invitation.accepted_at) {
      return jsonResponse({ error: "Invitation déjà acceptée." }, 409);
    }

    // 6. Construit le mail
    const schemeLink = `correctis://invite?token=${invitation.token}`;
    const httpsLink = `${APP_PUBLIC_URL.replace(/\/$/, "")}/invite?token=${invitation.token}`;
    // Audit 15/10/2026 : une fois assetlinks.json publié (App Links vérifiés),
    // APP_LINKS_ENABLED=1 fait du lien https le bouton principal — il ne peut
    // pas être intercepté par une autre app, contrairement à correctis://.
    const appLinksEnabled = (Deno.env.get("APP_LINKS_ENABLED") ?? "") === "1";
    const deepLink = appLinksEnabled ? httpsLink : schemeLink;
    const webFallback = appLinksEnabled ? schemeLink : httpsLink;
    const inviterName =
      inviter?.display_name?.trim() ||
      inviter?.email ||
      "L'administrateur";

    const { subject, html, text } = buildEmail({
      establishmentName: establishment.name,
      inviterName,
      matiere: invitation.matiere,
      classes: invitation.classes ?? [],
      deepLink,
      webFallback,
      expiresAt,
    });

    // 7. Envoie via Resend
    const emailId = await sendViaResend({
      to: invitation.email,
      subject,
      html,
      text,
    });

    return jsonResponse({ ok: true, email_id: emailId });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("[send-invitation-email]", msg);
    return jsonResponse({ error: msg }, 500);
  }
});
