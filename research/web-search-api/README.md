# Web Search API Integration

A portable agent skill covering provider selection, correct per-provider authentication,
ready-to-paste reference implementations, and free-tier quota discipline for live web search
in agents.

> Part of **[Skill Bazaar](../../README.md)** · [Mega AI Bazaar](https://drvivek34.github.io/Mega-AI-Bazaar/)

## Details
- **Name**: web-search-api
- **Source URL**: https://github.com/Drvivek34/Skill-Bazaar/tree/main/research/web-search-api
- **Author**: Skill Bazaar Community
- **License**: MIT
- **Date Added**: 2026-08-24

## What it covers

- **Provider selection table** — Tavily vs Exa vs Firecrawl vs Brave vs Serper vs Google CSE
  vs SearXNG, mapped to query types (LLM-native, semantic, content-scraping, freshness, exact-Google).
- **Auth shapes** — the #1 failure mode: Tavily wants the key in the JSON body, Exa uses
  `x-api-key`, Firecrawl `Bearer`, Brave `X-Subscription-Token` with env var
  `BRAVE_SEARCH_API_KEY`, Google CSE needs key AND cx.
- **Free-tier cheat sheet** (verified 2026-08-24) — Tavily 1,000 credits/mo (no card),
  Exa $20 signup + $10/mo, Firecrawl 1,000 credits/mo, Brave $5/mo credits (card now required),
  Serper 2,500 one-time, Google CSE 100/day, SearXNG unlimited self-hosted.
- **Python reference implementations** for four providers.
- **Quota discipline rules** — cache-first, log-only-on-200, dev/prod routing, 80% alerts.

## Instructions
See [SKILL.md](SKILL.md) inside this folder.
