/**
 * Instagram Reels → YouTube Shorts.
 * Resmî Graph API + YouTube Data API v3. Kalıcı video deposu yok.
 */
import { mkdtemp, rm, writeFile, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";

const IG_API = "https://graph.instagram.com/v22.0";
const ADMIN_URL = (process.env.YOUTUBE_AUTOMATION_URL || "https://admin.rotalink.tr").replace(/\/$/, "");
const TOKEN = process.env.YOUTUBE_AUTOMATION_TOKEN || "";
const SITE = "https://rotalink.tr";
const SHORTS_MAX_SECONDS = 180;
const TITLE_MAX = 100;

export function firstMeaningfulLine(caption) {
  const lines = String(caption || "")
    .replace(/\r\n/g, "\n")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  for (const line of lines) {
    const withoutTags = line
      .replace(/#[\p{L}\p{N}_]+/gu, " ")
      .replace(/\s+/g, " ")
      .trim();
    if (withoutTags.length >= 3) return withoutTags;
  }
  return lines[0] || "Rotalink Shorts";
}

export function youtubeTitleFromCaption(caption) {
  let title = firstMeaningfulLine(caption);
  if (!/#shorts/i.test(title)) {
    const withTag = `${title} #Shorts`.trim();
    title = withTag.length <= TITLE_MAX ? withTag : title;
  }
  if (title.length > TITLE_MAX) title = title.slice(0, TITLE_MAX).trim();
  return title || "Rotalink #Shorts";
}

export function youtubeDescriptionFromCaption(caption) {
  const body = String(caption || "").trim();
  return [body, "", SITE, "", "Kaynak: Instagram @rotalink_tr", "#Shorts #Rotalink"]
    .join("\n")
    .slice(0, 4900);
}

export function isVerticalShort(meta) {
  if (meta.durationSec != null && meta.durationSec > SHORTS_MAX_SECONDS) {
    return {
      ok: false,
      reason: `Süre ${meta.durationSec.toFixed(1)} sn; Shorts üst sınırı ${SHORTS_MAX_SECONDS} sn.`,
    };
  }
  if (
    meta.width != null &&
    meta.height != null &&
    meta.width > 0 &&
    meta.height > 0 &&
    meta.width > meta.height
  ) {
    return {
      ok: false,
      reason: `Yatay video (${meta.width}x${meta.height}); Shorts dikey veya kare olmalı.`,
    };
  }
  return { ok: true, reason: "" };
}

function authHeaders() {
  return { Authorization: `Bearer ${TOKEN}`, Accept: "application/json" };
}

async function adminJson(path, init = {}) {
  const response = await fetch(`${ADMIN_URL}${path}`, {
    ...init,
    headers: {
      ...authHeaders(),
      ...(init.body ? { "Content-Type": "application/json" } : {}),
      ...(init.headers || {}),
    },
  });
  const text = await response.text();
  let data;
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    throw new Error(`Admin yanıtı JSON değil (${response.status}).`);
  }
  if (!response.ok) {
    throw new Error(
      data.error || data.message || `Admin HTTP ${response.status}`,
    );
  }
  return data;
}

async function listReels(userId, accessToken) {
  const items = [];
  let url = new URL(`${IG_API}/${encodeURIComponent(userId)}/media`);
  url.searchParams.set(
    "fields",
    "id,caption,media_type,media_product_type,media_url,permalink,timestamp,thumbnail_url",
  );
  url.searchParams.set("limit", "25");
  url.searchParams.set("access_token", accessToken);

  for (let page = 0; page < 8 && url; page += 1) {
    const response = await fetch(url);
    const data = await response.json();
    if (!response.ok) {
      throw new Error(data?.error?.message || "Instagram medya listesi alınamadı.");
    }
    for (const item of data.data || []) {
      const product = String(item.media_product_type || "").toUpperCase();
      const type = String(item.media_type || "").toUpperCase();
      const permalink = String(item.permalink || "");
      const isReel =
        product === "REELS" ||
        (type === "VIDEO" && /\/reel\//i.test(permalink));
      if (isReel) items.push(item);
    }
    url = data.paging?.next ? new URL(data.paging.next) : null;
  }
  return items;
}

async function mediaDetail(mediaId, accessToken) {
  const url = new URL(`${IG_API}/${encodeURIComponent(mediaId)}`);
  url.searchParams.set(
    "fields",
    "id,caption,media_type,media_product_type,media_url,permalink,timestamp,thumbnail_url",
  );
  url.searchParams.set("access_token", accessToken);
  const response = await fetch(url);
  const data = await response.json();
  if (!response.ok) {
    throw new Error(data?.error?.message || "Instagram medya detayı alınamadı.");
  }
  return data;
}

function run(cmd, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"] });
    let out = "";
    let err = "";
    child.stdout.on("data", (chunk) => {
      out += chunk;
    });
    child.stderr.on("data", (chunk) => {
      err += chunk;
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve(out);
      else reject(new Error(err || `${cmd} exit ${code}`));
    });
  });
}

