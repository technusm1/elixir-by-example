#!/usr/bin/env bash
# Analytics report from D1.  tools/report.sh [days] [--local]
set -euo pipefail
days="${1:-7}"
where="--remote"; [[ "${2:-}" == "--local" ]] && where="--local"
since="strftime('%s','now') - ${days}*86400"

q() {
  echo; echo "== $1"
  npx wrangler d1 execute ebe-analytics "$where" --json --command "$2" 2>/dev/null |
    python3 -c 'import sys,json
rows=json.load(sys.stdin)[0]["results"]
for r in rows: print("  " + "  ".join(f"{v}" for v in r.values()))'
}

q "requests by client (last ${days}d)" \
  "SELECT client, kind, COUNT(*) n FROM hits WHERE ts > $since GROUP BY client, kind ORDER BY n DESC"
q "top pages, humans" \
  "SELECT path, COUNT(*) n FROM hits WHERE ts > $since AND kind='page' AND client='human' GROUP BY path ORDER BY n DESC LIMIT 20"
q "most-run examples" \
  "SELECT path, COUNT(*) n FROM hits WHERE ts > $since AND kind='run' GROUP BY path ORDER BY n DESC LIMIT 20"
q "agents and tools (raw .exs, llms.txt, pages)" \
  "SELECT agent, kind, COUNT(*) n FROM hits WHERE ts > $since AND client IN ('agent','tool') GROUP BY agent, kind ORDER BY n DESC LIMIT 25"
q "crawlers" \
  "SELECT agent, COUNT(*) n FROM hits WHERE ts > $since AND client='crawler' GROUP BY agent ORDER BY n DESC LIMIT 15"
q "referrers, humans" \
  "SELECT ref, COUNT(*) n FROM hits WHERE ts > $since AND client='human' AND ref != '' GROUP BY ref ORDER BY n DESC LIMIT 15"
q "countries, humans" \
  "SELECT country, COUNT(*) n FROM hits WHERE ts > $since AND client='human' GROUP BY country ORDER BY n DESC LIMIT 15"
q "404s" \
  "SELECT path, COUNT(*) n FROM hits WHERE ts > $since AND kind='notfound' GROUP BY path ORDER BY n DESC LIMIT 15"
