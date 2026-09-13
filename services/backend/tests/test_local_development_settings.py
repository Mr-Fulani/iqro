import json
import subprocess
import sys
from pathlib import Path


def test_local_setup_does_not_schedule_full_provider_imports() -> None:
    # Import local settings in a fresh interpreter: its development renderer
    # configuration must not change the running test suite's settings.
    script = """
import json
from quran_backend.settings import base, local
print(json.dumps([
    [job['task'] for job in base.CELERY_BEAT_SCHEDULE.values()],
    [job['task'] for job in local.CELERY_BEAT_SCHEDULE.values()],
]))
"""
    baseline, local_jobs = json.loads(
        subprocess.check_output(  # noqa: S603
            [sys.executable, "-c", script],
            cwd=Path(__file__).resolve().parents[1] / "src",
            text=True,
        )
    )
    provider_tasks = {
        "audio.sync_quran_foundation",
        "audio.sync_quran_foundation_ayah_catalog",
        "quran.sync_quran_foundation_mushafs",
        "translations.sync_quran_foundation_translations",
        "tafsirs.sync_quran_foundation_tafsirs",
    }
    assert provider_tasks <= set(baseline)
    local_tasks = set(local_jobs)
    assert local_tasks.isdisjoint(provider_tasks)
    assert {"reminders.dispatch_web_push_due", "accounts.prune_auth_sessions"} <= local_tasks
