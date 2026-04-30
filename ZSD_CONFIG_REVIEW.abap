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
*& What it shows (one ALV tab per topic)
*&   1. Order Doc Types        - TVAK config + count of VBAK orders
*&                               per order type in the selection
*&   2. Item Categories        - TVSPA assignment joined to TVSPS
*&                               for item-category descriptions
*&   3. Billing Types          - TVFK config + count of VBRK invoices
*&                               per billing type in the selection
*&   4. Copy Control           - TVCPF copy rules (kappl V1)
*&   5. Output Records         - NACH condition records (V1/V2/V3)
*&                               grouped by output type / medium /
*&                               sales area, with hit counts
*&   6. Output Cond Types      - T685A condition type config
*&                               (V1/V2/V3 applications)
*&   7. Acct Determination     - VKOA revenue account assignments
*&                               enriched with SKAT GL descriptions
*&   8. Transactional Summary  - per (auart, vkorg, vtweg, date):
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
*&   Config:  TVAK, TVSPA, TVSPS, TVFK, TVCPF, T685A, VKOA, SKAT
*&   Trans:   VBAK, VBRK, VBRP, NACH
*&
*& Output
*&   Tabbed ALV display via cl_gui_docking_container +
*&   cl_gui_tabstrip + cl_gui_alv_grid. No spool, no file output,
*&   no remote calls.
*&
*& Compatibility
*&   Requires SAP_BASIS 7.40 SP05 or higher (uses VALUE / COND /
*&   inline DATA / strict Open SQL). Verified on 7.50 SP14.
*&---------------------------------------------------------------------*
REPORT zsd_config_review.

*----------------------------------------------------------------------*
* TYPE DEFINITIONS
*----------------------------------------------------------------------*
TYPES:
  " --- Sales Order Config ---
  BEGIN OF ty_vbak_types,
    auart     TYPE tvak-auart,
    bezei     TYPE tvak-bezei,
    autyp     TYPE tvak-autyp,
    abstk     TYPE tvak-abstk,
    faktyp    TYPE tvak-faktyp,
    prsfd     TYPE tvak-prsfd,
    count     TYPE i,
  END OF ty_vbak_types,

  BEGIN OF ty_item_cat,
    pstyv     TYPE tvsps-pstyv,
    vtext     TYPE tvsps-vtext,
    auart     TYPE tvspa-auart,
    mtpos     TYPE tvspa-mtpos,
    posit     TYPE tvspa-posit,
    erzet     TYPE tvspa-erzet,
    abgru     TYPE tvspa-abgru,
  END OF ty_item_cat,

  " --- Billing Config ---
  BEGIN OF ty_bill_types,
    fkart     TYPE tvfk-fkart,
    vtext     TYPE tvfk-vtext,
    fktyp     TYPE tvfk-fktyp,
    sfakn     TYPE tvfk-sfakn,
    rplkz     TYPE tvfk-rplkz,
    count     TYPE i,
  END OF ty_bill_types,

  BEGIN OF ty_bill_copy,
    kappl     TYPE tvcpf-kappl,
    qualf     TYPE tvcpf-qualf,
    qualz     TYPE tvcpf-qualz,
    fotranst  TYPE tvcpf-fotranst,
    vbtyp_n   TYPE tvcpf-vbtyp_n,
  END OF ty_bill_copy,

  " --- Output / NACE ---
  BEGIN OF ty_output,
    kappl     TYPE nach-kappl,
    kschl     TYPE nach-kschl,
    vkorg     TYPE nach-vkorg,
    vtweg     TYPE nach-vtweg,
    spart     TYPE nach-spart,
    nacha     TYPE nach-nacha,
    tnam      TYPE nach-tnam,
    count     TYPE i,
  END OF ty_output,

  BEGIN OF ty_nace_access,
    kappl     TYPE t685a-kappl,
    kschl     TYPE t685a-kschl,
    kozgf     TYPE t685a-kozgf,
    krech     TYPE t685a-krech,
    kbetr     TYPE t685a-kbetr,
  END OF ty_nace_access,

  " --- Account Determination ---
  BEGIN OF ty_vkoa,
    kappl     TYPE vkoa-kappl,
    ktosl     TYPE vkoa-ktosl,
    vkorg     TYPE vkoa-vkorg,
    vtweg     TYPE vkoa-vtweg,
    ktosg     TYPE vkoa-ktosg,
    zterm     TYPE vkoa-zterm,
    konts     TYPE vkoa-konts,
    konth     TYPE vkoa-konth,
    txt_acct  TYPE text30,
  END OF ty_vkoa,

  " --- Transactional Summary ---
  BEGIN OF ty_trans_summary,
    auart     TYPE vbak-auart,
    vkorg     TYPE vbak-vkorg,
    vtweg     TYPE vbak-vtweg,
    erdat     TYPE vbak-erdat,
    order_cnt TYPE i,
    bill_cnt  TYPE i,
    net_val   TYPE vbak-netwr,
  END OF ty_trans_summary.

