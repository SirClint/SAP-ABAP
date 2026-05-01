*&---------------------------------------------------------------------*
*& Report  ZSD_CONFIG_REVIEW
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
*&   5. Output Cond Types      - T685A condition type config (V1/V2/V3)
*&   6. Transactional Summary  - per (auart, vkorg, vtweg, date):
*&                               order count, net value, and invoice
*&                               count derived via VBRK->VBRP->VBAK
*&
*& Inputs
*&   s_vkorg / s_vtweg / s_spart  - sales area selection
*&   s_auart                       - order-type filter
*&   s_erdat                       - date range (default sy-datum)
*&   p_maxrec                      - VBAK row cap (default 5000)
*&
*& Tables read (READ-ONLY; no UPDATE / INSERT / MODIFY / DELETE /
*& COMMIT against any database table — internal-table DELETE
*& ADJACENT DUPLICATES is the only DELETE in the program):
*&   Config:  TVAK, TVAKT, T184, TVAPT, TVFK, TVFKT, T685A
*&   Trans:   VBAK, VBRK, VBRP, NACH
*&
*& Output
*&   Object-oriented ALV display via CL_SALV_TABLE. The selection
*&   screen offers eight radio buttons; one report run shows one
*&   view. Re-run the report to switch views. No spool, no file
*&   output, no remote calls.
*&
*& Compatibility
*&   Requires SAP_BASIS 7.40 SP05 or higher (uses VALUE / COND /
*&   inline DATA / strict Open SQL). Verified on 7.50 SP14.
*&---------------------------------------------------------------------*
REPORT zsd_config_review.

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
    kschl     TYPE kschl,
    count     TYPE i,
  END OF ty_output,

  BEGIN OF ty_nace_access,
    kappl     TYPE kappl,
    kschl     TYPE kschl,
  END OF ty_nace_access,

  " --- Transactional Summary ---
  BEGIN OF ty_trans_summary,
    auart     TYPE auart,
    vkorg     TYPE vkorg,
    vtweg     TYPE vtweg,
    erdat     TYPE erdat,
    order_cnt TYPE i,
    bill_cnt  TYPE i,
    net_val   TYPE netwr,
  END OF ty_trans_summary.

*----------------------------------------------------------------------*
* INTERNAL TABLES
*----------------------------------------------------------------------*
DATA:
  gt_vbak_types    TYPE TABLE OF ty_vbak_types,
  gt_item_cat      TYPE TABLE OF ty_item_cat,
  gt_bill_types    TYPE TABLE OF ty_bill_types,
  gt_output        TYPE TABLE OF ty_output,
  gt_nace_access   TYPE TABLE OF ty_nace_access,
  gt_trans_summary TYPE TABLE OF ty_trans_summary.

*----------------------------------------------------------------------*
* SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  SELECT-OPTIONS: s_vkorg FOR vbak-vkorg,
                  s_vtweg FOR vbak-vtweg,
                  s_spart FOR vbak-spart,
                  s_auart FOR vbak-auart,
                  s_erdat FOR vbak-erdat DEFAULT sy-datum.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
  PARAMETERS: p_maxrec TYPE i DEFAULT 5000 OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE TEXT-003.
  PARAMETERS: r_ord  RADIOBUTTON GROUP r1 DEFAULT 'X',
              r_itm  RADIOBUTTON GROUP r1,
              r_bil  RADIOBUTTON GROUP r1,
              r_out  RADIOBUTTON GROUP r1,
              r_t685 RADIOBUTTON GROUP r1,
              r_trn  RADIOBUTTON GROUP r1.
SELECTION-SCREEN END OF BLOCK b3.

*----------------------------------------------------------------------*
* INITIALIZATION
*----------------------------------------------------------------------*
INITIALIZATION.
  TEXT-001 = 'Selection Criteria'.
  TEXT-002 = 'Performance'.
  TEXT-003 = 'View (pick one)'.

*----------------------------------------------------------------------*
* SELECTION SCREEN VALIDATION
*----------------------------------------------------------------------*
AT SELECTION-SCREEN.
  IF p_maxrec <= 0.
    MESSAGE e398(00) WITH 'Max records must be greater than zero'.
  ENDIF.

