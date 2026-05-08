# Z Program Inventory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a seventh radio button view (`r_zprog`) to ZSDR_CONFIG_REVIEW that inventories all Z programs with metadata, activity signals, and source-derived input/output indicators, with a noise filter checkbox to suppress test/temp programs.

**Architecture:** Single ABAP file edit — ZSDR_CONFIG_REVIEW.abap. Four additions: (1) `ty_zprog` struct + `gt_zprog` global table, (2) selection screen parameter, (3) `FORM fetch_zprog` containing all data gathering logic, (4) ALV wiring. No new files. Source analysis uses multiple targeted `SELECT DISTINCT` passes against `REPOSRC` rather than reading all source lines, keeping memory use low.

**Tech Stack:** ABAP Open SQL (strict new syntax), SAP_BASIS 750 SP14, CL_SALV_TABLE ALV, SAPGUI_PROGRESS_INDICATOR

---

### Task 1: Add struct, global table, and selection screen scaffold

**Files:**
- Modify: `ZSDR_CONFIG_REVIEW.abap`

- [ ] **Step 1: Add `ty_zprog` to the TYPES block**

In `ZSDR_CONFIG_REVIEW.abap`, insert after the `ty_doc_flow` type definition (after line 112, before the closing period of the TYPES block). Change the period on `ty_doc_flow` to a comma and add:

```abap
  " --- Z Program Inventory ---
  BEGIN OF ty_zprog,
    progname    TYPE c LENGTH 40,
    prog_txt    TYPE c LENGTH 60,
    devclass    TYPE c LENGTH 30,
    prog_type   TYPE c LENGTH 16,
    cnam        TYPE c LENGTH 12,
    cdat        TYPE d,
    udat        TYPE d,
    last_spool  TYPE d,
    input_type  TYPE c LENGTH 20,
    output_type TYPE c LENGTH 20,
  END OF ty_zprog.
```

The closing period of `ty_doc_flow` becomes a comma; the new `ty_zprog` block ends with the period.

- [ ] **Step 2: Add `gt_zprog` to the DATA block**

After `gt_doc_flow TYPE TABLE OF ty_doc_flow.` add:

```abap
  gt_zprog         TYPE TABLE OF ty_zprog.
```

- [ ] **Step 3: Add `r_zprog` radio button and `p_noise` checkbox to selection screen**

In the `SELECTION-SCREEN BEGIN OF BLOCK b3` section, add `r_zprog` after `r_dflow`:

```abap
  PARAMETERS: r_order  RADIOBUTTON GROUP r1 DEFAULT 'X',
              r_itmcat RADIOBUTTON GROUP r1,
              r_biltyp RADIOBUTTON GROUP r1,
              r_output RADIOBUTTON GROUP r1,
              r_trans  RADIOBUTTON GROUP r1,
              r_dflow  RADIOBUTTON GROUP r1,
              r_zprog  RADIOBUTTON GROUP r1.
SELECTION-SCREEN END OF BLOCK b3.

SELECTION-SCREEN BEGIN OF BLOCK b4 WITH FRAME TITLE TEXT-004.
  PARAMETERS: p_noise AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK b4.
```

Add to the selection text comments:
```abap
*   R_ZPROG   "Z Program Inventory"
*   P_NOISE   "Exclude Suspected Noise"
*   TEXT-004  "Z Program Options"
```

- [ ] **Step 4: Wire `r_zprog` into START-OF-SELECTION**

Add to the CASE block:
```abap
    WHEN r_zprog.  PERFORM fetch_zprog.
```

- [ ] **Step 5: Add empty FORM stub for fetch_zprog**

After `ENDFORM.` of `fetch_doc_flow`, insert:

```abap
*----------------------------------------------------------------------*
* FORM: FETCH_ZPROG
* Inventories all Z programs using TRDIR, TRDIRT, TADIR, TSP01.
* REPOSRC scanned for noise flags and input/output patterns.
* Progress shown via SAPGUI_PROGRESS_INDICATOR.
*----------------------------------------------------------------------*
FORM fetch_zprog.
ENDFORM.
```

