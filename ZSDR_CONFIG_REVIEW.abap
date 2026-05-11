*&---------------------------------------------------------------------*
*& Report  ZSDR_CONFIG_REVIEW
*& Title:  SD Module Configuration & Transactional Review
*&---------------------------------------------------------------------*
*& Purpose
*&   Read-only diagnostic report for the SD (Sales & Distribution)
*&   module. Cross-references master configuration against actual
*&   transactional volume so consultants can quickly see which
*&   document types, output records, and account determinations
*&   are configured AND in active use within a chosen sales area
*&   and date range.
*&
*& What it shows (one view per run, picked via radio button)
*&   1. Order Doc Types        - TVAK + TVAKT description + count of
*&                               VBAK orders per order type
*&   2. Item Categories        - T184 determination joined to TVAPT
*&                               for item-category descriptions
*&   3. Billing Types          - TVFK + TVFKT description + count of
*&                               VBRK invoices per billing type
*&   4. Output Records         - NACH condition records (V1/V2/V3),
*&                               counts grouped by KAPPL + KSCHL
*&   5. Transactional Summary  - Order count and net value by
*&                               (auart, vkorg) aggregated across
*&                               the selected date range
*&   6. Document Flow          - Order-type to billing-type paths via
*&                               VBRK->VBRP->VBAK join (VBRP-AUBEL)
*&   7. Z Program Inventory   - All Z programs: metadata, last spool,
*&                               input/output type from source scan;
*&                               noise filter suppresses test/temp code
*&
*& Inputs
*&   s_vkorg  - sales org filter (Distribution Channel and Division
*&              are hardcoded to '01' — always constant in this system)
*&   s_auart  - order-type filter
*&   s_erdat  - date range (default: last 180 days; required for billing/trans views)
*&   p_noise  - Exclude suspected noise programs (default: checked)
*&
*& Tables read (READ-ONLY; no UPDATE / INSERT / MODIFY / DELETE /
*& COMMIT against any database table — internal-table DELETE
*& ADJACENT DUPLICATES is the only DELETE in the program):
*&   Config:  TVAK, TVAKT, T184, TVAPT, TVFK, TVFKT
*&   Trans:   VBAK, VBRK, NACH
*&   Catalog: TRDIR, TRDIRT, TADIR, REPOSRC, TSP01
*&
*& Output
*&   Object-oriented ALV display via CL_SALV_TABLE. The selection
*&   screen offers six radio buttons; one report run shows one
*&   view. Re-run the report to switch views. No spool, no file
*&   output, no remote calls.
*&
*& Compatibility
*&   Requires SAP_BASIS 7.40 SP05 or higher (uses VALUE / COND /
*&   inline DATA / strict Open SQL). Verified on 7.50 SP14.
*&---------------------------------------------------------------------*
REPORT zsdr_config_review.

*----------------------------------------------------------------------*
* TABLE WORK AREAS
* Required for SELECT-OPTIONS FOR vbak-<field> to resolve the
* column reference at compile time.
*----------------------------------------------------------------------*
TABLES: vbak.

*----------------------------------------------------------------------*
* TYPE DEFINITIONS
*----------------------------------------------------------------------*
TYPES:
  " --- Sales Order Config ---
  BEGIN OF ty_vbak_types,
    auart     TYPE auart,
    vkorg     TYPE vkorg,
    bezei     TYPE text30,
    count     TYPE i,
  END OF ty_vbak_types,

  BEGIN OF ty_item_cat,
    auart     TYPE auart,
    pstyv     TYPE pstyv,
    vtext     TYPE text30,
  END OF ty_item_cat,

  " --- Billing Config ---
  BEGIN OF ty_bill_types,
    fkart     TYPE fkart,
    vkorg     TYPE vkorg,
    vtext     TYPE text30,
    count     TYPE i,
  END OF ty_bill_types,

  " --- Output / NACE ---
  BEGIN OF ty_output,
    kappl     TYPE kappl,
    appl_txt  TYPE c LENGTH 20,
    kschl     TYPE kschl,
    medium    TYPE c LENGTH 12,
    count     TYPE i,
  END OF ty_output,

  " --- Transactional Summary ---
  BEGIN OF ty_trans_summary,
    auart   TYPE auart,
    vkorg   TYPE vkorg,
    waerk   TYPE waerk,
    ord_cnt TYPE i,
    net_val TYPE netwr,
  END OF ty_trans_summary,

  " --- Document Flow ---
  BEGIN OF ty_doc_flow,
    vkorg     TYPE vkorg,
    auart     TYPE auart,
    auart_txt TYPE text30,
    fkart     TYPE fkart,
    fkart_txt TYPE text30,
    bill_cnt  TYPE i,
  END OF ty_doc_flow,

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