export async function probeVideo(filePath) {
  try {
    const out = await run("ffprobe", [
      "-v",
      "error",
      "-select_streams",
      "v:0",
      "-show_entries",
      "stream=width,height:format=duration",
      "-of",
      "json",
      filePath,
    ]);
    const parsed = JSON.parse(out);
    const stream = parsed.streams?.[0] || {};
    const duration = Number(parsed.format?.duration);
    return {
      width: Number.isFinite(stream.width) ? stream.width : null,
      height: Number.isFinite(stream.height) ? stream.height : null,
      durationSec: Number.isFinite(duration) ? duration : null,
    };
  } catch {
    return { width: null, height: null, durationSec: null };
  }
}

async function downloadVideo(mediaUrl, filePath) {
  const response = await fetch(mediaUrl, {
    headers: { "User-Agent": "RotalinkShorts/1.0 (+https://rotalink.tr)" },
  });
  if (!response.ok) {
    throw new Error(`Video indirme başarısız (HTTP ${response.status}).`);
  }
  const buffer = Buffer.from(await response.arrayBuffer());
  if (buffer.length < 1024) throw new Error("İndirilen video dosyası çok küçük.");
  await writeFile(filePath, buffer);
  return buffer.length;
}

async function uploadYouTube({
  accessToken,
  filePath,
  title,
  description,
  privacyStatus,
}) {
  const metadata = {
    snippet: {
      title,
      description,
      categoryId: "22",
    },
    status: {
      privacyStatus,
      selfDeclaredMadeForKids: false,
    },
  };
  const start = await fetch(
    "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json; charset=UTF-8",
        "X-Upload-Content-Type": "video/mp4",
      },
      body: JSON.stringify(metadata),
    },
  );
  if (!start.ok) {
    const err = await start.text();
    throw new Error(`YouTube yükleme oturumu açılamadı: ${err.slice(0, 400)}`);
  }
  const uploadUrl = start.headers.get("location");
  if (!uploadUrl) throw new Error("YouTube resumable upload URL alınamadı.");
  const bytes = await readFile(filePath);
  const put = await fetch(uploadUrl, {
    method: "PUT",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "video/mp4",
      "Content-Length": String(bytes.length),
    },
    body: bytes,
  });
  const body = await put.json().catch(() => ({}));
  if (!put.ok || !body.id) {
    throw new Error(
      body?.error?.message ||
        `YouTube yükleme başarısız (HTTP ${put.status}).`,
    );
  }
  return String(body.id);
}

async function processMedia({ media, job, tempDir }) {
  const detail = await mediaDetail(media.id, job.instagramAccessToken);
  const caption = String(detail.caption || media.caption || "");
  const permalink = String(detail.permalink || media.permalink || "");
  const title = youtubeTitleFromCaption(caption);
  const description = youtubeDescriptionFromCaption(caption);
  const mediaUrl = detail.media_url;

  if (!mediaUrl) {
    return {
      instagramMediaId: media.id,
      status: "failed",
      title,
      caption,
      permalink,
      error:
        "Instagram media_url vermedi (telif/lisanslı ses veya indirme kısıtı olabilir). Scraping kullanılmaz.",
    };
  }

  const filePath = join(tempDir, `${media.id}.mp4`);
  try {
    await downloadVideo(mediaUrl, filePath);
    const probe = await probeVideo(filePath);
    const check = isVerticalShort(probe);
    if (!check.ok) {
      return {
        instagramMediaId: media.id,
        status: "skipped",
        title,
        caption,
        permalink,
        error: check.reason,
      };
    }
    const youtubeVideoId = await uploadYouTube({
      accessToken: job.youtubeAccessToken,
      filePath,
      title,
      description,
      privacyStatus: job.privacyStatus || "private",
    });
    return {
      instagramMediaId: media.id,
      status: "published",
      title,
      caption,
      permalink,
      youtubeVideoId,
      error: "",
    };
  } finally {
    await rm(filePath, { force: true }).catch(() => {});
  }
}

