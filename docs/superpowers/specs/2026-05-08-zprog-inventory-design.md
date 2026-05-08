# Z Program Inventory View — Design Spec
**Date:** 2026-05-08
**Report:** ZSDR_CONFIG_REVIEW
**Author:** Clinton_Smith

---

## Overview

Add a seventh radio button view (`r_zprog`) to ZSDR_CONFIG_REVIEW that inventories all Z programs on the system. The view helps distinguish active, production-grade custom programs from test/temp/dead code, and surfaces what each program does (input method, output method) without requiring the reviewer to open each program individually.

---

## Selection Screen Changes

One new parameter added to the existing selection screen:

- `r_zprog` — radio button "Z Program Inventory" added to GROUP r1
- `p_noise` — checkbox "Exclude Suspected Noise", **checked by default**

No date range required for this view (reads static metadata and source, not transactional data).

---

## Output Columns

| Field | Source | Notes |
|---|---|---|
| `progname` | `TRDIR` | Program name |
| `prog_txt` | `TRDIRT` | Short description |
| `devclass` | `TADIR` | Package / development class |
| `prog_type` | `TRDIR-SUBC` | Decoded: Executable, Module Pool, Include, Subr. Pool, Class |
| `cnam` | `TRDIR` | Created by |
| `cdat` | `TRDIR` | Created date |
| `udat` | `TRDIR` | Last changed date |
| `last_spool` | `TSP01` | Most recent spool date — best available proxy for last run |
| `input_type` | `REPOSRC` | e.g. "Sel.Screen", "File", "Sel.Screen+File", blank |
| `output_type` | `REPOSRC` | e.g. "Print", "ALV", "File", "Print+File", blank |

---

## Data Sources

| Table | Usage |
|---|---|
| `TRDIR` | Program attributes: type, created by/date, last changed date |
| `TRDIRT` | Language-dependent short description |
| `TADIR` | Package (DEVCLASS), filters to PGMID='R3TR' AND OBJECT='PROG' |
| `TSP01` | MAX(RQCRDAT) grouped by RQPNM — last spool date per program |
| `REPOSRC` | Source code lines — scanned for noise flags and input/output patterns |

---

## Noise Filter Logic

When `p_noise = 'X'` (default), programs matching any of the following are excluded from output:

**Name patterns** (case-insensitive, checked against `TRDIR-NAME`):
- Contains: `TEST`, `TEMP`, `TMP`, `COPY`, `OLD`, `BAK`, `DEL`

**Description patterns** (checked against `TRDIRT-TEXT`):
- Contains: `TEST`, `TEMP`, `COPY`, `OLD`, `UNUSED`, `DELETE`, `WORKAROUND`

**Source header scan** (first 20 lines of `REPOSRC`, **including** comment lines):
- Contains: `TEST`, `TEMP`, `COPY`, `OLD`, `UNUSED`, `DELETE`, `WORKAROUND`, `DO NOT USE`

A program is flagged as noise if **any one** of the three signals triggers. Flagged programs are silently excluded when `p_noise` is checked; all programs appear when unchecked.

---

## Input / Output Detection

Detected by scanning `REPOSRC` for keyword patterns. Comment lines (starting with `*` or `"`) are **excluded** from these scans — only executable source lines are checked.

**Input type** — separate `SELECT DISTINCT progname` passes per keyword group:

| Keyword(s) | Label |
|---|---|
| `PARAMETERS` or `SELECT-OPTIONS` or `SELECTION-SCREEN` | "Sel.Screen" |
| `OPEN DATASET` + `READ DATASET` | "File" |

If both present: "Sel.Screen+File". If neither: blank.

**Output type** — separate `SELECT DISTINCT progname` passes per keyword group:

| Keyword(s) | Label |
|---|---|
| `WRITE` | "Print" |
| `CL_SALV_TABLE` or `REUSE_ALV` | "ALV" |
| `TRANSFER` or (`OPEN DATASET` without `READ DATASET`) | "File" |

Combinations concatenated with `+`: e.g. "Print+ALV", "File+ALV". If none: blank.

---

## Fetch Logic (fetch_zprog)

```
1. SELECT all Z program names from TRDIR (NAME LIKE 'Z%')
   → base list, ~938 rows

2. SELECT descriptions from TRDIRT (spras = sy-langu)
   → hashed table keyed by progname

3. SELECT DEVCLASS from TADIR
   (PGMID='R3TR', OBJECT='PROG', OBJ_NAME LIKE 'Z%')
   → hashed table keyed by progname

4. SELECT MAX(RQCRDAT) from TSP01 GROUP BY RQPNM
   WHERE RQPNM LIKE 'Z%'
   → hashed table keyed by progname

5. IF p_noise = 'X':
   a. SELECT DISTINCT progname FROM REPOSRC
      WHERE progname LIKE 'Z%' AND ZEILE <= 20
      AND (line contains noise keywords)
      → noise set

6. Input/Output detection — 5 separate SELECT DISTINCT progname passes
   against REPOSRC WHERE progname LIKE 'Z%'
   AND line NOT LIKE '*%' AND line NOT LIKE '"%'
   AND line LIKE '%KEYWORD%'

7. LOOP over base TRDIR list:
   - Skip if in noise set (when p_noise active)
   - Resolve description, package, spool date from hashed tables
   - Decode SUBC to text
   - Build input_type / output_type strings from detection sets
   - Update progress indicator: "Analyzing program X of N..."
   - APPEND to gt_zprog

8. SORT BY devclass progname
```

---

## Progress Indicator

`SAPGUI_PROGRESS_INDICATOR` called inside the main LOOP (step 7) every iteration:

```abap
CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
  EXPORTING
    percentage = lv_pct
    text       = |Analyzing program { lv_idx } of { lv_total }...|.
```

`lv_pct` = `( lv_idx / lv_total ) * 100`, cast to integer.

---

## Program Type Decode (TRDIR-SUBC)

| Code | Text |
|---|---|
| `1` | Executable |
| `F` | Function Group |
| `I` | Include |
| `K` | Class |
| `M` | Module Pool |
| `S` | Subroutine Pool |
| other | raw code |

---

## Struct (ty_zprog)

```abap
BEGIN OF ty_zprog,
  progname   TYPE progname,
  prog_txt   TYPE text60,
  devclass   TYPE devclass,
  prog_type  TYPE c LENGTH 16,
  cnam       TYPE syuname,
  cdat       TYPE sydatum,
  udat       TYPE sydatum,
  last_spool TYPE sydatum,
  input_type TYPE c LENGTH 20,
  output_type TYPE c LENGTH 20,
END OF ty_zprog.
```

---

## ALV Title

"Z Program Inventory"

---

## Sort

`devclass ASCENDING, progname ASCENDING`
