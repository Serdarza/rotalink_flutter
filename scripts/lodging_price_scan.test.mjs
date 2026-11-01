import assert from "node:assert/strict";
import test from "node:test";
import { selectFacilities } from "./lodging_price_scan.mjs";

test("pasif tesis dışarıda kalır, aynı il ve ad karışmaz, yeni kayıt kapsamdadır", () => {
  const { selected, errors } = selectFacilities([
    { il: "Kayseri", isim: "Açık Tesis" },
    { il: "Kayseri", isim: "Kapalı Tesis", durum: "pasif" },
    { il: "Kayseri", isim: "Çift Tesis" },
    { il: "Kayseri", isim: "Çift Tesis" },
    { il: "Ankara", isim: "Yeni Tesis", aktif: true },
  ], [
    { il: "Kayseri", isim: "Açık Tesis", kaynak: "https://ornek.bel.tr/tarife" },
  ]);
  assert.equal(errors, 1);
  assert.deepEqual(selected.map((row) => row.isim), ["Açık Tesis", "Yeni Tesis"]);
  assert.equal(selected[0].officialUrl, "https://ornek.bel.tr/tarife");
  assert.equal(selected[1].officialUrl, "");
});
