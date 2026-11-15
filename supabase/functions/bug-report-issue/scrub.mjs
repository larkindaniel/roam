// What could identify someone, taken out of text that goes into a public GitHub issue: emails, phone numbers and ids
// (user, session and place ids alike). Ten or more digits in a run (with spaces, dashes or brackets) reads as a phone
// number; dates, coordinates and sizes don't.
export function scrub(text) {
  return String(text)
    .replace(/[\w.+-]+@[\w-]+\.[\w.]+/g, "[email]")
    .replace(/\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b/g, "[id]")
    .replace(/\+?\d[\d ().-]{8,}\d/g, match => match.replace(/\D/g, "").length >= 10 ? "[number]" : match);
}

// The issue's title: the first line of the (scrubbed) description, at most 80 characters.
export function issueTitle(description) {
  return scrub(description).split("\n")[0].slice(0, 80);
}
