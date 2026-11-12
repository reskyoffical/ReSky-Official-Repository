// Registers an uploaded profile image. The SERVER inspects the bytes to decide
// whether it is animated (GIF / APNG / animated WebP), so the client cannot
// sneak animated artwork past the ReSky Plus check.
import { adminClient, handle, HttpError, json, requireUser } from "../_shared/util.ts";

const MAX_BYTES = 10 * 1024 * 1024;
const KINDS = ["avatar", "banner", "background", "theme_art"];

function sniff(b: Uint8Array): { mime: string; animated: boolean } | null {
  const ascii = (o: number, n: number) => String.fromCharCode(...b.subarray(o, o + n));
  if (b[0] === 0xff && b[1] === 0xd8) return { mime: "image/jpeg", animated: false };
  if (ascii(0, 6) === "GIF87a" || ascii(0, 6) === "GIF89a") {
    // count image descriptors (0x2C) that follow a graphic control extension block
    let frames = 0;
    for (let i = 0; i < b.length - 2; i++) if (b[i] === 0x21 && b[i + 1] === 0xf9 && b[i + 2] === 0x04) frames++;
    return { mime: "image/gif", animated: frames > 1 };
  }
  if (b[0] === 0x89 && ascii(1, 3) === "PNG") {
    let animated = false;
    for (let i = 8; i + 8 < b.length;) {
      const len = (b[i] << 24 | b[i + 1] << 16 | b[i + 2] << 8 | b[i + 3]) >>> 0;
      const type = ascii(i + 4, 4);
      if (type === "acTL") { animated = true; break; }
      if (type === "IDAT") break;
      i += 12 + len;
    }
    return { mime: "image/png", animated };
  }
  if (ascii(0, 4) === "RIFF" && ascii(8, 4) === "WEBP") {
    const vp8x = ascii(12, 4) === "VP8X";
    const animated = vp8x && (b[20] & 0x02) !== 0;
    return { mime: "image/webp", animated };
  }
  return null;
}

Deno.serve(handle(async (req) => {
  const user = await requireUser(req);
  const { path, static_path, kind } = await req.json().catch(() => ({}));
  if (typeof path !== "string" || !KINDS.includes(kind)) throw new HttpError(400, "invalid_request");
  if (!path.startsWith(`${user.id}/`) || (static_path && !String(static_path).startsWith(`${user.id}/`))) {
    throw new HttpError(403, "forbidden");
  }
  const admin = adminClient();
  const { data: file, error } = await admin.storage.from("profile").download(path);
  if (error || !file) throw new HttpError(404, "file_not_found");
  const bytes = new Uint8Array(await file.arrayBuffer());
  if (bytes.length > MAX_BYTES) {
    await admin.storage.from("profile").remove([path]);
    throw new HttpError(413, "file_too_large");
  }
  const info = sniff(bytes);
  if (!info) {
    await admin.storage.from("profile").remove([path]);
    throw new HttpError(415, "unsupported_format");
  }
  const { data: row, error: insErr } = await admin.from("profile_assets").insert({
    user_id: user.id, kind, path,
    static_path: info.animated ? (static_path ?? null) : path,
    is_animated: info.animated, mime_type: info.mime, byte_size: bytes.length,
  }).select().single();
  if (insErr) throw new HttpError(500, "insert_failed");

  const { data: plus } = await admin.rpc("has_plus", { uid: user.id });
  return json({ asset: row, is_animated: info.animated, locked: info.animated && !plus });
}));
