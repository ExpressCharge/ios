// Set the "What to Test" (whatsNew) note on a TestFlight build's
// BetaBuildLocalization for en-US. Creates the localization if it
// doesn't exist, otherwise PATCHes the existing one.
//
// Usage:
//   ASC_API_KEY_PATH=… ASC_API_KEY_ID=… ASC_API_ISSUER_ID=… ASC_APP_ID=… \
//   deno run --allow-read=KEY --allow-env=… --allow-net=api.appstoreconnect.apple.com \
//     bin/asc-set-whats-new.ts <buildVersion> <whatsNewText>

const buildVersion = Deno.args[0];
const whatsNewText = Deno.args[1];
if (!buildVersion || !whatsNewText) {
  console.error(
    "usage: asc-set-whats-new.ts <buildVersion> <whatsNewText>",
  );
  Deno.exit(2);
}

const KEY_PATH = Deno.env.get("ASC_API_KEY_PATH")!;
const KEY_ID = Deno.env.get("ASC_API_KEY_ID")!;
const ISSUER_ID = Deno.env.get("ASC_API_ISSUER_ID")!;
const APP_ID = Deno.env.get("ASC_APP_ID")!;

async function jwt(): Promise<string> {
  const pem = await Deno.readTextFile(KEY_PATH);
  const body = pem.replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der.buffer,
    { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
  );
  const header = { alg: "ES256", kid: KEY_ID, typ: "JWT" };
  const payload = {
    iss: ISSUER_ID,
    exp: Math.floor(Date.now() / 1000) + 1200,
    aud: "appstoreconnect-v1",
  };
  const b64u = (s: string) =>
    btoa(s).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
  const input = `${b64u(JSON.stringify(header))}.${b64u(JSON.stringify(payload))}`;
  const sig = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(input),
    ),
  );
  let bin = "";
  for (const b of sig) bin += String.fromCharCode(b);
  return `${input}.${
    btoa(bin).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "")
  }`;
}

async function api(
  path: string,
  init: RequestInit = {},
): Promise<unknown> {
  const t = await jwt();
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${t}`,
      "Content-Type": "application/json",
      ...(init.headers || {}),
    },
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`ASC ${res.status} ${res.statusText}: ${text}`);
  }
  return text ? JSON.parse(text) : {};
}

// 1. Find the build by version
const buildsUrl =
  `/v1/builds?filter%5Bapp%5D=${APP_ID}&filter%5Bversion%5D=${buildVersion}&sort=-uploadedDate&limit=1`;
const buildsRes = await api(buildsUrl) as {
  data: Array<{ id: string }>;
};
const buildId = buildsRes.data[0]?.id;
if (!buildId) throw new Error(`build ${buildVersion} not found in ASC`);

// 2. Look up existing BetaBuildLocalization for en-US, if any
const locsRes = await api(
  `/v1/builds/${buildId}/betaBuildLocalizations`,
) as { data: Array<{ id: string; attributes: { locale: string } }> };
const enUS = locsRes.data.find((l) => l.attributes.locale === "en-US");

if (enUS) {
  await api(`/v1/betaBuildLocalizations/${enUS.id}`, {
    method: "PATCH",
    body: JSON.stringify({
      data: {
        type: "betaBuildLocalizations",
        id: enUS.id,
        attributes: { whatsNew: whatsNewText },
      },
    }),
  });
  console.log(`  ✓ updated en-US whatsNew on build ${buildVersion}`);
} else {
  await api("/v1/betaBuildLocalizations", {
    method: "POST",
    body: JSON.stringify({
      data: {
        type: "betaBuildLocalizations",
        attributes: { locale: "en-US", whatsNew: whatsNewText },
        relationships: {
          build: { data: { type: "builds", id: buildId } },
        },
      },
    }),
  });
  console.log(`  ✓ created en-US whatsNew on build ${buildVersion}`);
}
