/**
 * Termal tesislerin kayıtlı resmî sayfasını okur.
 * Canlı fiyat yazmaz. Sonuç yönetici onay kuyruğuna gider.
 */
import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { setTimeout as delay } from "node:timers/promises";

const BLOCKED = ["booking.com", "tripadvisor.com", "etstur.com", "otelz.com", "jollytur.com", "tatilsepeti.com", "google.com", "instagram.com", "facebook.com", "sikayetvar.com", "kamutesisleri.com", "wikipedia.org", "youtube.com", "x.com"];
const USER_AGENT = "RotalinkPriceCheck/1.0 (+https://rotalink.tr)";

export function officialHost(source) {
  try {
    const url = new URL(source);
    if (url.protocol !== "https:") return "";
    return url.hostname.toLowerCase().replace(/^www\./, "");
  } catch {
    return "";
  }
}

export function blockedHost(hostname) {
  const host = hostname.toLowerCase().replace(/^www\./, "");
  return BLOCKED.some((item) => host === item || host.endsWith("." + item));
}

export function sameOfficialHost(candidate, officialPage) {
  const official = officialHost(officialPage);
  const host = officialHost(candidate);
  if (!official || !host || blockedHost(host) || blockedHost(official)) return false;
  return host === official || host.endsWith("." + official);
}

export function htmlToText(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&#8378;|₺/g, " TL ")
    .replace(/\s+/g, " ")
    .trim();
}

function parseAmount(raw) {
  const body = raw.trim().replace(/\s/g, "");
  const normalized = body.includes(",") ? body.replace(/\./g, "").replace(",", ".") : body.replace(/\./g, "");
  const value = Number(normalized);
  return Number.isFinite(value) && value > 0 ? value : null;
}

function categoryOf(sentence) {
  const text = sentence.toLocaleLowerCase("tr");
  if (text.includes("aile banyosu")) return "aileBanyosu";
  if (/oda|konaklama|gece/.test(text) && !text.includes("havuz")) return "konaklama";
  if (text.includes("havuz")) return "havuz";
  if (/giriş|giris|kaplıca|kaplica|kişi başı|kisi basi/.test(text)) return "giris";
  return "";
}

function hasWord(text, word) {
  return text.toLocaleLowerCase("tr").split(/[^a-zçğıöşü0-9]+/i).includes(word);
}

function basisOf(sentence) {
  if (hasWord(sentence, "gece")) return "gece";
  if (hasWord(sentence, "oda")) return "oda";
  if (hasWord(sentence, "seans") || hasWord(sentence, "dakika")) return "seans";
  if (hasWord(sentence, "gün")) return "gun";
  return "kisi";
}

const LABELS = { giris: "Günlük giriş", havuz: "Günlük havuz girişi", aileBanyosu: "Aile banyosu", konaklama: "Konaklama" };
const UNITS = { gece: "gece", oda: "oda", seans: "seans", gun: "gün", kisi: "kişi" };

export function extractQuotes(text, sourceUrl, year) {
  const clean = htmlToText(text);
  const quotes = [];
  const amount = /(\d{1,3}(?:\.\d{3})+|\d{1,6})(?:,(\d{1,2}))?\s*(?:TL|₺)/gi;
  for (const sentence of clean.split(/\n|(?<=[.!])\s+/)) {
    if (!sentence.includes(String(year))) continue;
    if ([year - 2, year - 1, year + 1, year + 2].some((other) => sentence.includes(String(other)))) continue;
    const category = categoryOf(sentence);
    if (!category) continue;
    amount.lastIndex = 0;
    const found = amount.exec(sentence);
    if (!found) continue;
    const value = parseAmount(found[1] + (found[2] ? "," + found[2] : ""));
    if (value == null || value > 1_000_000) continue;
    if (/eur|usd|\$|€|dolar|euro/i.test(sentence)) continue;
    const dates = [...sentence.matchAll(/(\d{2})\.(\d{2})\.(20\d{2})/g)].map((item) => `${item[3]}-${item[2]}-${item[1]}`);
    const lower = sentence.toLocaleLowerCase("tr");
    const discount = /çocuk|cocuk|öğrenci|ogrenci|emekli|indirim|personel|ek yatak/.test(lower);
    const basis = basisOf(sentence);
    quotes.push({
      category,
      name: LABELS[category] + (discount ? " (indirimli)" : ""),
      amount: value,
      unit: UNITS[basis],
      basis,
      sourceUrl,
      year,
      validFrom: dates[0] ?? "",
      validTo: dates[1] ?? "",
      condition: /hafta sonu/.test(lower) ? "Hafta sonu" : /hafta içi|hafta ici/.test(lower) ? "Hafta içi" : "",
      starting: !discount,
    });
  }
  return quotes;
}

