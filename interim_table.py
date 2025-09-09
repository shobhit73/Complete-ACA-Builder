# MOVED from app.py — preserve original code, only moved.
import io
import pandas as pd
import numpy as np
from typing import Tuple
from validation import CANON_ALIASES, month_bounds, parse_date_safe, to_bool, _coerce_str, pd_isna  # helpers

# EXPECTED_SHEETS reproduced here (moved)
EXPECTED_SHEETS = {
    "emp demographic": ["employeeid","firstname","lastname","ssn","addressline1","addressline2","city","state","zipcode"],
    "emp status": ["employeeid","employmentstatus","role","statusstartdate","statusenddate"],
    "emp eligibility": ["employeeid","iseligibleforcoverage","minimumvaluecoverage","eligibilitystartdate","eligibilityenddate"],
    "emp enrollment": ["employeeid","isenrolled","enrollmentstartdate","enrollmentenddate"],
    "dep enrollment": ["employeeid","dependentrelationship","eligible","enrolled","eligiblestartdate","eligibleenddate"],
    "pay deductions": ["employeeid","amount","startdate","enddate"]
}

def normalize_columns(df: pd.DataFrame) -> pd.DataFrame:
    df = df.copy()
    df.columns = (df.columns.str.strip().str.replace(r"\s+", " ", regex=True).str.lower())
    return df

def load_excel(file_bytes: bytes) -> dict:
    xls = pd.ExcelFile(io.BytesIO(file_bytes))
    out = {}
    for raw in xls.sheet_names:
        df = pd.read_excel(xls, raw)
        df = normalize_columns(df)
        df = df.rename(columns={k:v for k,v in CANON_ALIASES.items() if k in df.columns})
        out[raw.strip().lower()] = df
    return out

def _pick_sheet(data: dict, key: str) -> pd.DataFrame:
    if key in data: return data[key]
    for k in data:
        if key in k: return data[k]
    return pd.DataFrame()

def _ensure_employeeid_str(df):
    if df.empty or "employeeid" not in df.columns: return df
    df = df.copy(); df["employeeid"] = df["employeeid"].map(_coerce_str); return df

def _parse_date_cols(df, cols, default_end_cols=()):
    if df.empty: return df
    df = df.copy(); endset = set(default_end_cols)
    for c in cols:
        if c in df.columns:
            df[c] = df[c].apply(lambda x: parse_date_safe(x, default_end=c in endset))
            df[c] = pd.to_datetime(df[c], errors="coerce")
    return df

def _boolify(df, cols):
    if df.empty: return df
    df = df.copy()
    for c in cols:
        if c in df.columns: df[c] = df[c].apply(to_bool)
    return df

def prepare_inputs(data: dict):
    cleaned = {}
    for sheet, cols in EXPECTED_SHEETS.items():
        df = _pick_sheet(data, sheet)
        if df.empty:
            cleaned[sheet] = pd.DataFrame(columns=cols); continue
        for misspell, canon in CANON_ALIASES.items():
            if misspell in df.columns and canon not in df.columns:
                df = df.rename(columns={misspell: canon})
        df = _ensure_employeeid_str(df)
        if sheet == "emp status":
            if "employmentstatus" in df.columns:
                df["employmentstatus"] = df["employmentstatus"].astype(str).str.strip().str.upper()
            if "role" in df.columns:
                df["role"] = df["role"].astype(str).str.strip().str.upper()
            df = _parse_date_cols(df, ["statusstartdate","statusenddate"], default_end_cols=["statusenddate"])
        elif sheet == "emp eligibility":
            df = _boolify(df, ["iseligibleforcoverage","minimumvaluecoverage"])
            df = _parse_date_cols(df, ["eligibilitystartdate","eligibilityenddate"], default_end_cols=["eligibilityenddate"])
        elif sheet == "emp enrollment":
            df = _boolify(df, ["isenrolled"])
            df = _parse_date_cols(df, ["enrollmentstartdate","enrollmentenddate"], default_end_cols=["enrollmentenddate"])
        elif sheet == "dep enrollment":
            if "dependentrelationship" in df.columns:
                df["dependentrelationship"] = df["dependentrelationship"].astype(str).str.strip().str.title()
            df = _boolify(df, ["eligible","enrolled"])
            df = _parse_date_cols(df, ["eligiblestartdate","eligibleenddate"], default_end_cols=["eligibleenddate"])
        elif sheet == "pay deductions":
            df = _parse_date_cols(df, ["startdate","enddate"], default_end_cols=["enddate"])
        cleaned[sheet] = df
    return (cleaned["emp demographic"], cleaned["emp status"], cleaned["emp eligibility"],
            cleaned["emp enrollment"], cleaned["dep enrollment"], cleaned["pay deductions"])

