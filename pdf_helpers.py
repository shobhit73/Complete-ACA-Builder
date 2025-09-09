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