*----------------------------------------------------------------------*
* INTERNAL TABLES
*----------------------------------------------------------------------*
DATA:
  gt_vbak_types    TYPE TABLE OF ty_vbak_types,
  gt_item_cat      TYPE TABLE OF ty_item_cat,
  gt_bill_types    TYPE TABLE OF ty_bill_types,
  gt_output        TYPE TABLE OF ty_output,
  gt_trans_summary TYPE TABLE OF ty_trans_summary,
  gt_doc_flow      TYPE TABLE OF ty_doc_flow,
  gt_zprog         TYPE TABLE OF ty_zprog.

*----------------------------------------------------------------------*
* SELECTION SCREEN
*
* Text elements are maintained in SE38 -> Goto -> Text Elements.
*
* Text Symbols (block frame titles):
*   TEXT-001  "Selection Criteria"
*   TEXT-003  "View (pick one)"
*
* Selection Texts (SE38 -> Goto -> Text Elements -> Selection Texts):
*   S_VKORG   "Sales Organization"
*   S_AUART   "Order Type"
*   S_ERDAT   "Date Range"
*   R_ORDER   "Order Document Types"
*   R_ITMCAT  "Item Categories"
*   R_BILTYP  "Billing Document Types"
*   R_OUTPUT  "Output Condition Records"
*   R_TRANS   "Transactional Summary"
*   R_DFLOW   "Order to Invoice Document Flow"
*   R_ZPROG   "Z Program Inventory"
*   P_NOISE   "Exclude Suspected Noise"
*   TEXT-004  "Z Program Options"
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  SELECT-OPTIONS: s_vkorg FOR vbak-vkorg,
                  s_auart FOR vbak-auart,
                  s_erdat FOR vbak-erdat.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-003.
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

*----------------------------------------------------------------------*
* INITIALIZATION
*----------------------------------------------------------------------*
INITIALIZATION.
  s_erdat-sign   = 'I'.
  s_erdat-option = 'BT'.
  s_erdat-low    = sy-datum - 180.
  s_erdat-high   = sy-datum.
  APPEND s_erdat TO s_erdat[].

*----------------------------------------------------------------------*
* SELECTION SCREEN VALIDATION
*----------------------------------------------------------------------*
AT SELECTION-SCREEN.
  IF s_erdat[] IS INITIAL AND
     ( r_biltyp = abap_true OR r_trans = abap_true OR r_dflow = abap_true ).
    MESSAGE e398(00) WITH 'Date range is required for this view'.
  ENDIF.

*----------------------------------------------------------------------*
* START OF SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  CASE 'X'.
    WHEN r_order.  PERFORM fetch_sd_order_types.
    WHEN r_itmcat. PERFORM fetch_item_categories.
    WHEN r_biltyp. PERFORM fetch_billing_types.
    WHEN r_output. PERFORM fetch_nace_output.
    WHEN r_trans.  PERFORM fetch_transactional_summary.
    WHEN r_dflow.  PERFORM fetch_doc_flow.
    WHEN r_zprog.  PERFORM fetch_zprog.
  ENDCASE.

END-OF-SELECTION.
  PERFORM display_alv.