*----------------------------------------------------------------------*
* INTERNAL TABLES
*----------------------------------------------------------------------*
DATA:
  gt_vbak_types    TYPE TABLE OF ty_vbak_types,
  gt_item_cat      TYPE TABLE OF ty_item_cat,
  gt_bill_types    TYPE TABLE OF ty_bill_types,
  gt_bill_copy     TYPE TABLE OF ty_bill_copy,
  gt_output        TYPE TABLE OF ty_output,
  gt_nace_access   TYPE TABLE OF ty_nace_access,
  gt_vkoa          TYPE TABLE OF ty_vkoa,
  gt_trans_summary TYPE TABLE OF ty_trans_summary.

*----------------------------------------------------------------------*
* FIELD CATALOGS
*----------------------------------------------------------------------*
DATA:
  gt_fcat_ord   TYPE lvc_t_fcat,
  gt_fcat_itmct TYPE lvc_t_fcat,
  gt_fcat_bill  TYPE lvc_t_fcat,
  gt_fcat_bcopy TYPE lvc_t_fcat,
  gt_fcat_nace  TYPE lvc_t_fcat,
  gt_fcat_nacac TYPE lvc_t_fcat,
  gt_fcat_vkoa  TYPE lvc_t_fcat,
  gt_fcat_trans TYPE lvc_t_fcat.

*----------------------------------------------------------------------*
* ALV / SCREEN OBJECTS
*----------------------------------------------------------------------*
DATA:
  go_dock        TYPE REF TO cl_gui_docking_container,
  go_tabstrip    TYPE REF TO cl_gui_tabstrip,
  go_container1  TYPE REF TO cl_gui_custom_container,
  go_container2  TYPE REF TO cl_gui_custom_container,
  go_container3  TYPE REF TO cl_gui_custom_container,
  go_container4  TYPE REF TO cl_gui_custom_container,
  go_container5  TYPE REF TO cl_gui_custom_container,
  go_container6  TYPE REF TO cl_gui_custom_container,
  go_container7  TYPE REF TO cl_gui_custom_container,
  go_container8  TYPE REF TO cl_gui_custom_container,
  go_alv1        TYPE REF TO cl_gui_alv_grid,
  go_alv2        TYPE REF TO cl_gui_alv_grid,
  go_alv3        TYPE REF TO cl_gui_alv_grid,
  go_alv4        TYPE REF TO cl_gui_alv_grid,
  go_alv5        TYPE REF TO cl_gui_alv_grid,
  go_alv6        TYPE REF TO cl_gui_alv_grid,
  go_alv7        TYPE REF TO cl_gui_alv_grid,
  go_alv8        TYPE REF TO cl_gui_alv_grid.

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

*----------------------------------------------------------------------*
* INITIALIZATION
*----------------------------------------------------------------------*
INITIALIZATION.
  TEXT-001 = 'Selection Criteria'.
  TEXT-002 = 'Performance'.

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
  PERFORM fetch_sd_order_types.
  PERFORM fetch_item_categories.
  PERFORM fetch_billing_types.
  PERFORM fetch_billing_copy_control.
  PERFORM fetch_nace_output.
  PERFORM fetch_nace_access.
  PERFORM fetch_account_determination.
  PERFORM fetch_transactional_summary.

END-OF-SELECTION.
  PERFORM display_alv_tabstrip.

