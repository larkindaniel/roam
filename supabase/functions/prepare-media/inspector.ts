import jpeg from "jpeg-js";

export type Inspection = { width: number; height: number; byteSize: number; sha256: string };

/** Bound allocation from actual frame headers, reject location-capable metadata, then fully
 * decode with strict entropy handling. Caller MIME and dimensions are never trusted. */
export async function inspectJPEG(bytes: Uint8Array): Promise<Inspection> {
  const fail = (message: string): never => { throw new Error(message); };
  if (bytes.length > 3 * 1024 * 1024) fail("Photos must be 3 MB or smaller.");
  if (bytes.length < 4 || bytes[0] !== 255 || bytes[1] !== 216 || bytes.at(-2) !== 255 || bytes.at(-1) !== 217) fail("Upload a complete JPEG photo.");
  let offset = 2, width = 0, height = 0, scans = 0, ended = false;
  const ascii = (start: number, length: number) => String.fromCharCode(...bytes.subarray(start, start + length));
  while (offset < bytes.length) {
    if (bytes[offset++] !== 255) fail("Invalid JPEG marker.");
    while (bytes[offset] === 255) offset++;
    const marker = bytes[offset++];
    if (marker === 217) { ended = offset === bytes.length; break; }
    if (marker === 216 || marker === 0 || marker === undefined || (marker >= 208 && marker <= 215)) fail("Invalid JPEG structure.");
    if (offset + 2 > bytes.length) fail("Truncated JPEG.");
    const length = (bytes[offset] << 8) | bytes[offset + 1];
    const start = offset + 2, end = offset + length;
    if (length < 2 || end > bytes.length) fail("Truncated JPEG segment.");
    if (marker === 225 || marker === 237 || marker === 254) fail("Remove location and comment metadata before uploading.");
    if (marker >= 224 && marker <= 239) {
      const safe = (marker === 224 && (ascii(start, 5) === "JFIF\0" || ascii(start, 5) === "JFXX\0"))
        || (marker === 226 && ascii(start, 12) === "ICC_PROFILE\0") || (marker === 238 && ascii(start, 5) === "Adobe");
      if (!safe) fail("Remove unsupported photo metadata before uploading.");
    }
    if ([192, 193, 194].includes(marker)) {
      if (width || length < 8 || bytes[start] !== 8) fail("Unsupported JPEG frame.");
      height = (bytes[start + 1] << 8) | bytes[start + 2];
      width = (bytes[start + 3] << 8) | bytes[start + 4];
      if (width < 1 || height < 1 || width > 2048 || height > 2048) fail("Photos must be 2,048 pixels or smaller on the longest side.");
    } else if (marker >= 195 && marker <= 207 && ![196, 200, 204].includes(marker)) fail("Unsupported JPEG frame.");
    offset = end;
    if (marker === 218) {
      scans++;
      while (offset < bytes.length) {
        if (bytes[offset] !== 255) { offset++; continue; }
        const next = bytes[offset + 1];
        if (next === 0 || (next >= 208 && next <= 215)) { offset += 2; continue; }
        break;
      }
    }
  }
  if (!ended || !width || !height || !scans) fail("The JPEG is incomplete.");
  try {
    const image = jpeg.decode(bytes, { useTArray: true, tolerantDecoding: false, maxResolutionInMP: 4.2, maxMemoryUsageInMB: 128 });
    if (image.width !== width || image.height !== height || image.data.length !== width * height * 4) fail("JPEG dimensions are inconsistent.");
  } catch { fail("This JPEG could not be decoded. Choose another photo."); }
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return { width, height, byteSize: bytes.length, sha256: Array.from(digest, x => x.toString(16).padStart(2, "0")).join("") };
}
