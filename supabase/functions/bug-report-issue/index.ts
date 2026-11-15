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

// Screenshots and recordings are committed here so the issue can show them. A branch of their own: it never touches
// main. Needs the token to have Contents: read and write as well as Issues.
const attachmentsBranch = Deno.env.get("GITHUB_ATTACHMENTS_BRANCH") ?? "bug-report-attachments";

async function github(path: string, init: RequestInit = {}) {
  return await fetch(`https://api.github.com/repos/${repo}/${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${token}`, Accept: "application/vnd.github+json", "Content-Type": "application/json",
               "User-Agent": "roam-bug-reports", ...(init.headers ?? {}) },
    signal: AbortSignal.timeout(30_000),
  });
}

function base64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
}

/// Commits the files to the attachments branch in one commit (making the branch on first use). Returns each file's
/// raw link, or null if GitHub refused (logged with its status, never the token).
async function commitAttachments(files: Array<{ path: string; bytes: Uint8Array }>, message: string): Promise<string[] | null> {
  const ref = await github(`git/ref/heads/${attachmentsBranch}`);
  let parent: string | null = null, baseTree: string | null = null;
  if (ref.ok) {
    parent = (await ref.json()).object.sha;
    baseTree = (await (await github(`git/commits/${parent}`)).json()).tree.sha;
  } else if (ref.status !== 404) {
    console.error("bug-report-issue: reading the attachments branch failed", ref.status);
    return null;
  }
  const tree = [];
  for (const file of files) {
    const blob = await github("git/blobs", { method: "POST", body: JSON.stringify({ content: base64(file.bytes), encoding: "base64" }) });
    if (!blob.ok) { console.error("bug-report-issue: GitHub refused the file", blob.status, (await blob.text()).slice(0, 200)); return null; }
    tree.push({ path: file.path, mode: "100644", type: "blob", sha: (await blob.json()).sha });
  }
  const madeTree = await github("git/trees", { method: "POST", body: JSON.stringify(baseTree ? { base_tree: baseTree, tree } : { tree }) });
  if (!madeTree.ok) { console.error("bug-report-issue: tree failed", madeTree.status); return null; }
  const commit = await github("git/commits", { method: "POST", body: JSON.stringify({
    message, tree: (await madeTree.json()).sha, parents: parent ? [parent] : [] }) });
  if (!commit.ok) { console.error("bug-report-issue: commit failed", commit.status); return null; }
  const sha = (await commit.json()).sha;
  const moved = parent
    ? await github(`git/refs/heads/${attachmentsBranch}`, { method: "PATCH", body: JSON.stringify({ sha }) })
    : await github("git/refs", { method: "POST", body: JSON.stringify({ ref: `refs/heads/${attachmentsBranch}`, sha }) });
  if (!moved.ok) { console.error("bug-report-issue: moving the branch failed", moved.status); return null; }
  // github.com's raw form works on public and private repos alike (raw.githubusercontent.com is public-only).
  return files.map(file => `https://github.com/${repo}/blob/${sha}/${file.path}?raw=true`);
}

/// A link to the file in Supabase storage, from a copy under a random name (the upload's own folder is the tester's
/// account id). Works once the project is hosted; used if GitHub won't take the file.
async function storageLink(path: string): Promise<string | null> {
  const extension = path.split(".").pop() ?? "jpg";
  const anonymous = `issues/${crypto.randomUUID()}.${extension}`;
  const copied = await fetch(`${url}/storage/v1/object/copy`, {
    method: "POST", headers: { ...asService, "Content-Type": "application/json" },
    body: JSON.stringify({ bucketId: "bug-reports", sourceKey: path, destinationKey: anonymous }),
  });
  if (!copied.ok) { console.error("bug-report-issue: copy failed", copied.status); return null; }
  const signed = await fetch(`${url}/storage/v1/object/sign/bug-reports/${anonymous}`, {
    method: "POST", headers: { ...asService, "Content-Type": "application/json" },
    body: JSON.stringify({ expiresIn: linkLifetime }),
  });
  return signed.ok ? `${url}/storage/v1${(await signed.json()).signedURL}` : null;
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
    // Committed to the attachments branch so GitHub shows them; Supabase links if that doesn't work.
    const downloaded: Array<{ path: string; bytes: Uint8Array }> = [];
    for (const file of files) {
      const object = await fetch(`${url}/storage/v1/object/bug-reports/${file.path}`, { headers: asService });
      if (!object.ok) { console.error("bug-report-issue: download failed", object.status); continue; }
      const extension = file.path.split(".").pop() ?? "jpg";
      downloaded.push({ path: `reports/${crypto.randomUUID()}.${extension}`, bytes: new Uint8Array(await object.arrayBuffer()) });
    }
    let links = downloaded.length ? await commitAttachments(downloaded, "Bug report attachments") : null;
    if (!links) {
      links = [];
      for (const file of files) { const link = await storageLink(file.path); if (link) links.push(link); }
    }
    let recordings = 0;
    const shown = links.map((link, index) => files[index]?.kind === "recording"
      ? `▶️ [Screen recording ${++recordings}](${link})`
      : `<img src="${link}" width="320">`);
    if (shown.length) attachment = `\n\n### Screenshots and recordings\n${shown.join("\n")}`;

    const description = scrub(String(report.description));
    const firstLine = description.split("\n")[0].slice(0, 80);
    const body = [
      description,
      attachment,
      "\n\n### Where",
      `- Screen: \`${report.screen ?? "?"}\``,
      `- App ${report.app_version} (${report.build}), iOS ${report.os_version}, ${report.device_model}`,
      `\n### Logs\nEverything the tester did, up to sending this (and their previous session, if the app was reopened to report). ` +
        `Paste into Supabase's SQL editor.\n\nWhat they did: screens, taps, navigation, actions, errors and crashes\n\n` +
        "```sql\nselect session, seq, at, kind, name, screen, duration_ms, props\nfrom bug_report_trail\n" +
        `where report_id = '${report.id}' and kind <> 'network'\norder by part, seq;\n` + "```\n\n" +
        "Network calls: what the app asked the server for, how long each took, and any that failed\n\n" +
        "```sql\nselect session, seq, at, name, duration_ms, props ->> 'status' as status, props\nfrom bug_report_trail\n" +
        `where report_id = '${report.id}' and kind = 'network'\norder by part, seq;\n` + "```",
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
