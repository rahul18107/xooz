from dotenv import load_dotenv
import os

load_dotenv()

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")
# Service role key bypasses Storage RLS (audio uploads). Server-side only — never expose to the app.
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY") or SUPABASE_KEY
ASSEMBLYAI_API_KEY = os.getenv("ASSEMBLYAI_API_KEY")
ACTIVE_TRANSCRIPTION_PROVIDER = os.getenv("ACTIVE_TRANSCRIPTION_PROVIDER", "whisper")
CLOUDFLARE_ACCOUNT_ID = os.getenv("CLOUDFLARE_ACCOUNT_ID")
CLOUDFLARE_API_TOKEN = os.getenv("CLOUDFLARE_API_TOKEN")
ACTIVE_SUMMARIZATION_PROVIDER = os.getenv("ACTIVE_SUMMARIZATION_PROVIDER", "cloudflare")