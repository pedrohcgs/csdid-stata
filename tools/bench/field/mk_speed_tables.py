# Run from the bench/ folder of the replication package.
# Usage:  python3 mk_speed_tables.py
import csv, sys
B="."
rows=list(csv.DictReader(open(B+"/scalebench-results.csv")))
def get(scan,**kw):
    out=[]
    for r in rows:
        if r["scan"]!=scan: continue
        if all(r[k]==v for k,v in kw.items()): out.append(r)
    return out
def t(r):
    try: return float(r["median_seconds"])
    except: return None
def fmt(x,dp=2):
    if x is None: return "—"
    return f"{x:.{dp}f}"
# dedupe keep-last on (scan,n,T,G,pkg)
seen={}
for r in rows: seen[(r["scan"],r["n_units"],r["T"],r["cohorts"],r["pkg"])]=r
rows=list(seen.values())
for scan in ["E_default","A_unbal","B_rcs","C_periods","D_cohorts","F_n","F_T","F_G","F_scheme"]:
    print("=== "+scan)
    for r in rows:
        if r["scan"]==scan:
            print(f'{r["n_units"]},{r["T"]},{r["cohorts"]},{r["rows"]},{r["pkg"]},{fmt(t(r),3)},{r["trials"]},{r["note"][:60]}')
