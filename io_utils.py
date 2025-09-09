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
