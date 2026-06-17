# Contributing to Homzy

Thanks for your interest in Homzy — a bilingual (Arabic / English) AI property
advisor that matches clients to real listings. Contributions of all kinds are
welcome: bug fixes, features, translations, listings data tooling, and docs.

## How to contribute

We use the standard **fork & pull request** flow:

1. **Fork** this repository to your own GitHub account.
2. **Clone** your fork and create a branch:
   ```bash
   git clone https://github.com/<your-username>/Homzy.git
   cd Homzy
   git checkout -b feature/my-change
   ```
3. **Make your change** and test it locally (see below).
4. **Commit** with a clear message and **push** to your fork.
5. Open a **Pull Request** against `main`. Describe what changed and why.

You don't need write access — anyone can fork and open a PR. Maintainers will
review and merge.

## Local setup

Requires Python 3.12+ on Windows (or any OS with Python 3.12).

```bash
# from the project root
python -m venv .venv
.venv\Scripts\activate        # Windows
pip install -r requirements.txt
python -m uvicorn backend.app:app --reload --port 8000
```

Then open http://127.0.0.1:8000. The app runs in a templated **Preview mode**
with no AI engine; install [Ollama](https://ollama.com) and run
`ollama pull qwen2.5:7b` for full local AI, or set a Google Gemini key. See the
[README](README.md) for details.

## Project layout

| Path | What it is |
|------|------------|
| `backend/` | FastAPI server, broker pipeline, LLM layer, listings search |
| `data/listings.json` | Property inventory (the source of truth for prices) |
| `frontend/index.html` | The chat UI |

## Guidelines

- **Never invent prices.** The AI must only present properties from
  `data/listings.json`. Keep prices grounded in code, never in the model.
- Keep the broker persona and prompts in `backend/persona.py`.
- Match the existing code style; keep functions small and commented where the
  intent isn't obvious.
- For larger changes, open an issue first to discuss the approach.

## Reporting bugs & ideas

Open a [GitHub Issue](../../issues) — describe the problem or idea, steps to
reproduce (for bugs), and what you expected. Bilingual (AR/EN) reports welcome.

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