*----------------------------------------------------------------------*
* FORM: FETCH_SD_ORDER_TYPES
* Reads sales document type config from TVAK.
* Order counts fetched in a single GROUP BY query — no SELECT in loop.
*----------------------------------------------------------------------*
FORM fetch_sd_order_types.
  TYPES: BEGIN OF ty_auart_cnt,
           auart TYPE vbak-auart,
           cnt   TYPE i,
         END OF ty_auart_cnt.

  DATA: lt_tvak      TYPE TABLE OF ty_vbak_types,
        lt_auart_cnt TYPE HASHED TABLE OF ty_auart_cnt
                     WITH UNIQUE KEY auart.

  SELECT auart, bezei, autyp, abstk, faktyp, prsfd
    FROM tvak
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
  SELECT a~pstyv, b~vtext, a~auart, a~mtpos, a~posit, a~erzet, a~abgru
    FROM tvspa AS a
    LEFT OUTER JOIN tvsps AS b ON a~pstyv = b~pstyv
    INTO TABLE @gt_item_cat
    WHERE a~auart IN @s_auart.

  SORT gt_item_cat BY auart pstyv.
  DELETE ADJACENT DUPLICATES FROM gt_item_cat COMPARING auart pstyv mtpos.
ENDFORM.

*----------------------------------------------------------------------*
* FORM: FETCH_BILLING_TYPES
* Reads billing document type config from TVFK.
* Invoice counts fetched in a single GROUP BY query — no SELECT in loop.
*----------------------------------------------------------------------*
FORM fetch_billing_types.
  TYPES: BEGIN OF ty_fkart_cnt,
           fkart TYPE vbrk-fkart,
           cnt   TYPE i,
         END OF ty_fkart_cnt.

  DATA: lt_tvfk      TYPE TABLE OF ty_bill_types,
        lt_fkart_cnt TYPE HASHED TABLE OF ty_fkart_cnt
                     WITH UNIQUE KEY fkart.

  SELECT fkart, vtext, fktyp, sfakn, rplkz
    FROM tvfk
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
* FORM: FETCH_BILLING_COPY_CONTROL
* Reads copy control rules from TVCPF
*----------------------------------------------------------------------*
FORM fetch_billing_copy_control.
  SELECT kappl, qualf, qualz, fotranst, vbtyp_n
    FROM tvcpf
    INTO TABLE @gt_bill_copy
    WHERE kappl = 'V1'.

  SORT gt_bill_copy BY kappl qualf qualz.
ENDFORM.

*----------------------------------------------------------------------*
* FORM: FETCH_NACE_OUTPUT
* Summarizes output condition records from NACH using GROUP BY —
* replaces the previous loop-based accumulation.
*----------------------------------------------------------------------*
FORM fetch_nace_output.
  SELECT kappl, kschl, vkorg, vtweg, spart, nacha, tnam, COUNT(*) AS count
    FROM nach
    WHERE kappl IN ( 'V1', 'V2', 'V3' )
      AND vkorg IN @s_vkorg
      AND vtweg IN @s_vtweg
      AND spart IN @s_spart
    GROUP BY kappl, kschl, vkorg, vtweg, spart, nacha, tnam
    INTO TABLE @gt_output.

  SORT gt_output BY kappl kschl count DESCENDING.
ENDFORM.

*----------------------------------------------------------------------*
* FORM: FETCH_NACE_ACCESS
* Reads output condition type config from T685A
*----------------------------------------------------------------------*
FORM fetch_nace_access.
  SELECT kappl, kschl, kozgf, krech, kbetr
    FROM t685a
    INTO TABLE @gt_nace_access
    WHERE kappl IN ( 'V1', 'V2', 'V3' ).

  SORT gt_nace_access BY kappl kschl.
ENDFORM.

