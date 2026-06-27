# WhatsApp → Homzy listings ingestion

Turns messy WhatsApp developer/broker messages into clean structured listings,
using Gemini. This is **step 1** of the data pipeline.

```
WhatsApp messages  →  extract.py (Gemini)  →  structured listings  →  Supabase  →  app
```

## What works now
`extract.py` takes raw message text and returns clean listing JSON. It:
- understands Arabic (Egyptian dialect), English, and mixed posts,
- **skips non-listings** (greetings, "available?", chit-chat),
- converts prices like `22 مليون` / `4.2M` to numbers,
- **never invents** a price/number (missing → `null`),
- outputs developer-market fields: developer, project, area, price, down payment,
  installment years, delivery, beds/baths/size, finishing, phone.

### Run it
```bash
# built-in demo (sample messages)
GEMINI_API_KEY=...  python tools/whatsapp_ingest/extract.py --demo

# a real WhatsApp "Export chat" .txt file
GEMINI_API_KEY=...  python tools/whatsapp_ingest/extract.py chat.txt > listings.json
```
`GEMINI_MODEL` defaults to `gemini-flash-latest`. `INGEST_BATCH` (default 12)
controls how many messages go in one Gemini call.

## Roadmap
1. **[done]** AI extraction (`extract.py`).
2. **[next]** Move listings to a Supabase `listings` table; an `import` step that
   inserts extracted listings with de-duplication.
3. **[then]** Live capture: a WhatsApp bot (Baileys, on a spare number) that joins
   the groups, streams new messages into `extract.py`, and upserts to Supabase.
   ⚠️ Unofficial automation breaks WhatsApp's ToS and risks a ban — use a
   secondary number.
