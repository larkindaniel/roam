// Opens a GitHub issue for a bug report the caller just sent.
//
// The app calls this with the report's id right after submit_bug_report. It reads the report with the service role,
// makes 30-day links to its screenshots and recordings, adds the last steps from the event trail, and opens an issue in
// GITHUB_REPO ("owner/name") with GITHUB_TOKEN (a fine-grained token with Issues: read and write on that repo only).
// Without those two secrets it does nothing, and the report is still saved for the team to read in SQL.
const url = Deno.env.get("SUPABASE_URL")!;
const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const token = Deno.env.get("GITHUB_TOKEN");
const repo = Deno.env.get("GITHUB_REPO");
// Issues on a public repo are readable by anyone, so by default they carry only the tester's words, the app and device
// and the report id. Screenshots, who sent it and the steps (places, people) stay in Supabase. Set this to "true" only
// when GITHUB_REPO is private.
const includeDetails = Deno.env.get("GITHUB_INCLUDE_DETAILS") === "true";

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

    const [profile] = includeDetails ? await rest(`profiles?id=eq.${user.id}&select=handle,display_name`) : [];
    const steps = includeDetails && report.session_id
      ? await rest(`bug_report_trail?report_id=eq.${reportId}&select=seq,at,kind,name,screen,duration_ms&order=seq.desc&limit=40`)
      : [];

    let attachment = "";
    const files = (report.attachments ?? []) as Array<{ path: string; kind: string }>;
    const shown: string[] = [];
    for (const [index, file] of (includeDetails ? files : []).entries()) {
      const signed = await fetch(`${url}/storage/v1/object/sign/bug-reports/${file.path}`, {
        method: "POST", headers: { ...asService, "Content-Type": "application/json" },
        body: JSON.stringify({ expiresIn: 60 * 60 * 24 * 30 }),
      });
      if (!signed.ok) continue;
      const link = `${url}/storage/v1${(await signed.json()).signedURL}`;
      shown.push(file.kind === "screenshot" ? `<img src="${link}" width="240">` : `[Screen recording ${index + 1}](${link})`);
    }
    if (shown.length) attachment = `\n\n### Attached\n${shown.join(" ")}\n(links last 30 days)`;

    const trail = (steps as Array<Record<string, unknown>>).reverse().map(step =>
      `| ${step.seq} | ${String(step.at).slice(11, 19)} | ${step.kind} | \`${step.name}\` | ${step.screen ?? ""} | ${step.duration_ms ?? ""} |`,
    ).join("\n");
    const firstLine = String(report.description).split("\n")[0].slice(0, 80);
    const body = [
      String(report.description),
      attachment,
      "\n\n### Where",
      includeDetails ? `- From: @${profile?.handle ?? "?"} (${profile?.display_name ?? "?"})` : `- ${files.length} attachment(s) in Supabase`,
      `- Screen: \`${report.screen ?? "?"}\``,
      `- App ${report.app_version} (${report.build}), iOS ${report.os_version}, ${report.device_model}`,
      `- Report \`${report.id}\`, session \`${report.session_id ?? "none"}\``,
      trail ? `\n### The last ${steps.length} steps\n| # | time (UTC) | kind | name | screen | ms |\n|---|---|---|---|---|---|\n${trail}` : "",
      `\n\nThe report and its steps: \`select * from bug_reports where id = '${report.id}'; select * from bug_report_trail where report_id = '${report.id}';\``,
    ].join("\n");

    const open = (labels: string[]) => fetch(`https://api.github.com/repos/${repo}/issues`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, Accept: "application/vnd.github+json", "Content-Type": "application/json",
                 "User-Agent": "roam-bug-reports" },
      body: JSON.stringify({ title: `Bug: ${firstLine}`, body, labels }),
      signal: AbortSignal.timeout(15_000),
    });
    // Labels the repo doesn't have can be refused; the issue matters more than its labels.
    let issue = await open(["bug", "beta-report"]);
    if (issue.status === 422) issue = await open([]);
    if (!issue.ok) return json({ message: "GitHub didn't take it." }, 502);
    const { html_url } = await issue.json();
    await fetch(`${url}/rest/v1/bug_reports?id=eq.${reportId}`, {
      method: "PATCH", headers: { ...asService, "Content-Type": "application/json", Prefer: "return=minimal" },
      body: JSON.stringify({ github_issue_url: html_url }),
    });
    return json({ url: html_url });
  } catch {
    // The report itself is already saved; no token or report text goes into logs.
    return json({ message: "Couldn't open an issue." }, 503);
  }
});
