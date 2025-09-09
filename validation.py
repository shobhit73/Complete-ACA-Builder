# MOVED from app.py preserve original code, only moved.
import numpy as np
from datetime import date, datetime, timedelta

TRUTHY = {"y","yes","true","t","1",1,True}
FALSY  = {"n","no","false","f","0",0,False,None,np.nan}
ACTIVE_STATUS = {"FT","FULL-TIME","FULL TIME","PT","PART-TIME","PART TIME","ACTIVE"}

CANON_ALIASES = {
    "mimimumvaluecoverage": "minimumvaluecoverage",
    "minimimvaluecoverage": "minimumvaluecoverage",
    "zip": "zipcode", "zip code": "zipcode",
    "ssn (digits only)": "ssn",
}

def _coerce_str(x) -> str:
    if pd_isna(x): return ""
    return str(x).strip()

def pd_isna(x):
    # wrapper so modules don't need to import pandas repeatedly for pd.isna in tiny helpers
    try:
        import pandas as pd
        return pd.isna(x)
    except Exception:
        return x is None

def to_bool(val) -> bool:
    if isinstance(val, str):
        v = val.strip().lower()
        if v in TRUTHY: return True
        if v in FALSY:  return False
    return bool(val) and val not in FALSY

def _last_day_of_month(y: int, m: int) -> date:
    return date(y,12,31) if m==12 else (date(y, m+1, 1) - timedelta(days=1))

def parse_date_safe(d, default_end: bool=False):
    import pandas as pd
    if pd.isna(d): return None
    if isinstance(d, (datetime, np.datetime64)):
        dt = pd.to_datetime(d, errors="coerce");  return None if pd.isna(dt) else dt.date()
    s = str(d).strip()
    if not s: return None
    try:
        if len(s)==4 and s.isdigit():
            y = int(s); return date(y,12,31) if default_end else date(y,1,1)
        if len(s)==7 and s[4]=="-":
            y,m = map(int, s.split("-"));  return _last_day_of_month(y,m) if default_end else date(y,m,1)
    except: pass
    dt = pd.to_datetime(s, errors="coerce", dayfirst=False)
    if pd.isna(dt):
        try:
            y,m = map(int, s.split("-")[:2])
            return _last_day_of_month(y,m) if default_end else date(y,m,1)
        except: return None
    return dt.date()

def month_bounds(year:int, month:int):
    return date(year, month, 1), _last_day_of_month(year, month)