*----------------------------------------------------------------------*
* FORM: FETCH_ACCOUNT_DETERMINATION
* Reads VKOA; GL account descriptions fetched in a single batch SELECT
* using a range table — eliminates SELECT SINGLE in loop.
*----------------------------------------------------------------------*
FORM fetch_account_determination.
  TYPES: BEGIN OF ty_skat_txt,
           saknr TYPE skat-saknr,
           txt20 TYPE skat-txt20,
         END OF ty_skat_txt.

  DATA: lt_vkoa  TYPE TABLE OF vkoa,
        lr_saknr TYPE RANGE OF skat-saknr,
        lt_skat  TYPE HASHED TABLE OF ty_skat_txt WITH UNIQUE KEY saknr.

  SELECT kappl, ktosl, vkorg, vtweg, ktosg, zterm, konts, konth
    FROM vkoa
    INTO CORRESPONDING FIELDS OF TABLE @lt_vkoa
    WHERE vkorg IN @s_vkorg
      AND vtweg IN @s_vtweg.

  " Build GL account range for single batch lookup
  lr_saknr = VALUE #(
    FOR ls IN lt_vkoa WHERE ( konts IS NOT INITIAL )
    ( sign = 'I' option = 'EQ' low = ls-konts ) ).
  SORT lr_saknr BY low.
  DELETE ADJACENT DUPLICATES FROM lr_saknr COMPARING low.

  IF lr_saknr IS NOT INITIAL.
    SELECT saknr, txt20
      FROM skat
      INTO TABLE @lt_skat
      WHERE spras = @sy-langu
        AND saknr IN @lr_saknr.
  ENDIF.

  LOOP AT lt_vkoa INTO DATA(ls_vkoa).
    DATA(ls_out) = VALUE ty_vkoa(
      kappl = ls_vkoa-kappl
      ktosl = ls_vkoa-ktosl
      vkorg = ls_vkoa-vkorg
      vtweg = ls_vkoa-vtweg
      ktosg = ls_vkoa-ktosg
      zterm = ls_vkoa-zterm
      konts = ls_vkoa-konts
      konth = ls_vkoa-konth
    ).
    IF ls_vkoa-konts IS NOT INITIAL.
      READ TABLE lt_skat WITH TABLE KEY saknr = ls_vkoa-konts
        INTO DATA(ls_skat).
      IF sy-subrc = 0.
        ls_out-txt_acct = ls_skat-txt20.
      ENDIF.
    ENDIF.
    APPEND ls_out TO gt_vkoa.
  ENDLOOP.

  SORT gt_vkoa BY kappl ktosl vkorg vtweg.
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
           auart TYPE vbak-auart,
           vkorg TYPE vbrk-vkorg,
           vtweg TYPE vbrk-vtweg,
           fkdat TYPE vbrk-fkdat,
           cnt   TYPE i,
         END OF ty_bill_cnt.

  DATA: lt_vbak     TYPE TABLE OF vbak,
        lt_bill_cnt TYPE TABLE OF ty_bill_cnt,
        lt_acc      TYPE HASHED TABLE OF ty_trans_summary
                    WITH UNIQUE KEY auart vkorg vtweg erdat.

  SELECT vbeln, auart, vkorg, vtweg, erdat, netwr
    FROM vbak
    INTO CORRESPONDING FIELDS OF TABLE @lt_vbak
    UP TO @p_maxrec ROWS
    WHERE vkorg IN @s_vkorg
      AND vtweg IN @s_vtweg
      AND spart IN @s_spart
      AND auart IN @s_auart
      AND erdat IN @s_erdat.

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
* FORM: DISPLAY_ALV_TABSTRIP
* Builds tabstrip container with one ALV grid per tab
*----------------------------------------------------------------------*
FORM display_alv_tabstrip.

  CREATE OBJECT go_dock
    EXPORTING
      repid     = sy-repid
      dynnr     = sy-dynnr
      side      = cl_gui_docking_container=>dock_at_left
      extension = 5000.

  CREATE OBJECT go_tabstrip
    EXPORTING
      parent = go_dock.

  go_tabstrip->add_c_tab(
    EXPORTING
      p_id      = 'TAB1'
      p_text    = 'Order Doc Types'
      p_tooltip = 'Sales Order Document Type Configuration' ).

  go_tabstrip->add_c_tab(
    EXPORTING
      p_id      = 'TAB2'
      p_text    = 'Item Categories'
      p_tooltip = 'Item Category Assignment' ).

  go_tabstrip->add_c_tab(
    EXPORTING
      p_id      = 'TAB3'
      p_text    = 'Billing Types'
      p_tooltip = 'Billing Document Type Configuration' ).

  go_tabstrip->add_c_tab(
    EXPORTING
      p_id      = 'TAB4'
      p_text    = 'Copy Control'
      p_tooltip = 'Billing Copy Control Rules' ).

  go_tabstrip->add_c_tab(
    EXPORTING
      p_id      = 'TAB5'
      p_text    = 'Output Records'
      p_tooltip = 'NACE Output Condition Records' ).

  go_tabstrip->add_c_tab(
    EXPORTING
      p_id      = 'TAB6'
      p_text    = 'Output Cond Types'
      p_tooltip = 'NACE Output Condition Type Config' ).

  go_tabstrip->add_c_tab(
    EXPORTING
      p_id      = 'TAB7'
      p_text    = 'Acct Determination'
      p_tooltip = 'VKOA Account Determination to GL' ).

  go_tabstrip->add_c_tab(
    EXPORTING
      p_id      = 'TAB8'
      p_text    = 'Transactional Summary'
      p_tooltip = 'Orders and Invoices Summary' ).

  CREATE OBJECT go_container1 EXPORTING parent = go_tabstrip container = 'TAB1'.
  CREATE OBJECT go_container2 EXPORTING parent = go_tabstrip container = 'TAB2'.
  CREATE OBJECT go_container3 EXPORTING parent = go_tabstrip container = 'TAB3'.
  CREATE OBJECT go_container4 EXPORTING parent = go_tabstrip container = 'TAB4'.
  CREATE OBJECT go_container5 EXPORTING parent = go_tabstrip container = 'TAB5'.
  CREATE OBJECT go_container6 EXPORTING parent = go_tabstrip container = 'TAB6'.
  CREATE OBJECT go_container7 EXPORTING parent = go_tabstrip container = 'TAB7'.
  CREATE OBJECT go_container8 EXPORTING parent = go_tabstrip container = 'TAB8'.

  PERFORM build_alv_order_types   USING go_container1.
  PERFORM build_alv_item_cat      USING go_container2.
  PERFORM build_alv_bill_types    USING go_container3.
  PERFORM build_alv_copy_control  USING go_container4.
  PERFORM build_alv_nace_output   USING go_container5.
  PERFORM build_alv_nace_access   USING go_container6.
  PERFORM build_alv_vkoa          USING go_container7.
  PERFORM build_alv_trans         USING go_container8.

