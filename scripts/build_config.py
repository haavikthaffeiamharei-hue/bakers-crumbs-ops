#!/usr/bin/env python3
"""Build LibreChat's librechat.yaml for Baker's Crumbs.

Reads the bakery documents (downloaded from S3 by start-bakers-crumbs.sh) and
writes a complete librechat.yaml to stdout: branding, theme, hidden features and
one enforced model spec whose instructions contain the bakery documents.

YAML is a superset of JSON, so the file is written as JSON with the standard
library only (no PyYAML needed on the server).

Usage: build_config.py <content_dir> <gemini_model> <release_label>
"""
import json
import pathlib
import sys

content_dir = pathlib.Path(sys.argv[1])
model = sys.argv[2]
release = sys.argv[3] if len(sys.argv) > 3 else "dev"

docs = sorted(content_dir.glob("*.md"))
if not docs:
    sys.exit(f"No .md documents found in {content_dir}")

doc_text = "\n\n".join(
    f'<document name="{d.name}">\n{d.read_text(encoding="utf-8").strip()}\n</document>'
    for d in docs
)

instructions = f"""You are the Baker's Crumbs Helper, the friendly question-and-answer assistant of Baker's Crumbs, a small neighbourhood bakery. Baker's Crumbs is an invented business created for a class project.

Rules you must follow:
1. Answer ONLY from the bakery documents below. If the answer is not in them, say you don't know and suggest contacting the bakery at hello@bakerscrumbs.example. Never guess prices, hours, ingredients or policies.
2. Keep answers short (one to four sentences, or a short list), warm and in plain English. Quote prices in pesos exactly as written.
3. You cannot take orders or payments, track orders or check today's stock. Explain how to pre-order instead.
4. Allergies and ingredients: you may repeat what the documents say, but always tell the customer to confirm with staff before eating, and never say a product is safe for someone with an allergy.
5. Politely decline questions that are not about the bakery.
6. Never ask for personal information such as full names, addresses or phone numbers.

Assistant release: {release}

BAKERY DOCUMENTS:
{doc_text}
"""

light = {
    "rgb-surface-primary": "255 250 242",
    "rgb-surface-secondary": "250 240 225",
    "rgb-surface-tertiary": "243 228 205",
    "rgb-surface-hover": "240 222 196",
    "rgb-text-primary": "61 38 20",
    "rgb-text-secondary": "110 78 52",
    "rgb-border-light": "234 216 190",
    "rgb-border-medium": "214 190 158",
    "rgb-accent-primary": "139 90 43",
    "rgb-accent-primary-hover": "112 70 32",
    "rgb-surface-submit": "139 90 43",
    "rgb-surface-submit-hover": "112 70 32",
    "rgb-button-primary": "139 90 43",
    "rgb-button-primary-hover": "112 70 32",
    "rgb-ring-primary": "139 90 43",
    "rgb-link": "139 90 43",
    # Page areas used by this LibreChat build (found in the client CSS)
    "rgb-presentation": "255 250 242",
    "rgb-surface-chat": "255 250 242",
    "rgb-surface-primary-alt": "250 240 225",
    "rgb-surface-sidebar": "246 234 214",
    "rgb-surface-nav-hover": "238 220 192",
    "rgb-surface-nav-selected": "232 210 178",
    "rgb-header-primary": "250 240 225",
    "rgb-header-hover": "240 222 196",
    "rgb-surface-composer": "255 255 255",
    "rgb-surface-composer-hover": "250 240 225",
    "rgb-surface-user-message": "243 224 196",
    "rgb-surface-menu": "255 250 242",
    "rgb-surface-card": "243 228 205",
    "rgb-surface-active": "238 220 192",
    "rgb-surface-dialog": "255 250 242",
}
dark = {
    "rgb-surface-primary": "33 24 18",
    "rgb-surface-secondary": "43 31 23",
    "rgb-surface-tertiary": "58 42 31",
    "rgb-surface-hover": "70 51 37",
    "rgb-text-primary": "250 238 220",
    "rgb-text-secondary": "214 190 158",
    "rgb-border-light": "70 52 38",
    "rgb-border-medium": "92 68 50",
    "rgb-accent-primary": "217 160 91",
    "rgb-accent-primary-hover": "232 182 120",
    "rgb-surface-submit": "176 112 52",
    "rgb-surface-submit-hover": "196 128 62",
    "rgb-button-primary": "176 112 52",
    "rgb-button-primary-hover": "196 128 62",
    "rgb-ring-primary": "217 160 91",
    "rgb-link": "232 182 120",
    # Page areas used by this LibreChat build (found in the client CSS)
    "rgb-presentation": "36 26 19",
    "rgb-surface-chat": "36 26 19",
    "rgb-surface-primary-alt": "43 31 23",
    "rgb-surface-sidebar": "29 21 15",
    "rgb-surface-nav-hover": "58 42 31",
    "rgb-surface-nav-selected": "70 51 37",
    "rgb-header-primary": "43 31 23",
    "rgb-header-hover": "58 42 31",
    "rgb-surface-composer": "50 36 27",
    "rgb-surface-composer-hover": "58 42 31",
    "rgb-surface-user-message": "92 62 38",
    "rgb-surface-menu": "43 31 23",
    "rgb-surface-card": "70 51 37",
    "rgb-surface-active": "70 51 37",
    "rgb-surface-dialog": "43 31 23",
}

