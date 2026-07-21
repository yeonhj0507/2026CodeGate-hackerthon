"""제휴 기사 데이터셋 시드 (명세 §4.4 "신문사 제휴 기반 자체 기사 데이터셋").

사용자 학습 데이터가 아니라 추천 소스다. 여러 번 실행해도 url 기준으로 갱신된다.

    python scripts/seed.py
"""

import asyncio
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from sqlalchemy import select  # noqa: E402

from app.core.db import SessionLocal  # noqa: E402
from app.domain.models import PartnerArticle  # noqa: E402

SEED_FILE = ROOT / "seed" / "partner_articles.json"


async def main() -> None:
    entries = json.loads(SEED_FILE.read_text(encoding="utf-8"))

    async with SessionLocal() as db:
        existing = {
            row.url: row for row in (await db.execute(select(PartnerArticle))).scalars().all()
        }
        created = updated = 0
        for entry in entries:
            row = existing.get(entry["url"])
            if row is None:
                row = PartnerArticle(url=entry["url"])
                db.add(row)
                created += 1
            else:
                updated += 1
            row.title = entry["title"]
            row.summary = entry.get("summary", "")
            row.publisher = entry.get("publisher", "")
            row.category = entry.get("category", "")
            row.concept_tags = entry.get("conceptTags", [])
        await db.commit()

    print(f"seeded partner_articles: {created} created, {updated} updated")


if __name__ == "__main__":
    asyncio.run(main())