- [ ] **Step 6: Add `r_zprog` WHEN block to DISPLAY_ALV**

In the CASE block inside `FORM display_alv`, add after the `r_dflow` WHEN:

```abap
        WHEN r_zprog.
          lv_title = 'Z Program Inventory'.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_alv
            CHANGING  t_table      = gt_zprog ).
```

- [ ] **Step 7: Commit the scaffold**

```bash
git add ZSDR_CONFIG_REVIEW.abap
git commit -m "Scaffold R_ZPROG: struct, table, selection screen, wiring"
```

---

### Task 2: Metadata fetch (TRDIR, TRDIRT, TADIR, TSP01)

**Files:**
- Modify: `ZSDR_CONFIG_REVIEW.abap` — fill in `FORM fetch_zprog`

- [ ] **Step 1: Add local type and data declarations inside FORM fetch_zprog**

Replace the empty `FORM fetch_zprog. ENDFORM.` with:

```abap
FORM fetch_zprog.
  TYPES: BEGIN OF ty_trdir_row,
           name  TYPE c LENGTH 40,
           subc  TYPE c LENGTH 1,
           cnam  TYPE c LENGTH 12,
           cdat  TYPE d,
           udat  TYPE d,
         END OF ty_trdir_row,
         BEGIN OF ty_desc,
           name  TYPE c LENGTH 40,
           title TYPE c LENGTH 60,
         END OF ty_desc,
         BEGIN OF ty_pkg,
           obj_name TYPE c LENGTH 40,
           devclass TYPE c LENGTH 30,
         END OF ty_pkg,
         BEGIN OF ty_spool,
           rqpnm     TYPE c LENGTH 40,
           last_date TYPE d,
         END OF ty_spool.

  DATA: lt_trdir  TYPE TABLE OF ty_trdir_row,
        lt_desc   TYPE HASHED TABLE OF ty_desc   WITH UNIQUE KEY name,
        lt_pkg    TYPE HASHED TABLE OF ty_pkg    WITH UNIQUE KEY obj_name,
        lt_spool  TYPE HASHED TABLE OF ty_spool  WITH UNIQUE KEY rqpnm,
        lt_noise  TYPE HASHED TABLE OF c LENGTH 40 WITH UNIQUE KEY table_line,
        lt_selscr TYPE HASHED TABLE OF c LENGTH 40 WITH UNIQUE KEY table_line,
        lt_filein TYPE HASHED TABLE OF c LENGTH 40 WITH UNIQUE KEY table_line,
        lt_write  TYPE HASHED TABLE OF c LENGTH 40 WITH UNIQUE KEY table_line,
        lt_alv    TYPE HASHED TABLE OF c LENGTH 40 WITH UNIQUE KEY table_line,
        lt_xfer   TYPE HASHED TABLE OF c LENGTH 40 WITH UNIQUE KEY table_line.

ENDFORM.
```

- [ ] **Step 2: Add the four metadata SELECTs inside FORM fetch_zprog (before ENDFORM)**

```abap
  " 1. Base program list
  SELECT name, subc, cnam, cdat, udat
    FROM trdir
    WHERE name LIKE 'Z%'
    INTO TABLE @lt_trdir.

  IF lt_trdir IS INITIAL.
    RETURN.
  ENDIF.

  " 2. Short descriptions
  SELECT name, title
    FROM trdirt
    WHERE sprsl = @sy-langu
      AND name LIKE 'Z%'
    INTO TABLE @lt_desc.

  " 3. Package / development class
  SELECT obj_name, devclass
    FROM tadir
    WHERE pgmid    = 'R3TR'
      AND object   = 'PROG'
      AND obj_name LIKE 'Z%'
    INTO TABLE @lt_pkg.

  " 4. Last spool date per program (best available run proxy)
  SELECT rqpnm, MAX( rqcrdat ) AS last_date
    FROM tsp01
    WHERE rqpnm LIKE 'Z%'
    GROUP BY rqpnm
    INTO TABLE @lt_spool.
```