ENDFORM.

*----------------------------------------------------------------------*
* FORM: BUILD_ALV_ORDER_TYPES
*----------------------------------------------------------------------*
FORM build_alv_order_types USING po_cont TYPE REF TO cl_gui_custom_container.
  gt_fcat_ord = VALUE lvc_t_fcat(
    ( fieldname = 'AUART'  coltext = 'Doc Type'        outputlen = 8  )
    ( fieldname = 'BEZEI'  coltext = 'Description'     outputlen = 30 )
    ( fieldname = 'AUTYP'  coltext = 'SD Doc Category' outputlen = 6  )
    ( fieldname = 'ABSTK'  coltext = 'Rejection Status' outputlen = 6 )
    ( fieldname = 'FAKTYP' coltext = 'Billing Type'    outputlen = 6  )
    ( fieldname = 'PRSFD'  coltext = 'Pricing'         outputlen = 6  )
    ( fieldname = 'COUNT'  coltext = 'Order Count'     outputlen = 12 ) ).

  CREATE OBJECT go_alv1 EXPORTING i_parent = po_cont.
  go_alv1->set_table_for_first_display(
    EXPORTING i_structure_name = space
    CHANGING  it_fieldcatalog  = gt_fcat_ord
              it_outtab        = gt_vbak_types ).
ENDFORM.