export function robotsAllows(robots, path) {
  const lines = robots.split(/\r?\n/);
  let active = false;
  const denies = [];
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const [key, ...rest] = trimmed.split(":");
    const value = rest.join(":").trim();
    if (/^user-agent$/i.test(key)) active = value === "*";
    else if (active && /^disallow$/i.test(key) && value) denies.push(value);
  }
  return !denies.some((rule) => path.startsWith(rule));
}

function privateHost(hostname) {
  const host = hostname.toLowerCase();
  if (host === "localhost" || host.endsWith(".local") || host.endsWith(".internal") || host === "metadata.google.internal") return true;
  const match = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
  if (!match) return false;
  const parts = match.slice(1).map(Number);
  const [a, b] = parts;
  return parts.some((part) => part > 255) || a === 10 || a === 127 || a === 0 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168);
}

async function fetchOfficial(url, cache, robotsCache) {
  const parsed = new URL(url);
  if (parsed.protocol !== "https:" || privateHost(parsed.hostname) || blockedHost(parsed.hostname)) {
    return { ok: false, reason: "kaynak-adresi-uygun-degil", text: "" };
  }
  const cached = cache.get(url);
  if (cached) return cached;
  const robotsUrl = parsed.origin + "/robots.txt";
  if (!robotsCache.has(parsed.origin)) {
    try {
      const robots = await fetch(robotsUrl, { headers: { "User-Agent": USER_AGENT }, redirect: "manual", signal: AbortSignal.timeout(10000) });
      robotsCache.set(parsed.origin, robots.ok ? await robots.text() : "");
    } catch {
      robotsCache.set(parsed.origin, "");
    }
  }
  if (!robotsAllows(robotsCache.get(parsed.origin) ?? "", parsed.pathname)) {
    const blocked = { ok: false, reason: "robots-txt", text: "" };
    cache.set(url, blocked);
    return blocked;
  }
  let current = url;
  for (let hop = 0; hop < 3; hop += 1) {
    let response;
    try {
      response = await fetch(current, { headers: { "User-Agent": USER_AGENT, Accept: "text/html,application/pdf" }, redirect: "manual", signal: AbortSignal.timeout(15000) });
    } catch {
      const failed = { ok: false, reason: "erisilemedi", text: "" };
      cache.set(url, failed);
      return failed;
    }
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const next = response.headers.get("location");
      if (!next || !sameOfficialHost(new URL(next, current).href, url)) {
        const failed = { ok: false, reason: "yonlendirme-baska-site", text: "" };
        cache.set(url, failed);
        return failed;
      }
      current = new URL(next, current).href;
      continue;
    }
    if (response.status === 429 || response.status >= 500) {
      await delay(2000);
      continue;
    }
    if (!response.ok) {
      const failed = { ok: false, reason: "http-" + response.status, text: "" };
      cache.set(url, failed);
      return failed;
    }
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.byteLength > 1_500_000) {
      const failed = { ok: false, reason: "sayfa-cok-buyuk", text: "" };
      cache.set(url, failed);
      return failed;
    }
    const type = response.headers.get("content-type") ?? "";
    const text = type.includes("pdf") || bytes[0] === 0x25 ? pdfText(bytes) : new TextDecoder("utf-8", { fatal: false }).decode(bytes);
    if (type.includes("pdf") && !text.trim()) {
      const failed = { ok: false, reason: "pdf-okunamadi", text: "" };
      cache.set(url, failed);
      return failed;
    }
    const result = { ok: true, reason: "", text };
    cache.set(url, result);
    return result;
  }
  const failed = { ok: false, reason: "erisilemedi", text: "" };
  cache.set(url, failed);
  return failed;
}

