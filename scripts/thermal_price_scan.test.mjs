import assert from "node:assert/strict";
import test from "node:test";
import { blockedHost, extractQuotes, robotsAllows, sameOfficialHost } from "./thermal_price_scan.mjs";

test("2026 cümlesindeki havuz ücretini ayırır", () => {
  const quotes = extractQuotes(
    "2025 yılı girişi 100 TL. 2026 yılı günlük havuz ücreti 350 TL'dir. Çocuk indirimi 2026 yılında 50 TL.",
    "https://tesis.bel.tr/tarife",
    2026,
  );
  assert.equal(quotes.length, 1);
  assert.equal(quotes[0].category, "havuz");
  assert.equal(quotes[0].amount, 350);
  assert.equal(quotes[0].starting, true);
});

test("başka yılı 2026 fiyatı saymaz", () => {
  const quotes = extractQuotes("2025 yılı giriş ücreti 200 TL.", "https://tesis.bel.tr/tarife", 2026);
  assert.deepEqual(quotes, []);
});

test("binlik tutarı okur ve dövizi reddeder", () => {
  assert.equal(extractQuotes("2026 yılı oda ücreti 2.500 TL.", "https://tesis.bel.tr/a", 2026)[0].amount, 2500);
  assert.deepEqual(extractQuotes("2026 yılı giriş 40 EUR.", "https://tesis.bel.tr/a", 2026), []);
});

test("üçüncü taraf ve iç adres resmi kaynak değildir", () => {
  assert.equal(sameOfficialHost("https://www.booking.com/x", "https://www.booking.com/y"), false);
  assert.equal(sameOfficialHost("https://tarif.tesis.bel.tr/fiyat", "https://www.tesis.bel.tr/"), true);
  assert.equal(blockedHost("blog.kamutesisleri.com"), true);
});

test("robots engelini aşmaz", () => {
  assert.equal(robotsAllows("User-agent: *\nDisallow: /tarife", "/tarife/2026"), false);
  assert.equal(robotsAllows("User-agent: *\nDisallow: /gizli", "/tarife"), true);
});
