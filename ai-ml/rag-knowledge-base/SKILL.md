---
name: rag-knowledge-base
description: Use when building, indexing, or querying vector databases for Retrieval-Augmented Generation (RAG).
---

# Semantic Search & RAG Instructions
1. Load document strings and clean HTML/markdown syntax.
2. Chunk text using recursive character splitting (target chunk size: 500, overlap: 50).
3. Compute embeddings using model API.
4. Insert chunks and embeddings into local vector store (e.g. Chroma, FAISS).
5. For queries, embed query string and retrieve top 3 nearest chunks.
6. Format prompt template: Context + Query -> Answer.

