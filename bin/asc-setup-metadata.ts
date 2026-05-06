// One-shot setup of App Store Connect metadata for ExpressCharge.
// Idempotent — safe to re-run when content changes.
//
// Fills in everything that doesn't require human-supplied creative
// content (categories, age rating, content rights, contact info,
// boilerplate description, support / marketing / privacy URLs).
//
// What still needs a human:
//   - Real privacy policy text behind the URL
//   - Screenshots
//   - Final marketing copy (description / promotional text), reviewing
//     the placeholders this script writes
//
// Env (so secrets stay out of the script):
//   ASC_API_KEY_PATH, ASC_API_KEY_ID, ASC_API_ISSUER_ID, ASC_APP_ID

const KEY_PATH = Deno.env.get("ASC_API_KEY_PATH")!;
const KEY_ID = Deno.env.get("ASC_API_KEY_ID")!;
const ISSUER_ID = Deno.env.get("ASC_API_ISSUER_ID")!;
const APP_ID = Deno.env.get("ASC_APP_ID")!;

// Content the user can edit later in App Store Connect or by changing
// the constants below and re-running this script.
const SUPPORT_URL = "https://polaris.express";
const MARKETING_URL = "https://polaris.express";
const PRIVACY_URL = "https://polaris.express/privacy";
const FEEDBACK_EMAIL = "support@polaris.express";
const CONTACT_FIRST = "Vlad";
const CONTACT_LAST = "Zaharia";
// Apple validates the phone format strictly. Setting null skips the
// Beta App Review Detail update; set a real number to enable external
// Beta App Review submissions.
const CONTACT_PHONE: string | null = "+12063563646";
const PRIMARY_CATEGORY = "TRAVEL";
const SECONDARY_CATEGORY = "UTILITIES";

const APP_DESCRIPTION = `ExpressCharge turns your iPhone into a tap-to-start key for Polaris EV charging stations. Tap a Polaris charge card to your phone, the station verifies your account, and your session begins — no app to launch, no QR code to scan, no waiting.

Built for the rare moment when your card isn't where you'd expect: tap your card to your phone, and we'll relay the verification to the station for you.

Features
• Tap-to-start: hold a Polaris charge card to your phone to begin a session.
• Live status: see whether the station is reachable and your account is in good standing before you tap.
• Secure by design: your account credentials never leave the keychain; sessions are signed end to end.

ExpressCharge requires a Polaris account and a registered NFC charge card. Visit polaris.express to sign up.`;

const PROMOTIONAL_TEXT =
  "Tap a Polaris charge card to your phone to start charging — no app to launch, no QR scan.";

const KEYWORDS = "ev,charging,nfc,polaris,charge,electric vehicle,charger,tap";

const BETA_DESCRIPTION =
  "Internal beta of the ExpressCharge iOS companion app — pair a Polaris charge card via NFC to start a charging session at any registered station.";

// App Store version metadata (per-version, not per-app).
const APP_COPYRIGHT = `${new Date().getFullYear()} Polaris Express`;
const APP_VERSION_RELEASE_NOTES =
  "Initial release of ExpressCharge for iOS — tap a Polaris charge card to your phone to start a charging session at any registered Polaris station.";

// ---------------------------------------------------------------------------
// JWT + API helpers
// ---------------------------------------------------------------------------

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
  // deno-lint-ignore no-explicit-any
): Promise<any> {
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
    throw new Error(`ASC ${res.status} ${path}: ${text}`);
  }
  return text ? JSON.parse(text) : {};
}

function step(msg: string) {
  console.log(`→ ${msg}`);
}

function ok(msg: string) {
  console.log(`  ✓ ${msg}`);
}

function note(msg: string) {
  console.log(`  · ${msg}`);
}

// ---------------------------------------------------------------------------
// Step 1 — App Info: categories, content rights, age rating
// ---------------------------------------------------------------------------