*----------------------------------------------------------------------*
* START OF SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.
  CASE 'X'.
    WHEN r_ord.  PERFORM fetch_sd_order_types.
    WHEN r_itm.  PERFORM fetch_item_categories.
    WHEN r_bil.  PERFORM fetch_billing_types.
    WHEN r_out.  PERFORM fetch_nace_output.
    WHEN r_t685. PERFORM fetch_nace_access.
    WHEN r_trn.  PERFORM fetch_transactional_summary.
  ENDCASE.

END-OF-SELECTION.
  PERFORM display_alv.

*----------------------------------------------------------------------*
* FORM: FETCH_SD_ORDER_TYPES
* Reads sales document type config from TVAK.
* Order counts fetched in a single GROUP BY query — no SELECT in loop.
*----------------------------------------------------------------------*
FORM fetch_sd_order_types.
  TYPES: BEGIN OF ty_auart_cnt,
           auart TYPE auart,
           cnt   TYPE i,
         END OF ty_auart_cnt.

  DATA: lt_tvak      TYPE TABLE OF ty_vbak_types,
        lt_auart_cnt TYPE HASHED TABLE OF ty_auart_cnt
                     WITH UNIQUE KEY auart.

  SELECT a~auart, t~bezei
    FROM tvak AS a
    LEFT OUTER JOIN tvakt AS t
      ON t~auart = a~auart
     AND t~spras = @sy-langu
    INTO CORRESPONDING FIELDS OF TABLE @lt_tvak.

  SELECT auart, COUNT(*) AS cnt
    FROM vbak
    WHERE vkorg IN @s_vkorg
      AND vtweg IN @s_vtweg
      AND spart IN @s_spart
      AND erdat IN @s_erdat
    GROUP BY auart
    INTO TABLE @lt_auart_cnt.

  LOOP AT lt_tvak INTO DATA(ls_tvak).
    READ TABLE lt_auart_cnt WITH TABLE KEY auart = ls_tvak-auart
      INTO DATA(ls_cnt).
    ls_tvak-count = COND #( WHEN sy-subrc = 0 THEN ls_cnt-cnt ELSE 0 ).
    APPEND ls_tvak TO gt_vbak_types.
  ENDLOOP.

  SORT gt_vbak_types BY count DESCENDING.
ENDFORM.

*----------------------------------------------------------------------*
* FORM: FETCH_ITEM_CATEGORIES
* Reads item category config using a JOIN — eliminates SELECT in loop.
*----------------------------------------------------------------------*
FORM fetch_item_categories.
  SELECT DISTINCT a~auart, a~pstyv, b~vtext
    FROM t184 AS a
    LEFT OUTER JOIN tvapt AS b
      ON b~pstyv = a~pstyv
     AND b~spras = @sy-langu
    WHERE a~auart IN @s_auart
    INTO TABLE @gt_item_cat.

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
      AND vtweg IN @s_vtweg
      AND spart IN @s_spart
      AND fkdat IN @s_erdat
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
  SELECT kappl, kschl, COUNT(*) AS count
    FROM nach
    WHERE kappl IN ( 'V1', 'V2', 'V3' )
    GROUP BY kappl, kschl
    INTO TABLE @gt_output.

  SORT gt_output BY kappl kschl count DESCENDING.
ENDFORM.

*----------------------------------------------------------------------*
* FORM: FETCH_NACE_ACCESS
* Reads output condition type config from T685A
*----------------------------------------------------------------------*
FORM fetch_nace_access.
  SELECT DISTINCT kappl, kschl
    FROM t685a
    WHERE kappl IN ( 'V1', 'V2', 'V3' )
    INTO TABLE @gt_nace_access.

  SORT gt_nace_access BY kappl kschl.
ENDFORM.

