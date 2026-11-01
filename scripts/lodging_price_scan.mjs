/**
 * Konaklama tesislerini GitHub'daki güncel listeden okur.
 * Canlı fiyat yazmaz. Metin yönetici onay kuyruğuna gider.
 */
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { setTimeout as delay } from "node:timers/promises";

const USER_AGENT = "RotalinkPriceCheck/1.0 (+https://rotalink.tr)";

function hostOf(raw) {
  try {
    const url = new URL(raw);
    return url.protocol === "https:" ? url.hostname.toLowerCase().replace(/^www\./, "") : "";
  } catch {
    return "";
  }
}

function active(row) {
  if (row?.aktif === false) return false;
  return String(row?.durum ?? "").toLocaleLowerCase("tr") !== "pasif";
}

export function selectFacilities(facilities, prices) {
  const priceByKey = new Map();
  for (const row of prices) {
    const key = `${String(row.il ?? "").toLocaleLowerCase("tr")}|${String(row.isim ?? "").toLocaleLowerCase("tr")}`;
    priceByKey.set(key, row);
  }
  const counts = new Map();
  for (const row of facilities) {
    if (!active(row)) continue;
    const key = `${String(row.il ?? "").toLocaleLowerCase("tr")}|${String(row.isim ?? "").toLocaleLowerCase("tr")}`;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  const selected = [];
  const errors = [];
  for (const row of facilities) {
    if (!active(row) || !row.il || !row.isim) continue;
    const key = `${String(row.il).toLocaleLowerCase("tr")}|${String(row.isim).toLocaleLowerCase("tr")}`;
    if (counts.get(key) !== 1) {
      if (!errors.includes(key)) errors.push(key);
      continue;
    }
    const price = priceByKey.get(key);
    selected.push({
      il: row.il,
      isim: row.isim,
      ilce: row.ilce ?? "",
      tip: row.tip ?? "",
      officialUrl: typeof price?.kaynak === "string" ? price.kaynak : "",
    });
  }
  return { selected, errors: errors.length };
}

async function fetchText(url) {
  if (!hostOf(url)) return "";
  let current = url;
  for (let hop = 0; hop < 3; hop += 1) {
    const response = await fetch(current, {
      headers: { "User-Agent": USER_AGENT, Accept: "text/html,application/pdf" },
      redirect: "manual",
      signal: AbortSignal.timeout(15000),
    });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const next = response.headers.get("location");
      if (!next || hostOf(new URL(next, current).href) !== hostOf(url)) return "";
      current = new URL(next, current).href;
      continue;
    }
    if (!response.ok) return "";
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.byteLength > 1_500_000) return "";
    return priceExcerpt(new TextDecoder("utf-8", { fatal: false }).decode(bytes));
  }
  return "";
}

function priceExcerpt(text) {
  const clean = text.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ");
  const parts = [];
  for (const sentence of clean.split(/\n|(?<=[.!])\s+/)) {
    if (!/TL|₺/i.test(sentence)) continue;
    parts.push(sentence.trim());
    if (parts.join(" ").length > 1800) break;
  }
  return parts.join(" ").slice(0, 1800);
}

async function main() {
  const year = Number(process.env.LODGING_TARIFF_YEAR || new Date().getFullYear());
  const facilitiesUrl = process.env.LODGING_CATALOG_URL || "https://raw.githubusercontent.com/Serdarza/rotalink-data/main/master_database_updated.json";
  const pricesUrl = process.env.LODGING_PRICES_URL || "https://raw.githubusercontent.com/Serdarza/rotalink-data/main/fiyatlar.json";
  const [facilityBody, priceBody] = await Promise.all([
    fetch(facilitiesUrl, { headers: { "User-Agent": USER_AGENT }, signal: AbortSignal.timeout(30000) }).then((response) => response.json()),
    fetch(pricesUrl, { headers: { "User-Agent": USER_AGENT }, signal: AbortSignal.timeout(30000) }).then((response) => response.json()),
  ]);
  const { selected, errors } = selectFacilities(facilityBody.tesisler ?? [], priceBody.tesisler ?? []);
  const offset = Math.max(0, Number(process.env.LODGING_OFFSET || 0));
  const limit = Math.max(0, Number(process.env.LODGING_LIMIT || 0));
  const slice = selected.slice(offset, limit > 0 ? offset + limit : undefined);
  const token = process.env.THERMAL_SCAN_TOKEN || "";
  const ingest = process.env.LODGING_INGEST_URL || "";
  if (!token || !ingest) throw new Error("THERMAL_SCAN_TOKEN veya LODGING_INGEST_URL eksik. Canlı fiyat yazılmadı.");
  const checkedAt = new Date().toLocaleDateString("en-CA", { timeZone: "Europe/Istanbul" });
  const cacheDir = process.env.LODGING_CACHE_DIR;
  if (cacheDir) await mkdir(cacheDir, { recursive: true });
  const maxBytes = 160000;
  let batch = [];
  let batchBytes = 200;
  let scanned = 0;
  async function send(results) {
    if (!results.length) return;
    const response = await fetch(ingest, {
      method: "POST",
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json", "User-Agent": USER_AGENT },
      body: JSON.stringify({ scanId: checkedAt.slice(0, 7), checkedAt, year, total: selected.length, errors, results }),
      signal: AbortSignal.timeout(30000),
    });
    if (!response.ok) throw new Error("Onay kuyruğuna yazılamadı: HTTP " + response.status);
  }
  for (const place of slice) {
    let text = "";
    if (place.officialUrl) {
      try { text = await fetchText(place.officialUrl); } catch { text = ""; }
      await delay(Number(process.env.LODGING_DELAY_MS || 800));
    }
    const item = { il: place.il, isim: place.isim, ilce: place.ilce, tip: place.tip, officialUrl: place.officialUrl, text };
    const extra = JSON.stringify(item).length + 1;
    if (batch.length && batchBytes + extra > maxBytes) {
      await send(batch);
      if (cacheDir) await writeFile(cacheDir + "/lodging-offset.txt", String(offset + scanned));
      batch = [];
      batchBytes = 200;
    }
    batch.push(item);
    batchBytes += extra;
    scanned += 1;
  }
  await send(batch);
  console.log(JSON.stringify({ total: selected.length, scanned, errors, offset }));
}

const ranDirectly = process.argv[1] && process.argv[1].replaceAll("\\", "/").endsWith("scripts/lodging_price_scan.mjs");
if (ranDirectly) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : "Tarama tamamlanamadı.");
    process.exitCode = 1;
  });
}
