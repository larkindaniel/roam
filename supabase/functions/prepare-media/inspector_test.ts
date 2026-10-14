import jpeg from "jpeg-js";
import { inspectJPEG } from "./inspector.ts";

function photo(width = 16, height = 12): Uint8Array {
  return jpeg.encode({ width, height, data: new Uint8Array(width * height * 4).fill(120) }, 80).data;
}
async function rejects(bytes: Uint8Array) {
  try { await inspectJPEG(bytes); throw new Error("Expected inspection rejection"); }
  catch (error) { if (error instanceof Error && error.message === "Expected inspection rejection") throw error; }
}
Deno.test("actual JPEG dimensions, byte size and SHA256", async () => {
  const bytes = photo(), result = await inspectJPEG(bytes);
  if (result.width !== 16 || result.height !== 12 || result.byteSize !== bytes.length || result.sha256.length !== 64) throw new Error("Incorrect measured inspection");
});
Deno.test("truncated and non-JPEG inputs", async () => {
  await rejects(new TextEncoder().encode("not a JPEG"));
  await rejects(photo().subarray(0, 20));
});
Deno.test("actual oversized frame rejected before decode", async () => { await rejects(photo(2049, 1)); });
Deno.test("oversized encoded body rejected", async () => { await rejects(new Uint8Array(3 * 1024 * 1024 + 1)); });
Deno.test("EXIF, IPTC and comment metadata rejected", async () => {
  for (const marker of [225, 237, 254]) {
    const source = photo(), data = new Uint8Array(source.length + 8);
    data.set(source.subarray(0, 2)); data.set([255, marker, 0, 6, 71, 80, 83, 0], 2); data.set(source.subarray(2), 10);
    await rejects(data);
  }
});
Deno.test("corrupt entropy cannot pass header checks", async () => {
  const source = photo(); let scan = -1;
  for (let i = 2; i < source.length - 1; i++) if (source[i] === 255 && source[i + 1] === 218) { scan = i; break; }
  if (scan < 0) throw new Error("Missing test scan");
  const length = (source[scan + 2] << 8) | source[scan + 3];
  const truncated = new Uint8Array(scan + 2 + length + 2);
  truncated.set(source.subarray(0, scan + 2 + length)); truncated.set([255, 217], truncated.length - 2);
  await rejects(truncated);
});
