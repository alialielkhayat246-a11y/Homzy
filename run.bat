@echo off
REM ---- Homzy launcher: sets up everything and opens the chat in your browser ----
cd /d "%~dp0"

if not exist ".venv" (
  echo Creating Python environment ^(first run only^)...
  py -3.12 -m venv .venv
)

call ".venv\Scripts\activate.bat"
python -m pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt

echo.
echo Starting Homzy at http://127.0.0.1:8000
echo Close this window to stop the server.
echo.
start "" http://127.0.0.1:8000
python -m uvicorn backend.app:app --host 127.0.0.1 --port 8000
