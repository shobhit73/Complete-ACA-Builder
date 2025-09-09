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