step("setting categories + content rights + age rating");
const appInfos = await api(`/v1/apps/${APP_ID}/appInfos`);
const appInfo = appInfos.data.find((a: { attributes: { appStoreState: string } }) =>
  a.attributes.appStoreState === "PREPARE_FOR_SUBMISSION"
) ?? appInfos.data[0];
const APPINFO_ID = appInfo.id;

await api(`/v1/appInfos/${APPINFO_ID}`, {
  method: "PATCH",
  body: JSON.stringify({
    data: {
      type: "appInfos",
      id: APPINFO_ID,
      relationships: {
        primaryCategory: {
          data: { type: "appCategories", id: PRIMARY_CATEGORY },
        },
        secondaryCategory: {
          data: { type: "appCategories", id: SECONDARY_CATEGORY },
        },
      },
    },
  }),
});
ok(`primary=${PRIMARY_CATEGORY}, secondary=${SECONDARY_CATEGORY}`);

// Content rights — confirm we don't use third-party content
await api(`/v1/apps/${APP_ID}`, {
  method: "PATCH",
  body: JSON.stringify({
    data: {
      type: "apps",
      id: APP_ID,
      attributes: {
        contentRightsDeclaration: "DOES_NOT_USE_THIRD_PARTY_CONTENT",
      },
    },
  }),
});
ok("content rights = DOES_NOT_USE_THIRD_PARTY_CONTENT");

// Age rating — utility app, no age-restricted content
// Apple's schema mixes types: most fields are FrequencyOfOccurrence
// enums ("NONE" / "INFREQUENT_OR_MILD" / "FREQUENT_OR_INTENSE"), but
// `gambling`, `unrestrictedWebAccess`, and `userGeneratedContent` are
// booleans. `contests` looks boolean by name but is actually the enum.
await api(`/v1/ageRatingDeclarations/${APPINFO_ID}`, {
  method: "PATCH",
  body: JSON.stringify({
    data: {
      type: "ageRatingDeclarations",
      id: APPINFO_ID,
      attributes: {
        // FrequencyOfOccurrence enums
        alcoholTobaccoOrDrugUseOrReferences: "NONE",
        contests: "NONE",
        gamblingSimulated: "NONE",
        horrorOrFearThemes: "NONE",
        matureOrSuggestiveThemes: "NONE",
        medicalOrTreatmentInformation: "NONE",
        profanityOrCrudeHumor: "NONE",
        sexualContentGraphicAndNudity: "NONE",
        sexualContentOrNudity: "NONE",
        violenceCartoonOrFantasy: "NONE",
        violenceRealistic: "NONE",
        violenceRealisticProlongedGraphicOrSadistic: "NONE",
        gunsOrOtherWeapons: "NONE",
        // booleans (V2-schema additions are all booleans)
        messagingAndChat: false,
        healthOrWellnessTopics: false,
        advertising: false,
        ageAssurance: false,
        lootBox: false,
        parentalControls: false,
        gambling: false,
        unrestrictedWebAccess: false,
        userGeneratedContent: false,
        // overrides — V2 only; V1 ageRatingOverride conflicts when V2 is set
        ageRatingOverrideV2: "NONE",
        koreaAgeRatingOverride: "NONE",
      },
    },
  }),
});
ok("age rating declaration = all clear (4+)");

// ---------------------------------------------------------------------------
// Step 2 — App Store Version 1.0 localization (en-US)
// ---------------------------------------------------------------------------

step("filling App Store version 1.0 metadata");
const versions = await api(`/v1/apps/${APP_ID}/appStoreVersions?limit=5`);
const version = versions.data[0]; // most recent — currently 1.0 PREPARE_FOR_SUBMISSION
const VERSION_ID = version.id;

// Per-version attributes: copyright, usesIdfa, releaseType.
await api(`/v1/appStoreVersions/${VERSION_ID}`, {
  method: "PATCH",
  body: JSON.stringify({
    data: {
      type: "appStoreVersions",
      id: VERSION_ID,
      attributes: {
        copyright: APP_COPYRIGHT,
        usesIdfa: false, // App does not use the advertising identifier
        releaseType: "AFTER_APPROVAL",
      },
    },
  }),
});
ok(`version attrs: copyright="${APP_COPYRIGHT}", usesIdfa=false, releaseType=AFTER_APPROVAL`);

