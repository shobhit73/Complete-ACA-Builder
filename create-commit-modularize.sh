#!/usr/bin/env bash
set -euo pipefail

BRANCH="modularize/app_py"
COMMIT_MSG="chore: modularize app.py into modules (fill_part1, fill_part2, interim_table, pdf_helpers, io_utils, validation, config)"

# Backup existing app.py
cp -n app.py app.py.bak || true
echo "Backup of app.py saved as app.py.bak (if not already present)."

# Create branch
git checkout -B "$BRANCH"

# Write files
cat > validation.py <<'PY'
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
PY

cat > config.py <<'PY'
# MOVED from app.py — preserve original code, only moved.
# Minimal config/constants used by multiple modules.

MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
PY

cat > interim_table.py <<'PY'
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
PY

cat > fill_part1.py <<'PY'
# MOVED from app.py — preserve original code, only moved.
import pandas as pd
from validation import _coerce_str

def normalize_ssn_digits(ssn: str) -> str:
    d = "".join(ch for ch in str(ssn) if str(ch).isdigit())
    return f"{d[0:3]}-{d[3:5]}-{d[5:9]}" if len(d)>=9 else d

def build_part1_map(emp_row: pd.Series):
    """
    Returns tuple (part1_map: dict, first_last: str, editable_first_last_clean: str, street: str)
    This builds the Part I mapping used by the PDF filling logic (identical code moved).
    """
    first  = _coerce_str(emp_row.get("firstname"))
    mi     = ""  # optional middle initial
    last   = _coerce_str(emp_row.get("lastname"))
    ssn    = normalize_ssn_digits(_coerce_str(emp_row.get("ssn")))
    addr1  = _coerce_str(emp_row.get("addressline1"))
    addr2  = _coerce_str(emp_row.get("addressline2"))
    city   = _coerce_str(emp_row.get("city"))
    state  = _coerce_str(emp_row.get("state"))
    zipcode= _coerce_str(emp_row.get("zipcode"))
    street = addr1 if not addr2 else f"{addr1} {addr2}"

    part1_map = {
        "f1_1[0]": first,
        "f1_2[0]": mi,
        "f1_3[0]": last,
        "f1_4[0]": ssn,
        "f1_5[0]": street,
        "f1_6[0]": city,
        "f1_7[0]": state,
        "f1_8[0]": zipcode,
    }

    first_last = f"{first}_{last}".strip().replace(" ","_") or (_coerce_str(emp_row.get("employeeid")) or "employee")
    return part1_map, first_last
PY

cat > fill_part2.py <<'PY'
# MOVED from app.py — preserve original code, only moved.
from config import MONTHS
from typing import Tuple
import pandas as pd

# Part II Line 14 (All 12 + Jan..Dec)
F_L14 = ["f1_17[0]","f1_18[0]","f1_19[0]","f1_20[0]","f1_21[0]","f1_22[0]","f1_23[0]",
         "f1_24[0]","f1_25[0]","f1_26[0]","f1_27[0]","f1_28[0]","f1_29[0]"]
# Part II Line 16 (All 12 + Jan..Dec)
F_L16 = ["f1_43[0]","f1_44[0]","f1_45[0]","f1_46[0]","f1_47[0]","f1_48[0]","f1_49[0]",
         "f1_50[0]","f1_51[0]","f1_52[0]","f1_53[0]","f1_54[0]","f1_55[0]"]

def build_part2_map(final_df_emp: pd.DataFrame):
    """
    Given the final employee table (with Month, Line14_Final, Line16_Final), build the
    part2_map suitable for zip into the PDF mapping. Returns dict.
    """
    l14_by_m = {row["Month"]: str(row["Line14_Final"]) for _,row in final_df_emp.iterrows()}
    l16_by_m = {row["Month"]: str(row["Line16_Final"]) for _,row in final_df_emp.iterrows()}

    def all12_value(d):
        vals = [d.get(m, "") for m in MONTHS]
        uniq = {v for v in vals if v}
        return list(uniq)[0] if len(uniq)==1 else ""

    l14_all = all12_value(l14_by_m)
    l16_all = all12_value(l16_by_m)

    l14_values = [l14_all] + [l14_by_m.get(m,"") for m in MONTHS]
    l16_values = [l16_all] + [l16_by_m.get(m,"") for m in MONTHS]

    part2_map = {}
    for name,val in zip(F_L14, l14_values): part2_map[name]=val
    for name,val in zip(F_L16, l16_values): part2_map[name]=val

    return part2_map