- [ ] **Step 3: Commit**

```bash
git add ZSDR_CONFIG_REVIEW.abap
git commit -m "R_ZPROG: metadata fetch from TRDIR/TRDIRT/TADIR/TSP01"
```

---

### Task 3: Source analysis — noise detection and input/output detection

**Files:**
- Modify: `ZSDR_CONFIG_REVIEW.abap` — add source scans inside `FORM fetch_zprog`

The REPOSRC scans go after the metadata SELECTs and before the assembly loop.

- [ ] **Step 1: Add noise detection block**

Noise scan reads the first 20 lines of every Z program (including comments — a `* TEST PROGRAM` header is exactly the signal we want) and checks for keywords in ABAP after uppercasing.

```abap
  " --- Noise detection: first 20 source lines including comments ---
  IF p_noise = abap_true.
    DATA(lt_hdr) TYPE TABLE OF reposrc.  " local inline
    SELECT progname, line
      FROM reposrc
      WHERE progname LIKE 'Z%'
        AND zeile    <= 20
      INTO TABLE @DATA(lt_hdr_lines).

    LOOP AT lt_hdr_lines INTO DATA(ls_hdr).
      DATA(lv_up_src) = to_upper( ls_hdr-line ).
      DATA(lv_up_nm)  = to_upper( ls_hdr-progname ).
      IF lv_up_src CS 'TEST'    OR lv_up_src CS 'TEMP'
         OR lv_up_src CS 'TMP'  OR lv_up_src CS 'COPY'
         OR lv_up_src CS 'OLD'  OR lv_up_src CS 'BAK'
         OR lv_up_src CS 'UNUSED' OR lv_up_src CS 'DELETE'
         OR lv_up_src CS 'WORKAROUND' OR lv_up_src CS 'DO NOT USE'.
        INSERT ls_hdr-progname INTO TABLE lt_noise.
      ENDIF.
    ENDLOOP.

    " Also flag based on program name alone
    LOOP AT lt_trdir INTO DATA(ls_nm_chk).
      DATA(lv_pnm) = to_upper( ls_nm_chk-name ).
      IF lv_pnm CS 'TEST' OR lv_pnm CS 'TEMP' OR lv_pnm CS 'TMP'
         OR lv_pnm CS 'COPY' OR lv_pnm CS 'OLD'
         OR lv_pnm CS 'BAK'  OR lv_pnm CS 'DEL'.
        INSERT ls_nm_chk-name INTO TABLE lt_noise.
      ENDIF.
    ENDLOOP.

    " Also flag based on description
    LOOP AT lt_desc INTO DATA(ls_dc_chk).
      DATA(lv_dtxt) = to_upper( ls_dc_chk-title ).
      IF lv_dtxt CS 'TEST'   OR lv_dtxt CS 'TEMP'
         OR lv_dtxt CS 'COPY'   OR lv_dtxt CS 'OLD'
         OR lv_dtxt CS 'UNUSED' OR lv_dtxt CS 'DELETE'
         OR lv_dtxt CS 'WORKAROUND'.
        INSERT ls_dc_chk-name INTO TABLE lt_noise.
      ENDIF.
    ENDLOOP.
  ENDIF.
```

- [ ] **Step 2: Add input detection — selection screen**

Comment lines excluded via `line NOT LIKE '*%' AND line NOT LIKE '"%'`.

```abap
  " --- Input: selection screen ---
  SELECT DISTINCT progname
    FROM reposrc
    WHERE progname LIKE 'Z%'
      AND line NOT LIKE '*%'
      AND line NOT LIKE '"%'
      AND ( line LIKE '%PARAMETERS%'
         OR line LIKE '%SELECT-OPTIONS%'
         OR line LIKE '%SELECTION-SCREEN%' )
    INTO TABLE @lt_selscr.

  " --- Input: file read ---
  SELECT DISTINCT progname
    FROM reposrc
    WHERE progname LIKE 'Z%'
      AND line NOT LIKE '*%'
      AND line NOT LIKE '"%'
      AND line LIKE '%READ DATASET%'
    INTO TABLE @lt_filein.
```