*----------------------------------------------------------------------*
* FORM: FETCH_SD_ORDER_TYPES
* Reads sales document type config from TVAK.
* Order counts fetched in a single GROUP BY query — no SELECT in loop.
*----------------------------------------------------------------------*
FORM fetch_sd_order_types.
  TYPES: BEGIN OF ty_tvak_desc,
           auart TYPE auart,
           bezei TYPE text30,
         END OF ty_tvak_desc,
         BEGIN OF ty_vkorg_cnt,
           auart TYPE auart,
           vkorg TYPE vkorg,
           cnt   TYPE i,
         END OF ty_vkorg_cnt.

  DATA: lt_desc TYPE HASHED TABLE OF ty_tvak_desc WITH UNIQUE KEY auart,
        lt_raw  TYPE TABLE OF ty_vkorg_cnt.

  SELECT a~auart, t~bezei
    FROM tvak AS a
    LEFT OUTER JOIN tvakt AS t
      ON t~auart = a~auart
     AND t~spras = @sy-langu
    INTO CORRESPONDING FIELDS OF TABLE @lt_desc.

  SELECT auart, vkorg, COUNT(*) AS cnt
    FROM vbak
    WHERE vkorg IN @s_vkorg
      AND vtweg = '01'
      AND spart = '01'
    GROUP BY auart, vkorg
    INTO TABLE @lt_raw.

  LOOP AT lt_raw INTO DATA(ls_raw).
    DATA(ls_row) = VALUE ty_vbak_types(
      auart = ls_raw-auart
      vkorg = ls_raw-vkorg
      count = ls_raw-cnt ).
    READ TABLE lt_desc WITH TABLE KEY auart = ls_raw-auart INTO DATA(ls_desc).
    IF sy-subrc = 0. ls_row-bezei = ls_desc-bezei. ENDIF.
    APPEND ls_row TO gt_vbak_types.
  ENDLOOP.

  SORT gt_vbak_types BY vkorg count DESCENDING.
ENDFORM.

*----------------------------------------------------------------------*
* FORM: FETCH_ITEM_CATEGORIES
* T184 is a pooled table — JOINs not supported on ECC.
* Two separate SELECTs merged in ABAP: T184 for determination entries,
* TVAPT for language-dependent descriptions.
*----------------------------------------------------------------------*
FORM fetch_item_categories.
  TYPES: BEGIN OF ty_tvapt,
           pstyv TYPE pstyv,
           vtext TYPE text30,
         END OF ty_tvapt,
         BEGIN OF ty_auart_cnt,
           auart TYPE auart,
           cnt   TYPE i,
         END OF ty_auart_cnt.

  DATA: lt_tvapt     TYPE HASHED TABLE OF ty_tvapt     WITH UNIQUE KEY pstyv,
        lt_auart_cnt TYPE HASHED TABLE OF ty_auart_cnt WITH UNIQUE KEY auart.

  " T184 is pooled — small config table, fast
  SELECT auart, pstyv
    FROM t184
    WHERE auart IN @s_auart
    INTO TABLE @DATA(lt_t184).

  SORT lt_t184 BY auart pstyv.
  DELETE ADJACENT DUPLICATES FROM lt_t184 COMPARING auart pstyv.

  IF lt_t184 IS INITIAL.
    RETURN.
  ENDIF.

  SELECT pstyv, vtext
    FROM tvapt
    WHERE spras = @sy-langu
    INTO TABLE @lt_tvapt.

  " Count orders per auart via VBAK only — VKORG index keeps this fast.
  " Avoids joining VBAP (no index on PSTYV, full scan on large table).
  " COUNT field shows orders of that type, not item-level occurrences.
  SELECT auart, COUNT(*) AS cnt
    FROM vbak
    WHERE vkorg IN @s_vkorg
      AND vtweg = '01'
      AND spart = '01'
      AND auart IN @s_auart
    GROUP BY auart
    INTO TABLE @lt_auart_cnt.

  LOOP AT lt_t184 INTO DATA(ls_t184).
    READ TABLE lt_auart_cnt WITH TABLE KEY auart = ls_t184-auart
      INTO DATA(ls_cnt).
    IF sy-subrc <> 0 OR ls_cnt-cnt = 0.
      CONTINUE.
    ENDIF.
    DATA(ls_item) = VALUE ty_item_cat(
      auart = ls_t184-auart
      pstyv = ls_t184-pstyv ).
    READ TABLE lt_tvapt WITH TABLE KEY pstyv = ls_t184-pstyv
      INTO DATA(ls_tv).
    IF sy-subrc = 0.
      ls_item-vtext = ls_tv-vtext.
    ENDIF.
    APPEND ls_item TO gt_item_cat.
  ENDLOOP.

  SORT gt_item_cat BY auart pstyv.
