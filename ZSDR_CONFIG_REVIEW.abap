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
*&   6. Billing Volume         - Billing doc count by billing type
*&                               and sales area from VBRK GROUP BY
*&                               — no VBRP/VBAK join
*&
*& Inputs
*&   s_vkorg  - sales org filter (Distribution Channel and Division
*&              are hardcoded to '01' — always constant in this system)
*&   s_auart  - order-type filter
*&   s_erdat  - date range (default: last 365 days)
*&
*& Tables read (READ-ONLY; no UPDATE / INSERT / MODIFY / DELETE /
*& COMMIT against any database table — internal-table DELETE
*& ADJACENT DUPLICATES is the only DELETE in the program):
*&   Config:  TVAK, TVAKT, T184, TVAPT, TVFK, TVFKT
*&   Trans:   VBAK, VBRK, NACH
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
    vtext     TYPE text30,
    count     TYPE i,
  END OF ty_bill_types,

  " --- Output / NACE ---
  BEGIN OF ty_output,
    kappl     TYPE kappl,
    appl_txt  TYPE c LENGTH 20,
    kschl     TYPE kschl,
    count     TYPE i,
  END OF ty_output,

  " --- Transactional Summary ---
  BEGIN OF ty_trans_summary,
    auart   TYPE auart,
    vkorg   TYPE vkorg,
    ord_cnt TYPE i,
    net_val TYPE netwr,
  END OF ty_trans_summary,

  " --- Billing Volume ---
  BEGIN OF ty_doc_flow,
    fkart     TYPE fkart,
    fkart_txt TYPE text30,
    vkorg     TYPE vkorg,
    bill_cnt  TYPE i,
  END OF ty_doc_flow.

*----------------------------------------------------------------------*
* INTERNAL TABLES
*----------------------------------------------------------------------*
DATA:
  gt_vbak_types    TYPE TABLE OF ty_vbak_types,
  gt_item_cat      TYPE TABLE OF ty_item_cat,
  gt_bill_types    TYPE TABLE OF ty_bill_types,
  gt_output        TYPE TABLE OF ty_output,
  gt_trans_summary TYPE TABLE OF ty_trans_summary,
  gt_doc_flow      TYPE TABLE OF ty_doc_flow.

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
*   R_DFLOW   "Billing Volume by Type"
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
              r_dflow  RADIOBUTTON GROUP r1.
SELECTION-SCREEN END OF BLOCK b3.

*----------------------------------------------------------------------*
* INITIALIZATION
*----------------------------------------------------------------------*
INITIALIZATION.
  s_erdat-sign   = 'I'.
  s_erdat-option = 'BT'.
  s_erdat-low    = sy-datum - 365.
  s_erdat-high   = sy-datum.
  APPEND s_erdat TO s_erdat[].

*----------------------------------------------------------------------*
* SELECTION SCREEN VALIDATION
*----------------------------------------------------------------------*
AT SELECTION-SCREEN.
  IF s_erdat[] IS INITIAL AND
     ( r_biltyp = abap_true OR r_trans = abap_true OR r_dflow = abap_true ).
    MESSAGE w398(00) WITH 'No date range — this view may run long on large systems'.
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
  TYPES: BEGIN OF ty_fkart_cnt,
           fkart TYPE fkart,
           cnt   TYPE i,
         END OF ty_fkart_cnt.

  DATA: lt_tvfk      TYPE TABLE OF ty_bill_types,
        lt_fkart_cnt TYPE HASHED TABLE OF ty_fkart_cnt
                     WITH UNIQUE KEY fkart.

  SELECT a~fkart, t~vtext
    FROM tvfk AS a
    LEFT OUTER JOIN tvfkt AS t
      ON t~fkart = a~fkart
     AND t~spras = @sy-langu
    INTO CORRESPONDING FIELDS OF TABLE @lt_tvfk.

  SELECT fkart, COUNT(*) AS cnt
    FROM vbrk
    WHERE vkorg IN @s_vkorg
      AND vtweg = '01'
      AND spart = '01'
    GROUP BY fkart
    INTO TABLE @lt_fkart_cnt.

  LOOP AT lt_tvfk INTO DATA(ls_tvfk).
    READ TABLE lt_fkart_cnt WITH TABLE KEY fkart = ls_tvfk-fkart
      INTO DATA(ls_cnt).
    ls_tvfk-count = COND #( WHEN sy-subrc = 0 THEN ls_cnt-cnt ELSE 0 ).
    APPEND ls_tvfk TO gt_bill_types.
  ENDLOOP.

  SORT gt_bill_types BY count DESCENDING.
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
           cnt   TYPE i,
         END OF ty_nach_raw.

  DATA lt_raw TYPE TABLE OF ty_nach_raw.

  SELECT kappl, kschl, COUNT(*) AS cnt
    FROM nach
    WHERE kappl IN ( 'V1', 'V2', 'V3' )
    GROUP BY kappl, kschl
    INTO TABLE @lt_raw.

  LOOP AT lt_raw INTO DATA(ls_raw).
    APPEND VALUE ty_output(
      kappl    = ls_raw-kappl
      kschl    = ls_raw-kschl
      count    = ls_raw-cnt
      appl_txt = SWITCH #( ls_raw-kappl
        WHEN 'V1' THEN 'Sales'
        WHEN 'V2' THEN 'Shipping'
        WHEN 'V3' THEN 'Billing' ) ) TO gt_output.
  ENDLOOP.

  SORT gt_output BY kappl kschl count DESCENDING.