PY

cat > pdf_helpers.py <<'PY'
# MOVED from app.py — preserve original code, only moved.
import io
from PyPDF2 import PdfReader, PdfWriter
from PyPDF2.generic import NameObject, BooleanObject, DictionaryObject
from reportlab.pdfgen import canvas
from fill_part1 import build_part1_map
from fill_part2 import build_part2_map

def set_need_appearances(writer: PdfWriter):
    root = writer._root_object
    if "/AcroForm" not in root:
        root.update({NameObject("/AcroForm"): DictionaryObject()})
    root["/AcroForm"].update({NameObject("/NeedAppearances"): BooleanObject(True)})

def find_rects(reader: PdfReader, target_names, page_index=0):
    rects = {}
    pg = reader.pages[page_index]
    annots = pg.get("/Annots")
    if not annots: return rects
    try: arr = annots.get_object()
    except Exception: arr = annots
    for a in arr:
        obj = a.get_object()
        if obj.get("/Subtype")!="/Widget": continue
        nm = obj.get("/T")
        ft = obj.get("/FT")
        if ft != "/Tx" or nm not in target_names: continue
        r = obj.get("/Rect")
        if r and len(r)==4:
            rects[nm] = tuple(float(r[i]) for i in range(4))
    return rects

def build_overlay(page_w, page_h, rects_and_values, font="Helvetica", font_size=10.5, inset=2.0):
    packet = io.BytesIO()
    c = canvas.Canvas(packet, pagesize=(page_w, page_h))
    c.setFont(font, font_size)
    for rect, val in rects_and_values:
        if not val: continue
        x0,y0,x1,y1 = rect
        text_x = x0 + inset
        text_y = y1 - font_size - inset
        if text_y < y0 + inset: text_y = y0 + inset
        c.drawString(text_x, text_y, val)
    c.save()
    packet.seek(0)
    return PdfReader(packet)

def flatten_pdf(reader: PdfReader):
    out = PdfWriter()
    for i, page in enumerate(reader.pages):
        annots = page.get("/Annots")
        if annots:
            try: arr = annots.get_object()
            except Exception: arr = annots
            keep=[]
            for a in arr:
                try:
                    if a.get_object().get("/Subtype") != "/Widget":
                        keep.append(a)
                except Exception:
                    keep.append(a)
            if keep:
                page[NameObject("/Annots")] = keep
            else:
                if "/Annots" in page:
                    del page[NameObject("/Annots")]
        out.add_page(page)
    if "/AcroForm" in out._root_object:
        del out._root_object[NameObject("/AcroForm")]
    return out

def fill_pdf_for_employee(pdf_bytes: bytes, emp_row, final_df_emp, year_used: int):
    """
    Return (editable_filename, editable_bytes, flattened_filename, flattened_bytes)
    Function body is identical to original app.py but now calls build_part1_map and build_part2_map.
    """
    reader = PdfReader(io.BytesIO(pdf_bytes))
    page0 = reader.pages[0]
    W = float(page0.mediabox.width); H = float(page0.mediabox.height)

    # ---- Part I values (from Emp Demographic) ----
    part1_map, first_last = build_part1_map(emp_row)

    # ---- Part II codes from Final table (Line 14 & Line 16) ----
    part2_map = build_part2_map(final_df_emp)

    mapping = {}
    mapping.update(part1_map); mapping.update(part2_map)

    # ---- EDITABLE output (NeedAppearances + overlay burn-in on page 1) ----
    writer_edit = PdfWriter()
    for i in range(len(reader.pages)):
        writer_edit.add_page(reader.pages[i])

    # Update values across pages (safe)
    for i in range(len(writer_edit.pages)):
        try:
            writer_edit.update_page_form_field_values(writer_edit.pages[i], mapping)
        except Exception:
            pass

    # NeedAppearances
    root = writer_edit._root_object
    if "/AcroForm" not in root:
        root.update({NameObject("/AcroForm"): DictionaryObject()})
    root["/AcroForm"].update({NameObject("/NeedAppearances"): BooleanObject(True)})

    # Overlay for visibility
    rects = find_rects(reader, list(mapping.keys()), page_index=0)
    overlay_pairs = [(rects[nm], mapping[nm]) for nm in mapping if nm in rects and mapping[nm]]
    if overlay_pairs:
        overlay_pdf = build_overlay(W, H, overlay_pairs)
        writer_edit.pages[0].merge_page(overlay_pdf.pages[0])

    editable_name = f"1095c_filled_fields_{first_last}_{year_used}.pdf"
    editable_bytes = io.BytesIO()
    writer_edit.write(editable_bytes)
    editable_bytes.seek(0)

    # ---- FLATTENED output ----
    reader_after = PdfReader(io.BytesIO(editable_bytes.getvalue()))
    writer_flat = flatten_pdf(reader_after)
    flattened_name = f"1095c_filled_flattened_{first_last}_{year_used}.pdf"
    flattened_bytes = io.BytesIO()
    writer_flat.write(flattened_bytes)
    flattened_bytes.seek(0)

    return editable_name, editable_bytes, flattened_name, flattened_bytes