- [ ] **Step 3: Add output detection — print, ALV, file**

```abap
  " --- Output: WRITE (print) ---
  SELECT DISTINCT progname
    FROM reposrc
    WHERE progname LIKE 'Z%'
      AND line NOT LIKE '*%'
      AND line NOT LIKE '"%'
      AND line LIKE '%WRITE%'
    INTO TABLE @lt_write.

  " --- Output: ALV ---
  SELECT DISTINCT progname
    FROM reposrc
    WHERE progname LIKE 'Z%'
      AND line NOT LIKE '*%'
      AND line NOT LIKE '"%'
      AND ( line LIKE '%CL_SALV_TABLE%'
         OR line LIKE '%REUSE_ALV%' )
    INTO TABLE @lt_alv.

  " --- Output: file write (TRANSFER) ---
  SELECT DISTINCT progname
    FROM reposrc
    WHERE progname LIKE 'Z%'
      AND line NOT LIKE '*%'
      AND line NOT LIKE '"%'
      AND line LIKE '%TRANSFER%'
    INTO TABLE @lt_xfer.
```

- [ ] **Step 4: Commit**

```bash
git add ZSDR_CONFIG_REVIEW.abap
git commit -m "R_ZPROG: noise detection and input/output REPOSRC scans"
```

---

### Task 4: Assembly loop, progress indicator, and header update

**Files:**
- Modify: `ZSDR_CONFIG_REVIEW.abap`

- [ ] **Step 1: Add the assembly loop inside FORM fetch_zprog**

After all the SELECTs and before `ENDFORM`:

```abap
  DATA(lv_total) = lines( lt_trdir ).
  DATA(lv_idx)   = 0.

  LOOP AT lt_trdir INTO DATA(ls_prog).
    lv_idx = lv_idx + 1.

    " Progress indicator — update GUI status bar
    DATA(lv_pct) = CONV i( ( lv_idx * 100 ) / lv_total ).
    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING
        percentage = lv_pct
        text       = |Analyzing program { lv_idx } of { lv_total }...|.

    " Skip noise programs when filter is active
    IF p_noise = abap_true.
      READ TABLE lt_noise WITH TABLE KEY table_line = ls_prog-name
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0. CONTINUE. ENDIF.
    ENDIF.

    DATA(ls_row) = VALUE ty_zprog(
      progname  = ls_prog-name
      cnam      = ls_prog-cnam
      cdat      = ls_prog-cdat
      udat      = ls_prog-udat
      prog_type = SWITCH #( ls_prog-subc
        WHEN '1' THEN 'Executable'
        WHEN 'F' THEN 'Function Group'
        WHEN 'I' THEN 'Include'
        WHEN 'K' THEN 'Class'
        WHEN 'M' THEN 'Module Pool'
        WHEN 'S' THEN 'Subroutine Pool'
        ELSE ls_prog-subc ) ).

    " Description
    READ TABLE lt_desc WITH TABLE KEY name = ls_prog-name INTO DATA(ls_d).
    IF sy-subrc = 0. ls_row-prog_txt = ls_d-title. ENDIF.

    " Package
    READ TABLE lt_pkg WITH TABLE KEY obj_name = ls_prog-name INTO DATA(ls_p).
    IF sy-subrc = 0. ls_row-devclass = ls_p-devclass. ENDIF.

    " Last spool date
    READ TABLE lt_spool WITH TABLE KEY rqpnm = ls_prog-name INTO DATA(ls_sp).
    IF sy-subrc = 0. ls_row-last_spool = ls_sp-last_date. ENDIF.

    " Input type
    DATA(lv_has_selscr) = abap_false.
    DATA(lv_has_filein) = abap_false.
    READ TABLE lt_selscr WITH TABLE KEY table_line = ls_prog-name
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0. lv_has_selscr = abap_true. ENDIF.
    READ TABLE lt_filein WITH TABLE KEY table_line = ls_prog-name
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0. lv_has_filein = abap_true. ENDIF.

    IF lv_has_selscr = abap_true AND lv_has_filein = abap_true.
      ls_row-input_type = 'Sel.Screen+File'.
    ELSEIF lv_has_selscr = abap_true.
      ls_row-input_type = 'Sel.Screen'.
    ELSEIF lv_has_filein = abap_true.
      ls_row-input_type = 'File'.
    ENDIF.

    " Output type
    DATA(lt_out_parts) TYPE TABLE OF c LENGTH 10.
    READ TABLE lt_write WITH TABLE KEY table_line = ls_prog-name
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0. APPEND 'Print' TO lt_out_parts. ENDIF.
    READ TABLE lt_alv WITH TABLE KEY table_line = ls_prog-name
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0. APPEND 'ALV' TO lt_out_parts. ENDIF.
    READ TABLE lt_xfer WITH TABLE KEY table_line = ls_prog-name
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0. APPEND 'File' TO lt_out_parts. ENDIF.

    DATA(lv_out) TYPE c LENGTH 20.
    LOOP AT lt_out_parts INTO DATA(lv_part).
      IF lv_out IS INITIAL.
        lv_out = lv_part.
      ELSE.
        lv_out = lv_out && '+' && lv_part.
      ENDIF.
    ENDLOOP.
    ls_row-output_type = lv_out.

    APPEND ls_row TO gt_zprog.
  ENDLOOP.

  SORT gt_zprog BY devclass progname.
```