ENDFORM.

*----------------------------------------------------------------------*
* FORM: FETCH_BILLING_TYPES
* Reads billing document type config from TVFK.
* Invoice counts fetched in a single GROUP BY query — no SELECT in loop.
*----------------------------------------------------------------------*
FORM fetch_billing_types.
  TYPES: BEGIN OF ty_fkart_raw,
           fkart TYPE fkart,
           vkorg TYPE vkorg,
           cnt   TYPE i,
         END OF ty_fkart_raw,
         BEGIN OF ty_tvfkt,
           fkart TYPE fkart,
           vtext TYPE text30,
         END OF ty_tvfkt.

  DATA: lt_raw   TYPE TABLE OF ty_fkart_raw,
        lt_tvfkt TYPE HASHED TABLE OF ty_tvfkt WITH UNIQUE KEY fkart.

  SELECT fkart, vkorg, COUNT(*) AS cnt
    FROM vbrk
    WHERE vkorg IN @s_vkorg
      AND vtweg = '01'
      AND spart = '01'
    GROUP BY fkart, vkorg
    INTO TABLE @lt_raw.

  IF lt_raw IS INITIAL.
    RETURN.
  ENDIF.

  SELECT fkart, vtext
    FROM tvfkt
    WHERE spras = @sy-langu
    INTO TABLE @lt_tvfkt.

  LOOP AT lt_raw INTO DATA(ls_raw).
    DATA(ls_bill) = VALUE ty_bill_types(
      fkart = ls_raw-fkart
      vkorg = ls_raw-vkorg
      count = ls_raw-cnt ).
    READ TABLE lt_tvfkt WITH TABLE KEY fkart = ls_raw-fkart INTO DATA(ls_ft).
    IF sy-subrc = 0. ls_bill-vtext = ls_ft-vtext. ENDIF.
    APPEND ls_bill TO gt_bill_types.
  ENDLOOP.

  SORT gt_bill_types BY vkorg ASCENDING count DESCENDING.
ENDFORM.

*----------------------------------------------------------------------*
* FORM: FETCH_NACE_OUTPUT
* Summarizes output condition records from NACH using GROUP BY —
* replaces the previous loop-based accumulation.
*----------------------------------------------------------------------*
FORM fetch_nace_output.
  TYPES: BEGIN OF ty_nach_raw,
           kappl TYPE kappl,
           kschl TYPE kschl,
           nacha TYPE c LENGTH 1,
           cnt   TYPE i,
         END OF ty_nach_raw.

  DATA lt_raw TYPE TABLE OF ty_nach_raw.

  SELECT kappl, kschl, nacha, COUNT(*) AS cnt
    FROM nach
    WHERE kappl IN ( 'V1', 'V2', 'V3' )
    GROUP BY kappl, kschl, nacha
    INTO TABLE @lt_raw.

  LOOP AT lt_raw INTO DATA(ls_raw).
    APPEND VALUE ty_output(
      kappl    = ls_raw-kappl
      kschl    = ls_raw-kschl
      medium   = SWITCH #( ls_raw-nacha
        WHEN '1' THEN 'Print'
        WHEN '2' THEN 'Fax'
        WHEN '3' THEN 'Telex'
        WHEN '5' THEN 'Ext. Send'
        WHEN '6' THEN 'EDI'
        WHEN '7' THEN 'Simple Mail'
        WHEN '8' THEN 'Special'
        WHEN 'A' THEN 'Events'
        ELSE ls_raw-nacha )
      count    = ls_raw-cnt
      appl_txt = SWITCH #( ls_raw-kappl
        WHEN 'V1' THEN 'Sales'
        WHEN 'V2' THEN 'Shipping'
        WHEN 'V3' THEN 'Billing' ) ) TO gt_output.
  ENDLOOP.

  SORT gt_output BY kappl kschl medium.
ENDFORM.

