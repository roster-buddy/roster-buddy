const allowedOrigins = new Set([
  "https://roster-buddy.github.io",
  "http://localhost",
  "http://localhost:3000",
  "http://localhost:8080",
]);

function corsHeaders(request: Request): Record<string, string> {
  const origin = request.headers.get("origin") ?? "";
  const allowedOrigin = allowedOrigins.has(origin)
    ? origin
    : "https://roster-buddy.github.io";

  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function jsonResponse(
  request: Request,
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(request),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function decodeBase64(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);

  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }

  return bytes;
}

function numberValue(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function safeErrorMessage(payload: Record<string, unknown>): string {
  const message = payload.ErrorMessage ?? payload.ErrorDetails;
  if (Array.isArray(message)) {
    return message.map(String).filter(Boolean).join(" ");
  }
  if (typeof message === "string" && message.trim()) {
    return message.trim();
  }
  return "The secure scanner could not read this document.";
}

function normalisePages(payload: Record<string, unknown>) {
  const parsedResults = payload.ParsedResults;
  if (!Array.isArray(parsedResults)) {
    return [];
  }

  return parsedResults.map((rawPage) => {
    const page = rawPage && typeof rawPage === "object"
      ? rawPage as Record<string, unknown>
      : {};
    const overlay = page.TextOverlay && typeof page.TextOverlay === "object"
      ? page.TextOverlay as Record<string, unknown>
      : {};
    const overlayLines = Array.isArray(overlay.Lines) ? overlay.Lines : [];
    const words: Array<Record<string, unknown>> = [];

    for (const rawLine of overlayLines) {
      const line = rawLine && typeof rawLine === "object"
        ? rawLine as Record<string, unknown>
        : {};
      const lineWords = Array.isArray(line.Words) ? line.Words : [];

      for (const rawWord of lineWords) {
        const word = rawWord && typeof rawWord === "object"
          ? rawWord as Record<string, unknown>
          : {};
        const text = String(word.WordText ?? "").trim();
        if (!text) continue;

        const left = numberValue(word.Left);
        const top = numberValue(word.Top);
        const width = numberValue(word.Width);
        const height = numberValue(word.Height);

        words.push({
          text,
          left,
          top,
          right: left + width,
          bottom: top + height,
        });
      }
    }

    return {
      fullText: String(page.ParsedText ?? ""),
      confidence: null,
      lines: words,
    };
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(request) });
  }

  if (request.method !== "POST") {
    return jsonResponse(request, { error: "Method not allowed." }, 405);
  }

  const apiKey = Deno.env.get("OCR_SPACE_API_KEY")?.trim();
  if (!apiKey) {
    return jsonResponse(
      request,
      { error: "The secure scanner has not been configured yet." },
      503,
    );
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch (_) {
    return jsonResponse(request, { error: "Invalid scan request." }, 400);
  }

  const fileName = String(body.fileName ?? "roster.jpg")
    .replace(/[^a-zA-Z0-9._-]/g, "_")
    .slice(0, 160);
  const mimeType = String(body.mimeType ?? "image/jpeg");
  const base64Data = String(body.base64Data ?? "");

  if (!base64Data) {
    return jsonResponse(request, { error: "The document is empty." }, 400);
  }

  const supportedTypes = new Set([
    "image/jpeg",
    "image/png",
    "application/pdf",
  ]);
  if (!supportedTypes.has(mimeType)) {
    return jsonResponse(
      request,
      { error: "This file type is not supported by the secure scanner." },
      415,
    );
  }

  let bytes: Uint8Array;
  try {
    bytes = decodeBase64(base64Data);
  } catch (_) {
    return jsonResponse(request, { error: "The document data is invalid." }, 400);
  }

  if (bytes.byteLength > 1_000_000) {
    return jsonResponse(
      request,
      { error: "This document is too large for the secure free scanner." },
      413,
    );
  }

  const form = new FormData();
  form.append("file", new Blob([bytes], { type: mimeType }), fileName);
  form.append("language", "eng");
  form.append("isOverlayRequired", "true");
  form.append("isTable", "true");
  form.append("OCREngine", "2");

  let providerResponse: Response;
  try {
    providerResponse = await fetch("https://api.ocr.space/parse/image", {
      method: "POST",
      headers: { apikey: apiKey },
      body: form,
    });
  } catch (_) {
    return jsonResponse(
      request,
      { error: "The secure scanner could not be reached." },
      502,
    );
  }

  let providerPayload: Record<string, unknown>;
  try {
    providerPayload = await providerResponse.json();
  } catch (_) {
    return jsonResponse(
      request,
      { error: "The secure scanner returned an invalid response." },
      502,
    );
  }

  if (!providerResponse.ok || providerPayload.IsErroredOnProcessing === true) {
    return jsonResponse(
      request,
      { error: safeErrorMessage(providerPayload) },
      422,
    );
  }

  const pages = normalisePages(providerPayload);
  if (pages.length === 0 || pages.every((page) => !page.fullText.trim())) {
    return jsonResponse(
      request,
      { error: "No readable text was found by the secure scanner." },
      422,
    );
  }

  return jsonResponse(request, { pages });
});