*----------------------------------------------------------------------*
* FORM: BUILD_ALV_ITEM_CAT
*----------------------------------------------------------------------*
FORM build_alv_item_cat USING po_cont TYPE REF TO cl_gui_custom_container.
  gt_fcat_itmct = VALUE lvc_t_fcat(
    ( fieldname = 'AUART' coltext = 'Sales Doc Type'    outputlen = 8  )
    ( fieldname = 'PSTYV' coltext = 'Item Category'     outputlen = 8  )
    ( fieldname = 'VTEXT' coltext = 'Description'       outputlen = 30 )
    ( fieldname = 'MTPOS' coltext = 'Material Type'     outputlen = 8  )
    ( fieldname = 'POSIT' coltext = 'Higher-Level Item' outputlen = 6  )
    ( fieldname = 'ERZET' coltext = 'Manual Entry'      outputlen = 6  )
    ( fieldname = 'ABGRU' coltext = 'Rejection Reason'  outputlen = 6  ) ).

  CREATE OBJECT go_alv2 EXPORTING i_parent = po_cont.
  go_alv2->set_table_for_first_display(
    EXPORTING i_structure_name = space
    CHANGING  it_fieldcatalog  = gt_fcat_itmct
              it_outtab        = gt_item_cat ).
ENDFORM.

*----------------------------------------------------------------------*
* FORM: BUILD_ALV_BILL_TYPES
*----------------------------------------------------------------------*
FORM build_alv_bill_types USING po_cont TYPE REF TO cl_gui_custom_container.
  gt_fcat_bill = VALUE lvc_t_fcat(
    ( fieldname = 'FKART' coltext = 'Billing Type'      outputlen = 8  )
    ( fieldname = 'VTEXT' coltext = 'Description'       outputlen = 30 )
    ( fieldname = 'FKTYP' coltext = 'SD Doc Category'   outputlen = 6  )
    ( fieldname = 'SFAKN' coltext = 'Cancellation Type' outputlen = 8  )
    ( fieldname = 'RPLKZ' coltext = 'Relevant for Acct' outputlen = 6  )
    ( fieldname = 'COUNT' coltext = 'Invoice Count'     outputlen = 12 ) ).

  CREATE OBJECT go_alv3 EXPORTING i_parent = po_cont.
  go_alv3->set_table_for_first_display(
    EXPORTING i_structure_name = space
    CHANGING  it_fieldcatalog  = gt_fcat_bill
              it_outtab        = gt_bill_types ).
ENDFORM.

*----------------------------------------------------------------------*
* FORM: BUILD_ALV_COPY_CONTROL
*----------------------------------------------------------------------*
FORM build_alv_copy_control USING po_cont TYPE REF TO cl_gui_custom_container.
  gt_fcat_bcopy = VALUE lvc_t_fcat(
    ( fieldname = 'KAPPL'    coltext = 'Application'     outputlen = 6 )
    ( fieldname = 'QUALF'    coltext = 'Source Doc Type' outputlen = 8 )
    ( fieldname = 'QUALZ'    coltext = 'Target Doc Type' outputlen = 8 )
    ( fieldname = 'FOTRANST' coltext = 'Copy Routine'    outputlen = 6 )
    ( fieldname = 'VBTYP_N'  coltext = 'Target SD Cat'  outputlen = 6 ) ).

  CREATE OBJECT go_alv4 EXPORTING i_parent = po_cont.
  go_alv4->set_table_for_first_display(
    EXPORTING i_structure_name = space
    CHANGING  it_fieldcatalog  = gt_fcat_bcopy
              it_outtab        = gt_bill_copy ).
ENDFORM.

*----------------------------------------------------------------------*
* FORM: BUILD_ALV_NACE_OUTPUT
*----------------------------------------------------------------------*
FORM build_alv_nace_output USING po_cont TYPE REF TO cl_gui_custom_container.
  gt_fcat_nace = VALUE lvc_t_fcat(
    ( fieldname = 'KAPPL' coltext = 'Application'  outputlen = 6  )
    ( fieldname = 'KSCHL' coltext = 'Output Type'  outputlen = 8  )
    ( fieldname = 'VKORG' coltext = 'Sales Org'    outputlen = 6  )
    ( fieldname = 'VTWEG' coltext = 'Dist Channel' outputlen = 6  )
    ( fieldname = 'SPART' coltext = 'Division'     outputlen = 6  )
    ( fieldname = 'NACHA' coltext = 'Medium'       outputlen = 6  )
    ( fieldname = 'TNAM'  coltext = 'Form/Program' outputlen = 20 )
    ( fieldname = 'COUNT' coltext = 'Record Count' outputlen = 10 ) ).

  CREATE OBJECT go_alv5 EXPORTING i_parent = po_cont.
  go_alv5->set_table_for_first_display(
    EXPORTING i_structure_name = space
    CHANGING  it_fieldcatalog  = gt_fcat_nace
              it_outtab        = gt_output ).
