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
