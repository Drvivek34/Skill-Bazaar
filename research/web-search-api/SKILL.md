---
name: web-search-api
description: Use when an agent needs live web results — pick a search provider (Tavily, Exa, Firecrawl, Brave, Serper, Google CSE, SearXNG), authenticate, call it correctly, and stay inside free-tier quotas.
---

# Web Search API Integration

Pick the right provider, wire auth the way each API actually expects, and don't burn quota.

## Provider selection

| Situation | Use |
|---|---|
| Default LLM-friendly search | Tavily |
| Conceptual / semantic queries | Exa |
| Need page content (not snippets) | Firecrawl |
| Freshness-critical lookups | Brave Search API |
| Exact Google SERP / answer boxes | Serper.dev or Google CSE |
| Unlimited dev/testing | Self-hosted SearXNG |

Free tiers (verified 2026-08-24): Tavily 1,000 credits/mo · Exa $20 signup + $10/mo ·
Firecrawl 1,000 credits/mo · Brave $5/mo credits (card required since Aug 2025) ·
Serper 2,500 one-time · Google CSE 100 queries/day · SearXNG unlimited self-hosted.

## Auth shapes (the part everyone gets wrong)

| Provider | Auth location | Env var convention |
|---|---|---|
| Tavily | `api_key` **in JSON body** | `TAVILY_API_KEY` |
| Exa | `x-api-key` header | `EXA_API_KEY` |
| Firecrawl | `Authorization: Bearer` header | `FIRECRAWL_API_KEY` |
| Brave | `X-Subscription-Token` header | `BRAVE_SEARCH_API_KEY` (never `BRAVE_API_KEY`) |
| Serper | `X-API-KEY` header | `SERPER_API_KEY` |
| Google CSE | `key` + `cx` query params | `GCS_API_KEY` + `GCS_CX` |
| SearXNG | none (JSON format must be enabled server-side) | n/a |

## Reference implementations

```python
import os, requests

def tavily_search(q, n=5):
    r = requests.post("https://api.tavily.com/search", json={
        "api_key": os.environ["TAVILY_API_KEY"], "query": q,
        "search_depth": "basic", "max_results": n}, timeout=30)
    r.raise_for_status()
    return [{"title": x["title"], "url": x["url"], "snippet": x["content"]}
            for x in r.json()["results"]]

def exa_search(q, n=5):
    r = requests.post("https://api.exa.ai/search",
        headers={"x-api-key": os.environ["EXA_API_KEY"]},
        json={"query": q, "numResults": n}, timeout=30)
    r.raise_for_status()
    return [{"title": x["title"], "url": x["url"]} for x in r.json()["results"]]

def brave_search(q, n=5):
    r = requests.get("https://api.search.brave.com/res/v1/web/search",
        headers={"X-Subscription-Token": os.environ["BRAVE_SEARCH_API_KEY"],
                 "Accept": "application/json"},
        params={"q": q, "count": n}, timeout=30)
    r.raise_for_status()
    return [{"title": x["title"], "url": x["url"], "snippet": x["description"],
             "age": x.get("age")} for x in r.json()["web"]["results"]]

def serper_search(q, n=5):
    r = requests.post("https://google.serper.dev/search",
        headers={"X-API-KEY": os.environ["SERPER_API_KEY"]},
        json={"q": q, "num": n}, timeout=20)
    r.raise_for_status()
    return [{"title": x["title"], "url": x["link"], "snippet": x["snippet"]}
            for x in r.json().get("organic", [])[:n]]
```

## Quota discipline

1. Only HTTP 200 counts against real quota — log 429/5xx separately, never increment.
2. Cache by normalized URL; identical repeat queries should never re-hit the API.
3. Route cheap dev traffic to SearXNG; save metered keys for production paths.
4. Track monthly usage per key in a state file; alert at 80% before exhaustion.
5. Monthly refills reset on the 1st and do not roll over.

## Pitfalls

- Tavily: key in body, not header. `advanced` depth = 2× credits.
- Exa: no relevance scores returned; `/contents` costs extra beyond `/search`.
- Firecrawl: crawl jobs are async (job ID first, poll later) — not empty results.
- Brave: card required at signup now; summarizer/grounding endpoints bill faster than plain search.
- Google CSE: needs BOTH `key` and `cx`; quota resets midnight PT not IST.