*----------------------------------------------------------------------*
* FORM: FETCH_TRANSACTIONAL_SUMMARY
* Order count and net order value by order type and sales area,
* aggregated across the full selected date range. One row per
* (auart, vkorg) — use s_erdat to scope the period.
*----------------------------------------------------------------------*
FORM fetch_transactional_summary.
  SELECT auart, vkorg, waerk,
         COUNT(*) AS ord_cnt,
         SUM( netwr ) AS net_val
    FROM vbak
    WHERE vkorg IN @s_vkorg
      AND vtweg = '01'
      AND spart = '01'
      AND auart IN @s_auart
      AND erdat IN @s_erdat
    GROUP BY auart, vkorg, waerk
    INTO CORRESPONDING FIELDS OF TABLE @gt_trans_summary.

  SORT gt_trans_summary BY vkorg waerk ord_cnt DESCENDING.
ENDFORM.

*----------------------------------------------------------------------*
* FORM: FETCH_DOC_FLOW
* Shows order-type to billing-type document flow paths.
* VBRK->VBRP->VBAK join via VBRP-AUBEL (billing item back-reference).
* COUNT DISTINCT on billing doc avoids inflating multi-item invoices.
* Date filter on VBRK-FKDAT limits VBRP rows read; GROUP BY keeps result small.
*----------------------------------------------------------------------*
FORM fetch_doc_flow.
  TYPES: BEGIN OF ty_raw,
           auart    TYPE auart,
           fkart    TYPE fkart,
           vkorg    TYPE vkorg,
           bill_cnt TYPE i,
         END OF ty_raw,
         BEGIN OF ty_tvakt,
           auart TYPE auart,
           bezei TYPE text30,
         END OF ty_tvakt,
         BEGIN OF ty_tvfkt,
           fkart TYPE fkart,
           vtext TYPE text30,
         END OF ty_tvfkt.

  DATA: lt_raw   TYPE TABLE OF ty_raw,
        lt_tvakt TYPE HASHED TABLE OF ty_tvakt WITH UNIQUE KEY auart,
        lt_tvfkt TYPE HASHED TABLE OF ty_tvfkt WITH UNIQUE KEY fkart.

  SELECT k~auart, r~fkart, r~vkorg,
         COUNT( DISTINCT r~vbeln ) AS bill_cnt
    FROM vbrk AS r
    INNER JOIN vbrp AS p ON p~vbeln = r~vbeln
    INNER JOIN vbak AS k ON k~vbeln = p~aubel
    WHERE r~vkorg IN @s_vkorg
      AND r~fkdat IN @s_erdat
      AND k~auart IN @s_auart
    GROUP BY k~auart, r~fkart, r~vkorg
    INTO TABLE @lt_raw.

  IF lt_raw IS INITIAL.
    RETURN.
  ENDIF.

  SELECT auart, bezei
    FROM tvakt
    WHERE spras = @sy-langu
    INTO TABLE @lt_tvakt.

  SELECT fkart, vtext
    FROM tvfkt
    WHERE spras = @sy-langu
    INTO TABLE @lt_tvfkt.

  LOOP AT lt_raw INTO DATA(ls_raw).
    DATA(ls_flow) = VALUE ty_doc_flow(
      vkorg    = ls_raw-vkorg
      auart    = ls_raw-auart
      fkart    = ls_raw-fkart
      bill_cnt = ls_raw-bill_cnt ).
    READ TABLE lt_tvakt WITH TABLE KEY auart = ls_raw-auart INTO DATA(ls_ak).
    IF sy-subrc = 0. ls_flow-auart_txt = ls_ak-bezei. ENDIF.
    READ TABLE lt_tvfkt WITH TABLE KEY fkart = ls_raw-fkart INTO DATA(ls_ft).
    IF sy-subrc = 0. ls_flow-fkart_txt = ls_ft-vtext. ENDIF.
    APPEND ls_flow TO gt_doc_flow.
  ENDLOOP.

  SORT gt_doc_flow BY vkorg auart bill_cnt DESCENDING.
ENDFORM.