const locs = await api(
  `/v1/appStoreVersions/${VERSION_ID}/appStoreVersionLocalizations`,
);
const enUS = locs.data.find((l: { attributes: { locale: string } }) =>
  l.attributes.locale === "en-US"
);
// Version-localization fields that are always writable on a draft.
const versionLocAttrs: Record<string, unknown> = {
  description: APP_DESCRIPTION,
  keywords: KEYWORDS,
  marketingUrl: MARKETING_URL,
  promotionalText: PROMOTIONAL_TEXT,
  supportUrl: SUPPORT_URL,
};

if (!enUS) {
  await api(`/v1/appStoreVersionLocalizations`, {
    method: "POST",
    body: JSON.stringify({
      data: {
        type: "appStoreVersionLocalizations",
        attributes: { ...versionLocAttrs, locale: "en-US" },
        relationships: {
          appStoreVersion: {
            data: { type: "appStoreVersions", id: VERSION_ID },
          },
        },
      },
    }),
  });
  ok(`created en-US version localization`);
} else {
  await api(`/v1/appStoreVersionLocalizations/${enUS.id}`, {
    method: "PATCH",
    body: JSON.stringify({
      data: {
        type: "appStoreVersionLocalizations",
        id: enUS.id,
        attributes: versionLocAttrs,
      },
    }),
  });
  ok(`updated en-US version localization`);
}

// Try to set whatsNew (release notes) separately. Apple locks this field
// on the very first version of an app — there's nothing to be "new" since
// — so a 409 with "cannot be edited at this time" is expected on v1.0
// and shouldn't fail the bootstrap. On later versions the same code path
// will succeed.
const targetLocId = enUS?.id ??
  // Re-fetch if we just created it.
  ((await api(
    `/v1/appStoreVersions/${VERSION_ID}/appStoreVersionLocalizations`,
  )) as { data: Array<{ id: string; attributes: { locale: string } }> })
    .data
    .find((l) => l.attributes.locale === "en-US")?.id;
if (targetLocId) {
  try {
    await api(`/v1/appStoreVersionLocalizations/${targetLocId}`, {
      method: "PATCH",
      body: JSON.stringify({
        data: {
          type: "appStoreVersionLocalizations",
          id: targetLocId,
          attributes: { whatsNew: APP_VERSION_RELEASE_NOTES },
        },
      }),
    });
    ok("whatsNew (App Store release notes) set");
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    if (msg.includes("cannot be edited at this time")) {
      note(
        "whatsNew skipped — locked on first version (will succeed on next release)",
      );
    } else {
      throw err;
    }
  }
}

// Link the most-recently-uploaded VALID build to this version. Without
// this, App Store review submission has no binary to review. The
// relationship is one-to-one; PATCHing replaces any prior assignment.
step("linking the latest VALID build to version 1.0");
const builds = await api(
  `/v1/builds?filter%5Bapp%5D=${APP_ID}&filter%5BprocessingState%5D=VALID&sort=-uploadedDate&limit=1`,
);
const latestBuild = builds.data[0];
if (latestBuild) {
  await api(`/v1/appStoreVersions/${VERSION_ID}/relationships/build`, {
    method: "PATCH",
    body: JSON.stringify({
      data: { type: "builds", id: latestBuild.id },
    }),
  });
  ok(`linked build ${latestBuild.attributes.version} (id ${latestBuild.id})`);
} else {
  note("no VALID builds yet — skipped (re-run after a successful TestFlight upload)");
}

// ---------------------------------------------------------------------------
// Step 3 — Beta App Localization (Test Info)
// ---------------------------------------------------------------------------