function pdfText(bytes) {
  const raw = new TextDecoder("latin1").decode(bytes);
  return [...raw.matchAll(/\((?:\\\)|\\.|[^\\)]){2,}\)/g)].map((item) => item[0].slice(1, -1)).join(" ");
}

export async function scanFacilities(facilities, year, pauseMs = 0) {
  const cache = new Map();
  const robotsCache = new Map();
  const results = [];
  for (const place of facilities) {
    if (place?.kategori !== "termal" || typeof place.id !== "string") continue;
    const official = typeof place.resmiKaynak === "string" ? place.resmiKaynak : "";
    let quotes = [];
    let reason = "";
    try {
      if (!sameOfficialHost(official, official)) reason = "Resmî fiyat doğrulanamadı";
      else {
        const page = await fetchOfficial(official, cache, robotsCache);
        if (!page.ok) reason = page.reason === "pdf-okunamadi" ? "PDF okunamadı" : "Resmî fiyat doğrulanamadı";
        else quotes = extractQuotes(page.text, official, year).filter((quote) => sameOfficialHost(quote.sourceUrl, official));
        if (page.ok && !quotes.length) reason = "Resmî fiyat doğrulanamadı";
      }
    } catch {
      reason = "Resmî fiyat doğrulanamadı";
    }
    results.push({
      facilityId: place.id,
      facilityName: place.isim ?? "",
      il: place.il ?? "",
      ilce: place.ilce ?? "",
      officialUrl: official,
      items: Array.isArray(place.ucretBilgisi?.kalemler) ? place.ucretBilgisi.kalemler : [],
      quotes,
      reason,
    });
    if (pauseMs > 0) await delay(pauseMs);
  }
  return results;
}

async function main() {
  const year = Number(process.env.THERMAL_TARIFF_YEAR || new Date().getFullYear());
  const source = process.env.KIS_KESFET_URL || "https://raw.githubusercontent.com/Serdarza/rotalink-data/main/kis_kesfet/data/kis_kesfet.json";
  const response = await fetch(source, { headers: { "User-Agent": USER_AGENT }, signal: AbortSignal.timeout(20000) });
  if (!response.ok) throw new Error("Tesis listesi indirilemedi.");
  const body = await response.json();
  const facilities = Array.isArray(body.kayitlar) ? body.kayitlar.filter((row) => row.kategori === "termal") : [];
  const checkedAt = new Date().toLocaleDateString("en-CA", { timeZone: "Europe/Istanbul" });
  const cacheDir = process.env.THERMAL_CACHE_DIR;
  if (cacheDir) await mkdir(cacheDir, { recursive: true });
  const results = await scanFacilities(facilities, year, Number(process.env.THERMAL_DELAY_MS || 1500));
  const payload = {
    scanId: checkedAt.slice(0, 7),
    checkedAt,
    year,
    catalogSha: createHash("sha256").update(JSON.stringify(facilities.map((row) => row.id))).digest("hex").slice(0, 16),
    results,
  };
  if (cacheDir) await writeFile(cacheDir + "/last-scan.json", JSON.stringify(payload));
  const token = process.env.THERMAL_SCAN_TOKEN || "";
  const ingest = process.env.THERMAL_INGEST_URL || "";
  if (!token || !ingest) throw new Error("THERMAL_SCAN_TOKEN veya THERMAL_INGEST_URL eksik. Canlı fiyat yazılmadı.");
  const saved = await fetch(ingest, {
    method: "POST",
    headers: { Authorization: "Bearer " + token, "Content-Type": "application/json", "User-Agent": USER_AGENT },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(30000),
  });
  if (!saved.ok) throw new Error("Onay kuyruğuna yazılamadı: HTTP " + saved.status);
  const summary = await saved.json();
  console.log(JSON.stringify({ scanId: payload.scanId, facilities: facilities.length, pending: summary.pending ?? null }));
}

const ranDirectly = process.argv[1] && process.argv[1].replaceAll("\\", "/").endsWith("scripts/thermal_price_scan.mjs");
if (ranDirectly) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : "Tarama tamamlanamadı.");
    process.exitCode = 1;
  });
}