*----------------------------------------------------------------------*
* FORM: FETCH_TRANSACTIONAL_SUMMARY
* Summarizes orders and billing by (auart, sales area, date).
* Order side: aggregated from VBAK via COLLECT into a HASHED accumulator
* — O(n) instead of the previous O(n^2) READ TABLE in a loop.
* Billing side: counts derived by joining VBRK -> VBRP -> VBAK so that
* each invoice is attributed to its source order's auart, then GROUP BY
* on the database for a single row per (auart, vkorg, vtweg, fkdat) —
* fixes the previous wrong match that ignored auart entirely.
*----------------------------------------------------------------------*
FORM fetch_transactional_summary.
  TYPES: BEGIN OF ty_bill_cnt,
           auart TYPE auart,
           vkorg TYPE vkorg,
           vtweg TYPE vtweg,
           fkdat TYPE fkdat,
           cnt   TYPE i,
         END OF ty_bill_cnt.

  DATA: lt_vbak     TYPE TABLE OF vbak,
        lt_bill_cnt TYPE TABLE OF ty_bill_cnt,
        lt_acc      TYPE HASHED TABLE OF ty_trans_summary
                    WITH UNIQUE KEY auart vkorg vtweg erdat.

  SELECT vbeln, auart, vkorg, vtweg, erdat, netwr
    FROM vbak
    WHERE vkorg IN @s_vkorg
      AND vtweg IN @s_vtweg
      AND spart IN @s_spart
      AND auart IN @s_auart
      AND erdat IN @s_erdat
    UP TO @p_maxrec ROWS
    INTO CORRESPONDING FIELDS OF TABLE @lt_vbak.

  LOOP AT lt_vbak INTO DATA(ls_vbak).
    COLLECT VALUE ty_trans_summary(
      auart     = ls_vbak-auart
      vkorg     = ls_vbak-vkorg
      vtweg     = ls_vbak-vtweg
      erdat     = ls_vbak-erdat
      order_cnt = 1
      net_val   = ls_vbak-netwr ) INTO lt_acc.
  ENDLOOP.

  " Billings attributed to source order's auart via VBRP/VBAK
  SELECT k~auart,
         b~vkorg,
         b~vtweg,
         b~fkdat,
         COUNT( DISTINCT b~vbeln ) AS cnt
    FROM vbrk AS b
    INNER JOIN vbrp AS p ON p~vbeln = b~vbeln
    INNER JOIN vbak AS k ON k~vbeln = p~aubel
    INTO TABLE @lt_bill_cnt
    WHERE b~vkorg IN @s_vkorg
      AND b~vtweg IN @s_vtweg
      AND b~spart IN @s_spart
      AND b~fkdat IN @s_erdat
      AND k~auart IN @s_auart
    GROUP BY k~auart, b~vkorg, b~vtweg, b~fkdat.

  LOOP AT lt_bill_cnt INTO DATA(ls_bc).
    COLLECT VALUE ty_trans_summary(
      auart    = ls_bc-auart
      vkorg    = ls_bc-vkorg
      vtweg    = ls_bc-vtweg
      erdat    = ls_bc-fkdat
      bill_cnt = ls_bc-cnt ) INTO lt_acc.
  ENDLOOP.

  gt_trans_summary = lt_acc.
  SORT gt_trans_summary BY vkorg vtweg erdat DESCENDING.
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
        WHEN r_ord.
          lv_title = 'Order Document Types'.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_alv
            CHANGING  t_table      = gt_vbak_types ).

        WHEN r_itm.
          lv_title = 'Item Categories'.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_alv
            CHANGING  t_table      = gt_item_cat ).

        WHEN r_bil.
          lv_title = 'Billing Document Types'.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_alv
            CHANGING  t_table      = gt_bill_types ).

        WHEN r_out.
          lv_title = 'Output Condition Records'.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_alv
            CHANGING  t_table      = gt_output ).

        WHEN r_t685.
          lv_title = 'Output Condition Types'.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_alv
            CHANGING  t_table      = gt_nace_access ).

        WHEN r_trn.
          lv_title = 'Transactional Summary'.
          cl_salv_table=>factory(
            IMPORTING r_salv_table = lo_alv
            CHANGING  t_table      = gt_trans_summary ).
      ENDCASE.

      lo_alv->get_display_settings( )->set_list_header( lv_title ).
      lo_alv->get_columns( )->set_optimize( abap_true ).
      lo_alv->get_functions( )->set_all( ).
      lo_alv->display( ).

    CATCH cx_salv_msg INTO DATA(lx_salv).
      MESSAGE lx_salv->get_text( ) TYPE 'I'.
  ENDTRY.
ENDFORM.