*----------------------------------------------------------------------*
* FORM: FETCH_ZPROG
* Inventories all Z programs using TRDIR, TRDIRT, TADIR, TSP01.
* REPOSRC scanned for noise flags and input/output patterns.
* Progress shown via SAPGUI_PROGRESS_INDICATOR.
*----------------------------------------------------------------------*
FORM fetch_zprog.
  TYPES: BEGIN OF ty_trdir_row,
           name TYPE c LENGTH 40,
           subc TYPE c LENGTH 1,
           cnam TYPE c LENGTH 12,
           cdat TYPE d,
           udat TYPE d,
         END OF ty_trdir_row,
         BEGIN OF ty_desc,
           name   TYPE c LENGTH 40,
           sprsl  TYPE c LENGTH 1,
           title  TYPE c LENGTH 60,
         END OF ty_desc,
         BEGIN OF ty_pkg,
           obj_name TYPE c LENGTH 40,
           devclass TYPE c LENGTH 30,
         END OF ty_pkg,
         BEGIN OF ty_spool,
           rqpnm     TYPE c LENGTH 40,
           last_date TYPE d,
         END OF ty_spool,
         ty_name40   TYPE c LENGTH 40,
         ty_name_set TYPE HASHED TABLE OF ty_name40
                     WITH UNIQUE KEY table_line.

  DATA: lt_trdir  TYPE TABLE OF ty_trdir_row,
        lt_desc   TYPE HASHED TABLE OF ty_desc  WITH UNIQUE KEY name,
        lt_pkg    TYPE HASHED TABLE OF ty_pkg   WITH UNIQUE KEY obj_name,
        lt_spool  TYPE HASHED TABLE OF ty_spool WITH UNIQUE KEY rqpnm,
        lt_noise  TYPE HASHED TABLE OF ty_name40 WITH UNIQUE KEY table_line,
        lt_selscr TYPE ty_name_set,
        lt_filein TYPE ty_name_set,
        lt_write  TYPE ty_name_set,
        lt_alv    TYPE ty_name_set,
        lt_xfer   TYPE ty_name_set,
        lv_has_selscr TYPE c LENGTH 1,
        lv_has_filein TYPE c LENGTH 1,
        lv_out    TYPE c LENGTH 20,
        lv_sep    TYPE c LENGTH 1,
        lv_total  TYPE i,
        lv_idx    TYPE i,
        lv_pct    TYPE i.

  " 1. Base program list
  SELECT name, subc, cnam, cdat, udat
    FROM trdir
    WHERE name LIKE 'Z%'
    INTO TABLE @lt_trdir.

  IF lt_trdir IS INITIAL.
    RETURN.
  ENDIF.

  " 2. Short descriptions — SELECT * avoids field-name validation against TRDIRT
  SELECT *
    FROM trdirt
    WHERE sprsl = @sy-langu
      AND name  LIKE 'Z%'
    INTO CORRESPONDING FIELDS OF TABLE @lt_desc.

  " 3. Package / development class
  SELECT obj_name, devclass
    FROM tadir
    WHERE pgmid    = 'R3TR'
      AND object   = 'PROG'
      AND obj_name LIKE 'Z%'
    INTO TABLE @lt_pkg.

  " 4. Last spool date per program — SELECT * avoids field-list restriction on TSP01
  SELECT *
    FROM tsp01
    WHERE rqpnm LIKE 'Z%'
    INTO TABLE @DATA(lt_tsp01_raw).

  LOOP AT lt_tsp01_raw INTO DATA(ls_tsp).
    READ TABLE lt_spool WITH TABLE KEY rqpnm = ls_tsp-rqpnm
      ASSIGNING FIELD-SYMBOL(<fs_sp>).
    IF sy-subrc = 0.
      IF ls_tsp-rqcrdat > <fs_sp>-last_date.
        <fs_sp>-last_date = ls_tsp-rqcrdat.
      ENDIF.
    ELSE.
      INSERT VALUE ty_spool( rqpnm = ls_tsp-rqpnm last_date = ls_tsp-rqcrdat )
        INTO TABLE lt_spool.
    ENDIF.
  ENDLOOP.

  " --- Noise detection ---
  " Header scan includes comment lines — '* TEST PROGRAM' is a noise signal
  IF p_noise = 'X'.
    SELECT *
      FROM reposrc
      WHERE progname LIKE 'Z%'
        AND zeile    <= 20
      INTO TABLE @DATA(lt_hdr_lines).

    LOOP AT lt_hdr_lines INTO DATA(ls_hdr).
      DATA(lv_up_src) = to_upper( ls_hdr-line ).
      IF lv_up_src CS 'TEST'    OR lv_up_src CS 'TEMP'
         OR lv_up_src CS 'TMP'  OR lv_up_src CS 'COPY'
         OR lv_up_src CS 'OLD'  OR lv_up_src CS 'BAK'
         OR lv_up_src CS 'UNUSED'    OR lv_up_src CS 'DELETE'
         OR lv_up_src CS 'WORKAROUND' OR lv_up_src CS 'DO NOT USE'.
        INSERT ls_hdr-progname INTO TABLE lt_noise.
      ENDIF.
    ENDLOOP.

    " Name pattern check
    LOOP AT lt_trdir INTO DATA(ls_nm_chk).
      DATA(lv_pnm) = to_upper( ls_nm_chk-name ).
      IF lv_pnm CS 'TEST' OR lv_pnm CS 'TEMP' OR lv_pnm CS 'TMP'
         OR lv_pnm CS 'COPY' OR lv_pnm CS 'OLD'
         OR lv_pnm CS 'BAK'  OR lv_pnm CS 'DEL'.
        INSERT ls_nm_chk-name INTO TABLE lt_noise.
      ENDIF.
    ENDLOOP.

    " Description keyword check
    LOOP AT lt_desc INTO DATA(ls_dc_chk).
      DATA(lv_dtxt) = to_upper( ls_dc_chk-title ).
      IF lv_dtxt CS 'TEST'   OR lv_dtxt CS 'TEMP'
         OR lv_dtxt CS 'COPY'    OR lv_dtxt CS 'OLD'
         OR lv_dtxt CS 'UNUSED'  OR lv_dtxt CS 'DELETE'
         OR lv_dtxt CS 'WORKAROUND'.
        INSERT ls_dc_chk-name INTO TABLE lt_noise.
      ENDIF.
    ENDLOOP.
  ENDIF.

  " --- Input/Output detection (comment lines excluded, single REPOSRC pass) ---
  SELECT *
    FROM reposrc
    WHERE progname LIKE 'Z%'
      AND line NOT LIKE '*%'
      AND line NOT LIKE '"%'
    INTO TABLE @DATA(lt_exec_lines).

  LOOP AT lt_exec_lines INTO DATA(ls_exec).
    IF ls_exec-line CS 'PARAMETERS' OR ls_exec-line CS 'SELECT-OPTIONS'
       OR ls_exec-line CS 'SELECTION-SCREEN'.
      INSERT ls_exec-progname INTO TABLE lt_selscr.
    ENDIF.
    IF ls_exec-line CS 'READ DATASET'.
      INSERT ls_exec-progname INTO TABLE lt_filein.
    ENDIF.
    IF ls_exec-line CS 'WRITE'.
      INSERT ls_exec-progname INTO TABLE lt_write.
    ENDIF.
    IF ls_exec-line CS 'CL_SALV_TABLE' OR ls_exec-line CS 'REUSE_ALV'.
      INSERT ls_exec-progname INTO TABLE lt_alv.
    ENDIF.
    IF ls_exec-line CS 'TRANSFER'.
      INSERT ls_exec-progname INTO TABLE lt_xfer.
    ENDIF.
  ENDLOOP.

  " --- Assembly loop ---
  lv_total = lines( lt_trdir ).
  lv_idx   = 0.

  LOOP AT lt_trdir INTO DATA(ls_prog).
    lv_idx = lv_idx + 1.
    lv_pct = ( lv_idx * 100 ) / lv_total.

    CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
      EXPORTING
        percentage = lv_pct
        text       = |Analyzing program { lv_idx } of { lv_total }...|.

    " Skip noise programs when filter is active
    IF p_noise = 'X'.
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

    READ TABLE lt_desc  WITH TABLE KEY name     = ls_prog-name INTO DATA(ls_d).
    IF sy-subrc = 0. ls_row-prog_txt   = ls_d-title.     ENDIF.

    READ TABLE lt_pkg   WITH TABLE KEY obj_name = ls_prog-name INTO DATA(ls_p).
    IF sy-subrc = 0. ls_row-devclass   = ls_p-devclass.  ENDIF.

    READ TABLE lt_spool WITH TABLE KEY rqpnm    = ls_prog-name INTO DATA(ls_sp).
    IF sy-subrc = 0. ls_row-last_spool = ls_sp-last_date. ENDIF.

    " Input type
    lv_has_selscr = ''.
    lv_has_filein = ''.
    READ TABLE lt_selscr WITH TABLE KEY table_line = ls_prog-name
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0. lv_has_selscr = 'X'. ENDIF.
    READ TABLE lt_filein WITH TABLE KEY table_line = ls_prog-name
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0. lv_has_filein = 'X'. ENDIF.

    IF lv_has_selscr = 'X' AND lv_has_filein = 'X'.
      ls_row-input_type = 'Sel.Screen+File'.
    ELSEIF lv_has_selscr = 'X'.
      ls_row-input_type = 'Sel.Screen'.
    ELSEIF lv_has_filein = 'X'.
      ls_row-input_type = 'File'.
    ENDIF.

    " Output type — build concatenated label
    lv_out = ''.
    lv_sep = ''.
    READ TABLE lt_write WITH TABLE KEY table_line = ls_prog-name
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      lv_out = |{ lv_out }{ lv_sep }Print|.  lv_sep = '+'.
    ENDIF.
    READ TABLE lt_alv WITH TABLE KEY table_line = ls_prog-name
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      lv_out = |{ lv_out }{ lv_sep }ALV|.    lv_sep = '+'.
    ENDIF.
    READ TABLE lt_xfer WITH TABLE KEY table_line = ls_prog-name
      TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      lv_out = |{ lv_out }{ lv_sep }File|.
    ENDIF.
    ls_row-output_type = lv_out.

    APPEND ls_row TO gt_zprog.
  ENDLOOP.

  SORT gt_zprog BY devclass progname.