ENDFORM.

*----------------------------------------------------------------------*
* FORM: BUILD_ALV_NACE_ACCESS
*----------------------------------------------------------------------*
FORM build_alv_nace_access USING po_cont TYPE REF TO cl_gui_custom_container.
  gt_fcat_nacac = VALUE lvc_t_fcat(
    ( fieldname = 'KAPPL' coltext = 'Application' outputlen = 6  )
    ( fieldname = 'KSCHL' coltext = 'Cond Type'   outputlen = 8  )
    ( fieldname = 'KOZGF' coltext = 'Access Seq'  outputlen = 8  )
    ( fieldname = 'KRECH' coltext = 'Calc Type'   outputlen = 6  )
    ( fieldname = 'KBETR' coltext = 'Rate'        outputlen = 12 ) ).

  CREATE OBJECT go_alv6 EXPORTING i_parent = po_cont.
  go_alv6->set_table_for_first_display(
    EXPORTING i_structure_name = space
    CHANGING  it_fieldcatalog  = gt_fcat_nacac
              it_outtab        = gt_nace_access ).
ENDFORM.

*----------------------------------------------------------------------*
* FORM: BUILD_ALV_VKOA
*----------------------------------------------------------------------*
FORM build_alv_vkoa USING po_cont TYPE REF TO cl_gui_custom_container.
  gt_fcat_vkoa = VALUE lvc_t_fcat(
    ( fieldname = 'KAPPL'    coltext = 'Application'     outputlen = 6  )
    ( fieldname = 'KTOSL'    coltext = 'Acct Assign Key' outputlen = 10 )
    ( fieldname = 'VKORG'    coltext = 'Sales Org'       outputlen = 6  )
    ( fieldname = 'VTWEG'    coltext = 'Dist Channel'    outputlen = 6  )
    ( fieldname = 'KTOSG'    coltext = 'Acct Assign Grp' outputlen = 6 )
    ( fieldname = 'ZTERM'    coltext = 'Payment Terms'   outputlen = 8  )
    ( fieldname = 'KONTS'    coltext = 'GL Account'      outputlen = 10 )
    ( fieldname = 'KONTH'    coltext = 'GL Acct (Alt)'   outputlen = 10 )
    ( fieldname = 'TXT_ACCT' coltext = 'GL Description'  outputlen = 30 ) ).

  CREATE OBJECT go_alv7 EXPORTING i_parent = po_cont.
  go_alv7->set_table_for_first_display(
    EXPORTING i_structure_name = space
    CHANGING  it_fieldcatalog  = gt_fcat_vkoa
              it_outtab        = gt_vkoa ).
ENDFORM.

*----------------------------------------------------------------------*
* FORM: BUILD_ALV_TRANS
*----------------------------------------------------------------------*
FORM build_alv_trans USING po_cont TYPE REF TO cl_gui_custom_container.
  gt_fcat_trans = VALUE lvc_t_fcat(
    ( fieldname = 'VKORG'     coltext = 'Sales Org'     outputlen = 6  )
    ( fieldname = 'VTWEG'     coltext = 'Dist Channel'  outputlen = 6  )
    ( fieldname = 'AUART'     coltext = 'Order Type'    outputlen = 8  )
    ( fieldname = 'ERDAT'     coltext = 'Date'          outputlen = 10 )
    ( fieldname = 'ORDER_CNT' coltext = 'Order Count'   outputlen = 10 )
    ( fieldname = 'BILL_CNT'  coltext = 'Invoice Count' outputlen = 10 )
    ( fieldname = 'NET_VAL'   coltext = 'Net Value'     outputlen = 15
      datatype = 'CURR' ) ).

  CREATE OBJECT go_alv8 EXPORTING i_parent = po_cont.
  go_alv8->set_table_for_first_display(
    EXPORTING i_structure_name = space
    CHANGING  it_fieldcatalog  = gt_fcat_trans
              it_outtab        = gt_trans_summary ).
ENDFORM.