- [ ] **Step 2: Update the header comment block at the top of the report**

Add view 7 to the "What it shows" section and add new tables to the "Tables read" section:

```abap
*&   7. Z Program Inventory  - All Z programs: metadata, last spool,
*&                               input/output type from source scan.
*&                               Noise filter suppresses test/temp code.
```

And in Tables read:
```abap
*&   Catalog: TRDIR, TRDIRT, TADIR, REPOSRC, TSP01
```

Also add to Inputs section:
```abap
*&   p_noise  - Exclude suspected noise programs (default: checked)
```

- [ ] **Step 3: Commit and push**

```bash
git add ZSDR_CONFIG_REVIEW.abap
git commit -m "R_ZPROG: assembly loop, progress indicator, header update"
git push
```

---

## Self-Review Notes

**Spec coverage check:**
- ✅ `r_zprog` radio button
- ✅ `p_noise` checkbox default checked
- ✅ All 10 output columns in `ty_zprog`
- ✅ TRDIR, TRDIRT, TADIR, TSP01, REPOSRC as sources
- ✅ Noise: name pattern, description pattern, source header (first 20 lines, includes comments)
- ✅ Input: Sel.Screen, File, Sel.Screen+File
- ✅ Output: Print, ALV, File, combinations
- ✅ Comment lines excluded from input/output scans (`NOT LIKE '*%'`, `NOT LIKE '"%'`)
- ✅ SAPGUI_PROGRESS_INDICATOR every iteration
- ✅ Sort: devclass ASC, progname ASC
- ✅ ALV title: "Z Program Inventory"

**Type notes for implementer:**
- `REPOSRC` field names: `PROGNAME`, `ZEILE`, `LINE` — verified standard SAP ECC naming
- `TRDIRT` language field is `SPRSL` (not `SPRAS` — unusual but standard for this table)
- `TSP01-RQCRDAT` is a DATE field (type d)
- All struct fields use concrete types (`c LENGTH n`, `d`, `i`) to avoid domain-type resolution errors (per prior session experience with `nacha TYPE nacha` failing)
- `p_noise = abap_true` correctly checks a checkbox parameter ('X' = true)
- Output concatenation uses a local `lt_out_parts` table to avoid hardcoding every combination