ENDFORM.

*----------------------------------------------------------------------*
* FORM: DISPLAY_ALV
* Displays the data table that matches the selected radio button using
* CL_SALV_TABLE (object-oriented ALV). Auto-builds the field catalog
* from the table's structure — no manual fcat needed. No screen, no
* container, no tabstrip: works on any 7.40+ system out of the box.
*----------------------------------------------------------------------*
FORM display_alv.
  DATA: lo_alv   TYPE REF TO cl_salv_table,
        lv_title TYPE lvc_title.

  TRY.
      CASE 'X'.
        WHEN r_order.
          lv_title = 'Order Document Types'.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_alv
            CHANGING  t_table      = gt_vbak_types ).

        WHEN r_itmcat.
          lv_title = 'Item Categories'.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_alv
            CHANGING  t_table      = gt_item_cat ).

        WHEN r_biltyp.
          lv_title = 'Billing Document Types'.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_alv
            CHANGING  t_table      = gt_bill_types ).

        WHEN r_output.
          lv_title = 'Output Condition Records'.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_alv
            CHANGING  t_table      = gt_output ).

        WHEN r_trans.
          lv_title = 'Transactional Summary'.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_alv
            CHANGING  t_table      = gt_trans_summary ).

        WHEN r_dflow.
          lv_title = 'Order to Invoice Document Flow'.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_alv
            CHANGING  t_table      = gt_doc_flow ).

        WHEN r_zprog.
          lv_title = 'Z Program Inventory'.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_alv
            CHANGING  t_table      = gt_zprog ).
      ENDCASE.

      lo_alv->get_display_settings( )->set_list_header( lv_title ).
      lo_alv->get_columns( )->set_optimize( abap_true ).
      lo_alv->get_functions( )->set_all( ).
      lo_alv->display( ).

    CATCH cx_salv_msg INTO DATA(lx_salv).
      MESSAGE lx_salv->get_text( ) TYPE 'I'.
  ENDTRY.
ENDFORM.