PY

cat > io_utils.py <<'PY'
# MOVED from app.py — preserve original code, only moved.
import io
import pandas as pd

def save_excel_outputs(interim: pd.DataFrame, final: pd.DataFrame, year:int) -> bytes:
    buf = io.BytesIO()
    with pd.ExcelWriter(buf, engine="xlsxwriter", datetime_format="yyyy-mm-dd") as xw:
        final.to_excel(xw, index=False, sheet_name=f"Final {year}")
        interim.to_excel(xw, index=False, sheet_name=f"Interim {year}")
    buf.seek(0)
    return buf.getvalue()
PY

cat > app.py <<'PY'
# MOVED from app.py — main Streamlit UI entrypoint. All business logic moved to modules.
import io
import zipfile
import pandas as pd
import streamlit as st

from interim_table import load_excel, prepare_inputs, build_interim, build_final, choose_report_year
from io_utils import save_excel_outputs
from pdf_helpers import fill_pdf_for_employee
from config import MONTHS

# ----------------------------
# Page config
# ----------------------------
st.set_page_config(page_title="ACA-1095 Builder", layout="wide")
st.title("ACA-1095 Builder")

# =========================
# UI — Step 1: Upload Excel
# =========================
st.subheader("1) Enter your Excel file")
excel_file = st.file_uploader("Upload ACA input workbook (.xlsx)", type=["xlsx"], key="excel")

interim_df = None
final_df = None
emp_demo_df = None
year_used = None

if excel_file is not None:
    try:
        data = load_excel(excel_file.getvalue())
        emp_demo_df, emp_status_df, emp_elig_df, emp_enroll_df, dep_enroll_df, pay_ded_df = prepare_inputs(data)
        year_used = choose_report_year(emp_elig_df)
        interim_df = build_interim(emp_demo_df, emp_status_df, emp_elig_df, emp_enroll_df, dep_enroll_df, year=year_used)
        final_df = build_final(interim_df)

        st.success(f"Processed successfully for YEAR = {year_used}")
        c1, c2 = st.columns(2)
        with c1:
            st.markdown("**Interim Table (preview)**")
            st.dataframe(interim_df.head(200), use_container_width=True)
        with c2:
            st.markdown("**Final Table (preview)**")
            st.dataframe(final_df.head(200), use_container_width=True)

        # Download combined Excel
        excel_bytes = save_excel_outputs(interim_df, final_df, year_used)
        st.download_button(
            label=f"Download Final & Interim Excel ({year_used})",
            data=excel_bytes,
            file_name=f"final_and_interim_{year_used}.xlsx",
            mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        )
    except Exception as e:
        st.error(f"Failed to process Excel: {e}")

# =========================
# UI — Step 2: Upload PDF
# =========================
st.subheader("2) Upload blank 1095-C PDF (employee copy, 2024 layout)")
pdf_file = st.file_uploader("Upload 1095-C PDF", type=["pdf"], key="pdf")

# =========================
# UI — Step 3: Generate PDFs
# =========================
st.subheader("3) Generate PDFs")

if excel_file is None:
    st.info("Upload the Excel workbook to continue.")
elif pdf_file is None:
    st.info("Upload the blank 1095-C PDF to enable PDF generation.")
