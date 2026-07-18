// ─── Kwik Video Host Extractor ──────────────────────────────────────
// animepahe embeds videos from kwik.si (primary) and sometimes
// mp4upload or streamsb as fallbacks.
//
// Kwik extraction flow:
//   1. Get pahewin response which gives a kwik URL like:
//      https://kwik.si/f/<token>
//   2. POST to kwik with form data: _token=<csrftoken>&kwik=<aes_token>
//   3. Parse response HTML for M3U8 manifest URL
//
// The kwik page requires JavaScript but we can extract the M3U8
// directly from the embedded JavaScript variable.

const KWIK_BASE = "https://kwik.si";

interface KwikPageData {
  csrfToken: string;
  kwikToken: string;
  m3u8: string | null;
}

export async function extractKwikUrl(
  kwikPageUrl: string,
  fetchFn: typeof fetch = fetch
): Promise<string | null> {
  try {
    // Step 1: Fetch the kwik page
    const pageResp = await fetchFn(kwikPageUrl, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        Accept: "text/html,application/xhtml+xml",
        Referer: "https://animepahe.pw/",
      },
    });

    const html = await pageResp.text();

    // Step 2: Extract the M3U8 from JavaScript variable
    // Kwik stores the M3U8 in JS: var _v = "https://...m3u8";
    const m3u8Match = html.match(/var\s+_v\s*=\s*["']([^"']+)["']/);
    if (m3u8Match?.[1]) {
      return m3u8Match[1];
    }

    // Alternative pattern: player source
    const sourceMatch = html.match(/source\s+src=["']([^"']+\.m3u8[^"']*)["']/);
    if (sourceMatch?.[1]) {
      return sourceMatch[1];
    }

    // Alternative: direct in eval or new URL
    const evalMatch = html.match(/["'](https?:\/\/[^"']+\.m3u8[^"']*)["']/);
    if (evalMatch?.[1]) {
      return evalMatch[1];
    }

    // Step 3: If no direct M3U8, try the POST approach
    const csrfMatch = html.match(
      /name=["']_token["']\s+value=["']([^"']+)["']/
    );
    const kwikMatch = html.match(
      /name=["']kwik["']\s+value=["']([^"']+)["']/
    );

    if (csrfMatch?.[1] && kwikMatch?.[1]) {
      const formData = new URLSearchParams();
      formData.set("_token", csrfMatch[1]);
      formData.set("kwik", kwikMatch[1]);

      const postResp = await fetchFn(kwikPageUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "User-Agent":
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
          Referer: kwikPageUrl,
          Origin: KWIK_BASE,
        },
        body: formData.toString(),
      });

      const postHtml = await postResp.text();
      const postM3u8 = postHtml.match(
        /["'](https?:\/\/[^"']+\.m3u8[^"']*)["']/
      );
      if (postM3u8?.[1]) {
        return postM3u8[1];
      }
    }

    return null;
  } catch (err) {
    console.error("[kwik] Extraction failed:", err);
    return null;
  }
}

/**
 * Resolve an animepahe video source URL to a playable stream.
 * Handles kwik and other hosts.
 */
export async function resolveVideoUrl(
  sourceUrl: string,
  fetchFn: typeof fetch = fetch
): Promise<string | null> {
  const url = sourceUrl.toLowerCase();

  if (url.includes("kwik")) {
    return extractKwikUrl(sourceUrl, fetchFn);
  }

  // Direct M3U8 or MP4 URLs can be returned directly
  if (url.endsWith(".m3u8") || url.endsWith(".mp4")) {
    return sourceUrl;
  }

  // mp4upload / streamsb require browser JS and are not easily
  // extracted without headless browser.
  return sourceUrl;
}