def choose_report_year(emp_elig: pd.DataFrame, fallback_to_current=True) -> int:
    from datetime import datetime
    if emp_elig.empty or not {"eligibilitystartdate","eligibilityenddate"} <= set(emp_elig.columns):
        return datetime.now().year if fallback_to_current else 2024
    counts={}
    for _,r in emp_elig.iterrows():
        s = pd.to_datetime(r.get("eligibilitystartdate"), errors="coerce")
        e = pd.to_datetime(r.get("eligibilityenddate"), errors="coerce")
        if pd.isna(s) and pd.isna(e): continue
        s = s or pd.Timestamp.min; e = e or pd.Timestamp.max
        for y in range(s.year, e.year+1): counts[y]=counts.get(y,0)+1
    return max(sorted(counts), key=lambda y:(counts[y], y)) if counts else (datetime.now().year if fallback_to_current else 2024)

def _collect_employee_ids(*dfs):
    ids=set()
    for df in dfs:
        if df is None or df.empty: continue
        if "employeeid" in df.columns:
            ids.update(map(_coerce_str, df["employeeid"].dropna().tolist()))
    return sorted(ids)

def _grid_for_year(employee_ids, year:int) -> pd.DataFrame:
    recs=[]
    for emp in employee_ids:
        for m in range(1,13):
            ms,me = month_bounds(year,m)
            recs.append({"employeeid":emp,"year":year,"monthnum":m,"month":ms.strftime("%b"),
                         "monthstart":ms,"monthend":me})
    g = pd.DataFrame.from_records(recs)
    g["monthstart"]=pd.to_datetime(g["monthstart"]); g["monthend"]=pd.to_datetime(g["monthend"])
    return g