else:
    # Single employee
    if emp_demo_df is not None and not emp_demo_df.empty:
        all_ids = sorted(emp_demo_df["employeeid"].astype(str).unique().tolist())
        selected_emp = st.selectbox("Choose EmployeeID to generate a single 1095-C PDF:", all_ids, index=0 if all_ids else None)
        colA, colB = st.columns(2)

        with colA:
            if st.button("Generate Single (Part I + Part II)", type="primary", use_container_width=True):
                try:
                    emp_row = emp_demo_df[emp_demo_df["employeeid"].astype(str)==selected_emp].iloc[0]
                    final_emp = final_df[final_df["EmployeeID"].astype(str)==selected_emp].copy()
                    if final_emp.empty:
                        final_emp = pd.DataFrame({"Month":MONTHS, "Line14_Final":[""]*12, "Line16_Final":[""]*12})
                    else:
                        ord_map = {m:i for i,m in enumerate(MONTHS, start=1)}
                        final_emp["_ord"] = final_emp["Month"].map(ord_map)
                        final_emp = final_emp.sort_values("_ord").drop(columns=["_ord"])

                    editable_name, editable_bytes, flat_name, flat_bytes = fill_pdf_for_employee(
                        pdf_file.getvalue(), emp_row, final_emp, year_used
                    )
                    st.success("PDFs generated for selected employee.")
                    st.download_button("Download Editable PDF", editable_bytes.getvalue(), file_name=editable_name, mime="application/pdf")
                    st.download_button("Download Flattened PDF", flat_bytes.getvalue(), file_name=flat_name, mime="application/pdf")
                except Exception as e:
                    st.error(f"Failed to generate PDFs: {e}")

        # Bulk
        with colB:
            st.write("Bulk generate for multiple employees")
            default_selection = all_ids if len(all_ids) <= 10 else all_ids[:10]
            bulk_ids = st.multiselect("Select employees (leave empty to generate for ALL)", all_ids, default=default_selection, key="bulk_ids")
            if st.button("Bulk Generate ZIP (Editable + Flattened for each)", use_container_width=True):
                try:
                    ids_to_run = bulk_ids if bulk_ids else all_ids
                    zip_buf = io.BytesIO()
                    with zipfile.ZipFile(zip_buf, mode="w", compression=zipfile.ZIP_DEFLATED) as z:
                        for emp_id in ids_to_run:
                            emp_row = emp_demo_df[emp_demo_df["employeeid"].astype(str)==emp_id]
                            if emp_row.empty:
                                continue
                            emp_row = emp_row.iloc[0]
                            final_emp = final_df[final_df["EmployeeID"].astype(str)==emp_id].copy()
                            if final_emp.empty:
                                final_emp = pd.DataFrame({"Month":MONTHS, "Line14_Final":[""]*12, "Line16_Final":[""]*12})
                            else:
                                ord_map = {m:i for i,m in enumerate(MONTHS, start=1)}
                                final_emp["_ord"] = final_emp["Month"].map(ord_map)
                                final_emp = final_emp.sort_values("_ord").drop(columns=["_ord"])

                            editable_name, editable_bytes, flat_name, flat_bytes = fill_pdf_for_employee(
                                pdf_file.getvalue(), emp_row, final_emp, year_used
                            )
                            z.writestr(editable_name, editable_bytes.getvalue())
                            z.writestr(flat_name, flat_bytes.getvalue())

                    zip_buf.seek(0)
                    st.success(f"Bulk ZIP generated ({len(ids_to_run)} employees).")
                    st.download_button(
                        "Download ZIP",
                        zip_buf.getvalue(),
                        file_name=f"1095c_bulk_{year_used}.zip",
                        mime="application/zip"
                    )
                except Exception as e:
                    st.error(f"Bulk generation failed: {e}")
    else:
        st.warning("No employees found in the uploaded Excel.")
PY

# Make files executable where relevant
chmod +x create-commit-modularize.sh || true

# Stage & commit
git add app.py fill_part1.py fill_part2.py interim_table.py pdf_helpers.py io_utils.py validation.py config.py
git commit -m "$COMMIT_MSG"

# Push branch
git push -u origin "$BRANCH"

echo "Done. Branch '$BRANCH' pushed. Open a PR from that branch on GitHub."
