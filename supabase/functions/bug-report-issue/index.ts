// Opens a GitHub issue for a bug report the caller just sent.
//
// The app calls this with the report's id right after submit_bug_report. It reads the report with the service role and
// opens an issue in GITHUB_REPO ("owner/name") with GITHUB_TOKEN (a fine-grained token with Issues: read and write on
// that repo only). Without those two secrets it does nothing, and the report is still saved for the team to read in SQL.
//
// The repo is public, so the issue has what helps fix the bug and nothing that identifies the tester:
//   in:  their description, the screenshots (shown inline) and recordings (linked), app, iOS and device, the screen,
//        and the SQL that lists the steps before the report (the steps themselves stay in Supabase)
//   out: who sent it, emails and phone numbers
const url = Deno.env.get("SUPABASE_URL")!;
const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const token = Deno.env.get("GITHUB_TOKEN");
const repo = Deno.env.get("GITHUB_REPO");
// Attachment links last a year, so the pictures keep showing in the issue.
const linkLifetime = 60 * 60 * 24 * 365;

/// Takes out what could identify someone: emails, phone numbers and ids (user, session and place ids alike).
function scrub(text: string): string {
  return text
    .replace(/[\w.+-]+@[\w-]+\.[\w.]+/g, "[email]")
    .replace(/\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b/g, "[id]")
    // Ten or more digits in a run (with spaces, dashes or brackets) reads as a phone number; dates and sizes don't.
    .replace(/\+?\d[\d ().-]{8,}\d/g, match => match.replace(/\D/g, "").length >= 10 ? "[number]" : match);
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body),
  { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" } });

const asService = { apikey: service, Authorization: `Bearer ${service}` };

async function rest(path: string) {
  const response = await fetch(`${url}/rest/v1/${path}`, { headers: asService, signal: AbortSignal.timeout(10_000) });
  if (!response.ok) throw new Error(`rest ${response.status}`);
  return await response.json();
}

Deno.serve(async request => {
  if (request.method !== "POST") return json({ message: "Use POST." }, 405);
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) return json({ message: "Sign in again." }, 401);
  if (!token || !repo) return json({ skipped: "GitHub isn't set up." });

  let reportId: unknown;
  try { reportId = (await request.json())?.reportId; } catch { return json({ message: "Invalid request." }, 400); }
  if (typeof reportId !== "string" || !/^[0-9a-f-]{36}$/.test(reportId)) return json({ message: "Invalid request." }, 400);

  try {
    // Only the person who sent the report can ask for its issue.
    const userResponse = await fetch(`${url}/auth/v1/user`, { headers: { apikey: anon, Authorization: authorization } });
    if (!userResponse.ok) return json({ message: "Sign in again." }, 401);
    const user = await userResponse.json();

    const [report] = await rest(`bug_reports?id=eq.${reportId}&select=*`);
    if (!report || report.user_id !== user.id) return json({ message: "Not found." }, 404);
    if (report.github_issue_url) return json({ url: report.github_issue_url });

    let attachment = "";
    const files = (report.attachments ?? []) as Array<{ path: string; kind: string }>;
    const shown: string[] = [];
    let recordings = 0;
    for (const file of files) {
      // The upload sits in a folder named after the tester's account id, which a public link would show. Link a copy
      // under a random name instead.
      const extension = file.path.split(".").pop() ?? "jpg";
      const anonymous = `issues/${crypto.randomUUID()}.${extension}`;
      const copied = await fetch(`${url}/storage/v1/object/copy`, {
        method: "POST", headers: { ...asService, "Content-Type": "application/json" },
        body: JSON.stringify({ bucketId: "bug-reports", sourceKey: file.path, destinationKey: anonymous }),
      });
      if (!copied.ok) { console.error("bug-report-issue: copy failed", copied.status); continue; }
      const signed = await fetch(`${url}/storage/v1/object/sign/bug-reports/${anonymous}`, {
        method: "POST", headers: { ...asService, "Content-Type": "application/json" },
        body: JSON.stringify({ expiresIn: linkLifetime }),
      });
      if (!signed.ok) continue;
      const link = `${url}/storage/v1${(await signed.json()).signedURL}`;
      shown.push(file.kind === "screenshot" ? `<img src="${link}" width="320">` : `▶️ [Screen recording ${++recordings}](${link})`);
    }
    if (shown.length) attachment = `\n\n### Screenshots and recordings\n${shown.join("\n")}`;

    const description = scrub(String(report.description));
    const firstLine = description.split("\n")[0].slice(0, 80);
    const body = [
      description,
      attachment,
      "\n\n### Where",
      `- Screen: \`${report.screen ?? "?"}\``,
      `- App ${report.app_version} (${report.build}), iOS ${report.os_version}, ${report.device_model}`,
      `\n### Logs\nEverything the tester did in the app up to sending this. Paste into Supabase's SQL editor:\n\n\`\`\`sql\nselect seq, at, kind, name, screen, duration_ms, props\nfrom bug_report_trail\nwhere report_id = '${report.id}'\norder by seq;\n\`\`\``,
    ].join("\n");

    const open = (labels: string[]) => fetch(`https://api.github.com/repos/${repo}/issues`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, Accept: "application/vnd.github+json", "Content-Type": "application/json",
                 "User-Agent": "roam-bug-reports" },
      body: JSON.stringify({ title: firstLine, body, labels }),
      signal: AbortSignal.timeout(15_000),
    });
    // Labels the repo doesn't have can be refused; the issue matters more than its labels.
    let issue = await open(["bug", "user-reported-bug"]);
    if (issue.status === 422) issue = await open([]);
    if (!issue.ok) {
      console.error("bug-report-issue: GitHub said", issue.status, (await issue.text()).slice(0, 300));
      return json({ message: "GitHub didn't take it." }, 502);
    }
    const { html_url } = await issue.json();
    await fetch(`${url}/rest/v1/bug_reports?id=eq.${reportId}`, {
      method: "PATCH", headers: { ...asService, "Content-Type": "application/json", Prefer: "return=minimal" },
      body: JSON.stringify({ github_issue_url: html_url }),
    });
    return json({ url: html_url });
  } catch (error) {
    // The report itself is already saved. Only the error's own message is logged, never the token or the report.
    console.error("bug-report-issue failed:", error instanceof Error ? error.message : String(error));
    return json({ message: "Couldn't open an issue." }, 503);
  }
});