ENDFORM.

*----------------------------------------------------------------------*
* FORM: FETCH_TRANSACTIONAL_SUMMARY
* Order count and net order value by order type and sales area,
* aggregated across the full selected date range. One row per
* (auart, vkorg) — use s_erdat to scope the period.
*----------------------------------------------------------------------*
FORM fetch_transactional_summary.
  SELECT auart, vkorg,
         COUNT(*) AS ord_cnt,
         SUM( netwr ) AS net_val
    FROM vbak
    WHERE vkorg IN @s_vkorg
      AND vtweg = '01'
      AND spart = '01'
      AND auart IN @s_auart
      AND erdat IN @s_erdat
    GROUP BY auart, vkorg
    INTO CORRESPONDING FIELDS OF TABLE @gt_trans_summary.

  SORT gt_trans_summary BY vkorg ord_cnt DESCENDING.
ENDFORM.

*----------------------------------------------------------------------*
* FORM: FETCH_DOC_FLOW
* Billing volume by billing type and sales area.
* Pure VBRK GROUP BY + TVFKT description lookup — no VBRP/VBAK join,
* uses VKORG index, returns quickly on any data volume.
*----------------------------------------------------------------------*
FORM fetch_doc_flow.
  TYPES: BEGIN OF ty_fkart_cnt,
           fkart TYPE fkart,
           vkorg TYPE vkorg,
           cnt   TYPE i,
         END OF ty_fkart_cnt.

  DATA: lt_raw   TYPE TABLE OF ty_fkart_cnt,
        lt_tvfkt TYPE HASHED TABLE OF ty_bill_types WITH UNIQUE KEY fkart.

  SELECT fkart, vkorg, COUNT(*) AS cnt
    FROM vbrk
    WHERE vkorg IN @s_vkorg
      AND vtweg = '01'
      AND spart = '01'
      AND fkdat IN @s_erdat
    GROUP BY fkart, vkorg
    INTO TABLE @lt_raw.

  IF lt_raw IS INITIAL.
    RETURN.
  ENDIF.

  SELECT fkart, vtext
    FROM tvfkt
    WHERE spras = @sy-langu
    INTO CORRESPONDING FIELDS OF TABLE @lt_tvfkt.

  LOOP AT lt_raw INTO DATA(ls_raw).
    DATA(ls_flow) = VALUE ty_doc_flow(
      fkart    = ls_raw-fkart
      vkorg    = ls_raw-vkorg
      bill_cnt = ls_raw-cnt ).
    READ TABLE lt_tvfkt WITH TABLE KEY fkart = ls_raw-fkart
      INTO DATA(ls_ft).
    IF sy-subrc = 0. ls_flow-fkart_txt = ls_ft-vtext. ENDIF.
    APPEND ls_flow TO gt_doc_flow.
  ENDLOOP.

  SORT gt_doc_flow BY fkart vkorg.
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
          lv_title = 'Billing Volume by Type and Sales Area'.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_alv
            CHANGING  t_table      = gt_doc_flow ).
      ENDCASE.

      lo_alv->get_display_settings( )->set_list_header( lv_title ).
      lo_alv->get_columns( )->set_optimize( abap_true ).
      lo_alv->get_functions( )->set_all( ).
      lo_alv->display( ).

    CATCH cx_salv_msg INTO DATA(lx_salv).
      MESSAGE lx_salv->get_text( ) TYPE 'I'.
  ENDTRY.
ENDFORM.
