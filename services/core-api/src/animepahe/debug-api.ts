import puppeteer from "puppeteer-extra";
import StealthPlugin from "puppeteer-extra-plugin-stealth";
puppeteer.use(StealthPlugin());

async function test(url: string, page: any) {
  const r = await page.evaluate(async (u: string) => {
    try {
      const resp = await fetch(u, { credentials: "include" });
      const t = await resp.text();
      return { status: resp.status, len: t.length, cf: t.includes("Just a moment"), preview: t.substring(0, 80) };
    } catch(e: any) { return { error: e.message }; }
  }, url);
  console.log(`  ${url.substring(0, 70)}  -> status=${r.status} cf=${r.cf} len=${r.len} preview=${r.preview}`);
}

async function main() {
  const browser = await puppeteer.launch({
    headless: false,
    args: ["--no-sandbox","--disable-setuid-sandbox","--window-size=1200,800"],
  });
  const page = await browser.newPage();

  console.log("Opening animepahe.pw...");
  await page.goto("https://animepahe.pw/", { waitUntil: "domcontentloaded", timeout: 15000 }).catch(()=>{});
  console.log("Page title:", await page.title().catch(()=>"err"));

  // Wait 10s for potential auto-solve
  console.log("Waiting 10s for potential auto-solve...");
  await new Promise(r => setTimeout(r, 10000));
  console.log("Title after wait:", await page.title().catch(()=>"err"));

  // Check available cookies
  const cookies = await page.cookies();
  console.log("\nCookies:", cookies.filter(c=>c.domain?.includes("animepahe")).map(c=>c.name));

  console.log("\nTesting endpoints:");
  await test("https://animepahe.pw/api?m=search&q=test", page);
  await test("https://animepahe.pw/api?m=airing", page);
  await test("https://animepahe.pw/api?m=feed", page);
  await test("https://animepahe.pw/api?m=genre", page);
  await test("https://animepahe.pw/api", page);
  await test("https://animepahe.pw/", page);

  // Try animepahe.com
  console.log("\nTrying animepahe.com...");
  await page.goto("https://animepahe.com/", { waitUntil: "domcontentloaded", timeout: 15000 }).catch(()=>{});
  const c2 = await page.cookies();
  console.log("Cookies:", c2.filter((c: any)=>c.domain?.includes("animepahe")).map((c: any)=>c.name));

  await test("https://animepahe.com/api?m=search&q=test", page);

  await browser.close();
}
main();
