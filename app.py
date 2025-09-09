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
