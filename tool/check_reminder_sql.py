"""Verify the actual native digest SQL against synthetic SQLite fixtures."""
import re
import sqlite3
from pathlib import Path

source = (Path(__file__).resolve().parent.parent / 'android/app/src/main/kotlin/com/detabev/recare/ReminderScheduler.kt').read_text()
base = re.search(r'"(SELECT name FROM foods[^"\n]+)"', source).group(1)
ack_filter = re.search(r'"( AND NOT EXISTS[^"\n]+)"', source).group(1)
exists_query = re.search(r'"(SELECT 1 FROM sqlite_master[^"\n]+)"', source).group(1)
order = re.search(r'acknowledgedFilter \+ "([^"\n]+)"', source).group(1)
db = sqlite3.connect(':memory:')
db.execute('CREATE TABLE foods (id TEXT PRIMARY KEY, name TEXT, remaining REAL, expiry TEXT)')
fixtures = [('expired',1,'2026-10-20'),('today',1,'2026-10-21'),('one',1,'2026-10-22'),('two',1,'2026-10-23'),('three',1,'2026-10-24'),('later',1,'2026-10-25'),('empty',0,'2026-10-21')]
db.executemany('INSERT INTO foods VALUES (?, ?, ?, ?)', [(name,name,remaining,expiry) for name,remaining,expiry in fixtures])
def digest():
    has_check_ins = db.execute(exists_query).fetchone() is not None
    query = base + (ack_filter if has_check_ins else '') + order
    args = ['2026-10-21','2026-10-22','2026-10-24'] + (['2026-10-21'] if has_check_ins else [])
    return [row[0] for row in db.execute(query, args)]
assert digest() == ['today','one','three'], 'Pre-migration fallback matches exact dates'
db.execute('CREATE TABLE expiry_check_ins (food_id TEXT, expiry TEXT, day TEXT, outcome TEXT, record_id TEXT, PRIMARY KEY(food_id, expiry, day))')
assert digest() == ['today','one','three'], 'Empty check-in table preserves matching'
db.execute("INSERT INTO expiry_check_ins VALUES ('one','2026-10-22','2026-10-21','none',NULL)")
assert digest() == ['today','three'], 'Matching acknowledgment suppresses only its food'
db.execute("INSERT INTO expiry_check_ins VALUES ('three','2026-10-24','2026-10-20','none',NULL)")
assert digest() == ['today','three'], 'Previous acknowledgment day does not suppress'
db.execute("INSERT INTO expiry_check_ins VALUES ('today','2026-10-20','2026-10-21','none',NULL)")
assert digest() == ['today','three'], 'Previous expiry does not suppress'
db.execute("UPDATE foods SET expiry = '2026-10-24' WHERE id = 'one'")
assert digest() == ['today','one','three'], 'Changed expiry permits a new acknowledgment'
print('ReminderScheduler SQL: 6 fixture checks passed')