step("filling Beta Test Info (en-US)");
const betaLocs = await api(`/v1/apps/${APP_ID}/betaAppLocalizations`);
const betaEnUS = betaLocs.data.find((l: { attributes: { locale: string } }) =>
  l.attributes.locale === "en-US"
);
if (!betaEnUS) {
  await api(`/v1/betaAppLocalizations`, {
    method: "POST",
    body: JSON.stringify({
      data: {
        type: "betaAppLocalizations",
        attributes: {
          locale: "en-US",
          feedbackEmail: FEEDBACK_EMAIL,
          marketingUrl: MARKETING_URL,
          privacyPolicyUrl: PRIVACY_URL,
          tvOsPrivacyPolicy: null,
          description: BETA_DESCRIPTION,
        },
        relationships: {
          app: { data: { type: "apps", id: APP_ID } },
        },
      },
    }),
  });
  ok(`created en-US beta localization`);
} else {
  await api(`/v1/betaAppLocalizations/${betaEnUS.id}`, {
    method: "PATCH",
    body: JSON.stringify({
      data: {
        type: "betaAppLocalizations",
        id: betaEnUS.id,
        attributes: {
          feedbackEmail: FEEDBACK_EMAIL,
          marketingUrl: MARKETING_URL,
          privacyPolicyUrl: PRIVACY_URL,
          description: BETA_DESCRIPTION,
        },
      },
    }),
  });
  ok(`updated en-US beta localization`);
}

// ---------------------------------------------------------------------------
// Step 4 — Beta App Review Detail (for external testing review)
// ---------------------------------------------------------------------------

step("filling Beta App Review contact info");
const betaReview = await api(`/v1/apps/${APP_ID}/betaAppReviewDetail`);
const BETA_REVIEW_ID = betaReview.data.id;
// Apple's PATCH validator on betaAppReviewDetails requires a non-null
// contactPhone in any payload that touches the entity, even if name +
// email are the only fields you actually want to set. Skip the whole
// step when CONTACT_PHONE isn't filled in — only external Beta App
// Review needs this entity, and internal TestFlight ignores it.
if (CONTACT_PHONE) {
  await api(`/v1/betaAppReviewDetails/${BETA_REVIEW_ID}`, {
    method: "PATCH",
    body: JSON.stringify({
      data: {
        type: "betaAppReviewDetails",
        id: BETA_REVIEW_ID,
        attributes: {
          contactFirstName: CONTACT_FIRST,
          contactLastName: CONTACT_LAST,
          contactEmail: FEEDBACK_EMAIL,
          contactPhone: CONTACT_PHONE,
          demoAccountRequired: false,
          notes:
            "Internal/external beta testers will use their existing Polaris account credentials at https://polaris.express to register the device and an NFC charge card to test the tap-to-start flow.",
        },
      },
    }),
  });
} else {
  console.log("  · skipped (set CONTACT_PHONE in this script and re-run before external Beta App Review)");
}
if (CONTACT_PHONE) {
  ok(`Beta App Review contact = ${CONTACT_FIRST} ${CONTACT_LAST} <${FEEDBACK_EMAIL}>`);
}

// ---------------------------------------------------------------------------
// Done — what still needs human attention
// ---------------------------------------------------------------------------

console.log("");
console.log("✓ ASC metadata bootstrap complete");
console.log("");
console.log("Web-UI-only (App Store Connect API doesn't expose these):");
note("App Privacy / Privacy Nutrition Labels — declare data types collected at https://appstoreconnect.apple.com/apps/" + APP_ID + "/distribution/privacy");
note("Pricing & availability — defaults to free in all territories; adjust at https://appstoreconnect.apple.com/apps/" + APP_ID + "/pricing");
console.log("");
console.log("Content the bootstrap can't autogenerate:");
note(`Privacy policy at ${PRIVACY_URL} is published; review the actual policy text whenever the data flows change.`);
note("Screenshots (required for App Store submission, not TestFlight) — capture from a real device once the UI is final.");
note("Review the description / keywords / promotional text in App Store Connect and tweak the marketing copy.");