def build_interim(emp_demo, emp_status, emp_elig, emp_enroll, dep_enroll, year=None) -> pd.DataFrame:
    if year is None: year = choose_report_year(emp_elig)
    employee_ids = _collect_employee_ids(emp_demo, emp_status, emp_elig, emp_enroll, dep_enroll)
    grid = _grid_for_year(employee_ids, year)
    demo = emp_demo[["employeeid","firstname","lastname"]].drop_duplicates("employeeid") if not emp_demo.empty else pd.DataFrame(columns=["employeeid","firstname","lastname"])
    out = grid.merge(demo, on="employeeid", how="left")
    stt, elg, enr, dep = emp_status.copy(), emp_elig.copy(), emp_enroll.copy(), dep_enroll.copy()
    for df in (stt,elg,enr,dep):
        if not df.empty:
            for c in df.columns:
                if c.endswith("date") and not np.issubdtype(df[c].dtype, np.datetime64):
                    df[c] = pd.to_datetime(df[c], errors="coerce")
    flags=[]
    for _,row in out.iterrows():
        emp = row["employeeid"]; ms=row["monthstart"].date(); me=row["monthend"].date()
        st_emp = stt[stt["employeeid"]==emp] if not stt.empty else stt
        el_emp = elg[elg["employeeid"]==emp] if not elg.empty else elg
        en_emp = enr[enr["employeeid"]==emp] if not enr.empty else enr
        de_emp = dep[dep["employeeid"]==emp] if not dep.empty else dep

        employed=False
        if not st_emp.empty and {"employmentstatus","statusstartdate","statusenddate"} <= set(st_emp.columns):
            employed = _any_overlap(st_emp, "statusstartdate","statusenddate", ms,me, mask=st_emp["employmentstatus"].isin(ACTIVE_STATUS))
        ft=False
        if not st_emp.empty and {"role","statusstartdate","statusenddate"} <= set(st_emp.columns):
            ft = _any_overlap(st_emp, "statusstartdate","statusenddate", ms,me, mask=st_emp["role"].eq("FT"))
        eligible_any=False; eligible_allmonth=False; eligible_mv_any=False
        if not el_emp.empty and {"eligibilitystartdate","eligibilityenddate"} <= set(el_emp.columns):
            eligible_any = _any_overlap(el_emp, "eligibilitystartdate","eligibilityenddate", ms,me)
            eligible_allmonth = _all_month(el_emp, "eligibilitystartdate","eligibilityenddate", ms,me)
            if "minimumvaluecoverage" in el_emp.columns:
                eligible_mv_any = _any_overlap(el_emp, "eligibilitystartdate","eligibilityenddate", ms,me, mask=el_emp["minimumvaluecoverage"].fillna(False))
        enrolled_allmonth=False
        if not en_emp.empty and {"enrollmentstartdate","enrollmentenddate"} <= set(en_emp.columns):
            en_mask = en_emp["isenrolled"].fillna(False) if "isenrolled" in en_emp.columns else pd.Series(True,index=en_emp.index)
            enrolled_allmonth = _all_month(en_emp, "enrollmentstartdate","enrollmentenddate", ms,me, mask=en_mask)
        offer_spouse=False; offer_dependents=False
        if not de_emp.empty and {"dependentrelationship","eligiblestartdate","eligibleenddate"} <= set(de_emp.columns):
            offer_spouse = _any_overlap(de_emp, "eligiblestartdate","eligibleenddate", ms,me, mask=de_emp["dependentrelationship"].eq("Spouse"))
            offer_dependents = _any_overlap(de_emp, "eligiblestartdate","eligibleenddate", ms,me, mask=de_emp["dependentrelationship"].eq("Child"))
        waitingperiod_month = bool(employed and ft and not eligible_any)

        # Line 14
        if eligible_allmonth and eligible_mv_any:
            l14 = "1E" if (offer_spouse and offer_dependents) else ("1C" if (offer_dependents and not offer_spouse) else ("1D" if (offer_spouse and not offer_dependents) else "1B"))
        elif eligible_allmonth and not eligible_mv_any:
            l14 = "1F"
        else:
            l14 = "1H"

        # Line 16
        if enrolled_allmonth: l16 = "2C"
        elif waitingperiod_month: l16 = "2D"
        elif not employed: l16 = "2A"
        elif employed and not ft: l16 = "2B"
        else: l16 = ""

        flags.append({
            "employed": employed, "ft": ft,
            "eligibleforcoverage": eligible_any, "eligible_allmonth": eligible_allmonth, "eligible_mv": eligible_mv_any,
            "offer_ee_allmonth": eligible_allmonth, "enrolled_allmonth": enrolled_allmonth,
            "offer_spouse": offer_spouse, "offer_dependents": offer_dependents, "waitingperiod_month": waitingperiod_month,
            "line14_final": l14, "line16_final": l16,
        })
    interim = pd.concat([out.reset_index(drop=True), pd.DataFrame(flags)], axis=1)
    base_cols = ["employeeid","firstname","lastname","year","monthnum","month","monthstart","monthend"]
    flag_cols = ["employed","ft","eligibleforcoverage","eligible_allmonth","eligible_mv","offer_ee_allmonth",
                 "enrolled_allmonth","offer_spouse","offer_dependents","waitingperiod_month","line14_final","line16_final"]
    keep = [c for c in base_cols if c in interim.columns] + [c for c in flag_cols if c in interim.columns]
    interim = interim[keep].sort_values(["employeeid","year","monthnum"]).reset_index(drop=True)
    return interim

def build_final(interim: pd.DataFrame) -> pd.DataFrame:
    df = interim.copy()
    out = df.loc[:, ["employeeid","month","line14_final","line16_final"]].rename(columns={
        "employeeid":"EmployeeID","month":"Month","line14_final":"Line14_Final","line16_final":"Line16_Final"
    })
    if "monthnum" in df.columns:
        out = out.join(df["monthnum"]).sort_values(["EmployeeID","monthnum"]).drop(columns=["monthnum"])
    else:
        from config import MONTHS
        order = {m:i for i,m in enumerate(MONTHS, start=1)}
        out["_ord"]=out["Month"].map(order); out=out.sort_values(["EmployeeID","_ord"]).drop(columns=["_ord"])
    return out.reset_index(drop=True)

# local helpers used by build_interim that refer to validation utilities
def _any_overlap(df, start_col, end_col, m_start, m_end, mask=None) -> bool:
    if df.empty: return False
    _m = mask if mask is not None else pd.Series(True, index=df.index)
    s = df.loc[_m, start_col].fillna(pd.Timestamp.min).dt.date
    e = df.loc[_m, end_col].fillna(pd.Timestamp.max).dt.date
    return bool(((e >= m_start) & (s <= m_end)).any())

def _all_month(df, start_col, end_col, m_start, m_end, mask=None) -> bool:
    if df.empty: return False
    _m = mask if mask is not None else pd.Series(True, index=df.index)
    s = df.loc[_m, start_col].fillna(pd.Timestamp.min).dt.date
    e = df.loc[_m, end_col].fillna(pd.Timestamp.max).dt.date
    return bool(((s <= m_start) & (e >= m_end)).any())