config = {
    "version": "1.3.18",
    "cache": True,
    "interface": {
        "customWelcome": "Welcome to Baker's Crumbs! Ask me about our breads, cookies, cakes, opening hours, pre-orders and delivery.",
        "modelSelect": False,
        "parameters": False,
        "presets": False,
        "prompts": False,
        "bookmarks": False,
        "memories": False,
        "multiConvo": False,
        "agents": False,
        "sharedLinks": False,
        "temporaryChat": False,
        "theme": {
            "version": 1,
            "name": "bakers-crumbs",
            "modes": {"light": {"colors": light}, "dark": {"colors": dark}},
        },
    },
    # Gemini through its OpenAI-compatible API as a LibreChat custom endpoint,
    # so the chat shows the Baker's Crumbs icon and name instead of the Gemini icon.
    "endpoints": {
        "custom": [
            {
                "name": "BakersCrumbs",
                "apiKey": "${GOOGLE_KEY}",
                "baseURL": "https://generativelanguage.googleapis.com/v1beta/openai/",
                "models": {"default": [model], "fetch": False},
                "titleConvo": True,
                "titleModel": model,
                "modelDisplayLabel": "Baker's Crumbs Helper",
                "iconURL": "/assets/logo.svg",
            }
        ]
    },
    "modelSpecs": {
        "enforce": True,
        "prioritize": True,
        "list": [
            {
                "name": "bakers-crumbs-helper",
                "label": "Baker's Crumbs Helper",
                "default": True,
                "description": "Answers questions about the Baker's Crumbs menu, prices, hours, pre-orders, delivery and ingredients.",
                "iconURL": "/assets/logo.svg",
                "showIconInMenu": True,
                "showIconInHeader": True,
                "conversation_starters": [
                    "What time do you open on Saturday?",
                    "How much is a Cookie Box of 12?",
                    "Do you deliver, and how much is the fee?",
                    "Which of your cakes contain nuts?",
                ],
                "preset": {
                    "endpoint": "BakersCrumbs",
                    "model": model,
                    "modelLabel": "Baker's Crumbs Helper",
                    "iconURL": "/assets/logo.svg",
                    "promptPrefix": instructions,
                    "temperature": 0.2,
                    "max_tokens": 600,
                },
            }
        ],
    },
}

print("# Generated by bakers-crumbs-ops/scripts/build_config.py - do not edit by hand.")
print(json.dumps(config, indent=2, ensure_ascii=False))