export async function main() {
  if (!TOKEN || TOKEN.length < 24) {
    throw new Error("YOUTUBE_AUTOMATION_TOKEN eksik veya çok kısa.");
  }

  const job = await adminJson("/api/youtube-automation/job");
  if (!job.enabled) {
    console.log(job.reason || "Otomasyon kapalı.");
    return { skipped: true };
  }
  if (!job.ready) {
    console.log(job.reason || "Hazır değil.");
    return { skipped: true };
  }

  if (job.youtubeChannelId && job.expectedYoutubeChannelId &&
      job.youtubeChannelId !== job.expectedYoutubeChannelId) {
    throw new Error("YouTube kanal kimliği doğrulaması başarısız.");
  }

  const reels = await listReels(job.instagramUserId, job.instagramAccessToken);
  console.log(`Instagram Reels bulundu: ${reels.length}`);

  if (!job.baselineSeeded) {
    const mediaIds = reels.map((item) => item.id);
    const seeded = await adminJson("/api/youtube-automation/job/baseline", {
      method: "POST",
      body: JSON.stringify({ mediaIds }),
    });
    console.log(`Taban alındı; geçmiş ${seeded.seeded} medya işaretlendi, yükleme yok.`);
    return { baseline: true, seeded: seeded.seeded };
  }

  const known = new Set(job.knownMediaIds || []);
  const knownStatuses = job.knownStatuses || {};
  const candidates = [];

  for (const item of reels) {
    if (!known.has(item.id)) candidates.push(item);
  }
  for (const row of job.retry || []) {
    if (row.status === "queued" || row.status === "failed") {
      if (!candidates.some((item) => item.id === row.instagramMediaId)) {
        candidates.push({ id: row.instagramMediaId });
      }
    }
  }

  // Aynı medya ID ikinci kez yüklenmez.
  const fresh = candidates.filter((item) => knownStatuses[item.id] !== "published");
  console.log(`Yüklenecek aday: ${fresh.length}`);

  const results = [];
  const tempDir = await mkdtemp(join(tmpdir(), "rotalink-shorts-"));
  try {
    for (const media of fresh.slice(0, 5)) {
      console.log(`İşleniyor: ${media.id}`);
      try {
        const result = await processMedia({ media, job, tempDir });
        results.push(result);
        console.log(`Sonuç ${media.id}: ${result.status}${result.youtubeVideoId ? " " + result.youtubeVideoId : ""}`);
      } catch (error) {
        results.push({
          instagramMediaId: media.id,
          status: "failed",
          title: "",
          caption: "",
          permalink: "",
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }
  } finally {
    await rm(tempDir, { recursive: true, force: true }).catch(() => {});
  }

  if (results.length) {
    await adminJson("/api/youtube-automation/job/result", {
      method: "POST",
      body: JSON.stringify({ results }),
    });
  }

  return { processed: results.length, results };
}

const isDirect = process.argv[1] &&
  (process.argv[1].endsWith("instagram_youtube_shorts.mjs") ||
    process.argv[1].includes("instagram_youtube_shorts"));

if (isDirect) {
  main()
    .then((summary) => {
      console.log(JSON.stringify(summary, null, 2));
    })
    .catch(async (error) => {
      console.error(error);
      try {
        if (TOKEN) {
          await adminJson("/api/youtube-automation/job/result", {
            method: "POST",
            body: JSON.stringify({
              results: [],
              lastError: error instanceof Error ? error.message : String(error),
            }),
          });
        }
      } catch {
        // ignore secondary failure
      }
      process.exitCode = 1;
    });
}
