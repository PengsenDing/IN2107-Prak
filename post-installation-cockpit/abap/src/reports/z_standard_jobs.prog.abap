REPORT z_standard_jobs.

DATA gt_bdc TYPE STANDARD TABLE OF bdcdata.
DATA gs_bdc TYPE bdcdata.
DATA gt_msg TYPE STANDARD TABLE OF bdcmsgcoll.
DATA gs_msg TYPE bdcmsgcoll.
DATA gs_opt TYPE ctu_params.
DATA gv_text TYPE string.
DATA gv_all_text TYPE string.
DATA gv_subrc TYPE sysubrc.
DATA gv_subrc_text TYPE string.
DATA gv_message TYPE string.
DATA gv_state TYPE c LENGTH 1.
DATA gv_prog_name TYPE progname.
DATA gv_report TYPE c LENGTH 40 VALUE 'R_JR_UTIL_1'.
DATA gv_tcode TYPE c LENGTH 20 VALUE 'SA38'.
DATA gv_init_prog TYPE c LENGTH 40
  VALUE 'SAPMS38M'.
DATA gv_init_screen TYPE c LENGTH 4
  VALUE '0101'.
DATA gv_init_ok TYPE c LENGTH 20
  VALUE '=STRT'.
DATA gv_prog_field TYPE c LENGTH 40
  VALUE 'RS38M-PROGRAMM'.
DATA gv_rep_screen TYPE c LENGTH 4
  VALUE '1000'.
DATA gv_rep_ok TYPE c LENGTH 20
  VALUE '=ONLI'.
DATA gv_show_field TYPE c LENGTH 40
  VALUE 'SHOW'.
DATA gv_change_field TYPE c LENGTH 40
  VALUE 'CHANGE'.
DATA gv_pop_prog TYPE c LENGTH 40
  VALUE 'SAPLSPO1'.
DATA gv_pop_screen TYPE c LENGTH 4
  VALUE '0100'.
DATA gv_pop_ok TYPE c LENGTH 20
  VALUE '=YES'.
DATA gv_list_prog TYPE c LENGTH 40
  VALUE 'SAPMSSY0'.
DATA gv_list_screen TYPE c LENGTH 4
  VALUE '0120'.
DATA gv_list_ok TYPE c LENGTH 20
  VALUE '=BACK'.
DATA gv_exit_ok TYPE c LENGTH 20
  VALUE '/EE'.

FORM write_pair USING iv_key TYPE clike
                      iv_value TYPE clike.
  DATA lv_line TYPE string.
  CONCATENATE iv_key '=' iv_value INTO lv_line.
  WRITE / lv_line.
ENDFORM.

FORM finish USING iv_changed TYPE string
                  iv_status TYPE string
                  iv_message TYPE string.
  WRITE / 'RESULT_BEGIN'.
  PERFORM write_pair USING 'changed' iv_changed.
  PERFORM write_pair USING 'status' iv_status.
  PERFORM write_pair USING 'message' iv_message.
  PERFORM write_pair USING 'client' sy-mandt.
  PERFORM write_pair USING 'report' gv_report.
  gv_subrc_text = gv_subrc.
  PERFORM write_pair USING 'sap_subrc' gv_subrc_text.
  WRITE / 'RESULT_END'.
  STOP.
ENDFORM.

FORM bdc_dynpro USING iv_program TYPE any
                      iv_dynpro TYPE any.
  CLEAR gs_bdc.
  gs_bdc-program = iv_program.
  gs_bdc-dynpro = iv_dynpro.
  gs_bdc-dynbegin = 'X'.
  APPEND gs_bdc TO gt_bdc.
ENDFORM.

FORM bdc_field USING iv_name TYPE any
                     iv_value TYPE any.
  CLEAR gs_bdc.
  gs_bdc-fnam = iv_name.
  gs_bdc-fval = iv_value.
  APPEND gs_bdc TO gt_bdc.
ENDFORM.

FORM add_msg_text USING is_msg TYPE bdcmsgcoll.
  CLEAR gv_text.
  CALL FUNCTION 'MESSAGE_TEXT_BUILD'
    EXPORTING
      msgid = is_msg-msgid
      msgnr = is_msg-msgnr
      msgv1 = is_msg-msgv1
      msgv2 = is_msg-msgv2
      msgv3 = is_msg-msgv3
      msgv4 = is_msg-msgv4
    IMPORTING
      message_text_output = gv_text
    EXCEPTIONS
      OTHERS = 1.
  IF gv_text IS INITIAL.
    CONCATENATE is_msg-msgid is_msg-msgnr INTO gv_text
      SEPARATED BY space.
  ENDIF.
  IF gv_all_text IS INITIAL.
    gv_all_text = gv_text.
  ELSE.
    CONCATENATE gv_all_text gv_text INTO gv_all_text
      SEPARATED BY ' | '.
  ENDIF.
ENDFORM.

FORM collect_messages.
  LOOP AT gt_msg INTO gs_msg.
    PERFORM add_msg_text USING gs_msg.
  ENDLOOP.
ENDFORM.

* Runs R_JR_UTIL_1 in display mode and parses its list output.
* cv_state: 'A' = automation active, 'I' = inactive,
* initial = state could not be determined.
FORM read_state CHANGING cv_state TYPE c.
  TYPES ty_line TYPE c LENGTH 255.
  DATA lt_list TYPE STANDARD TABLE OF abaplist.
  DATA lt_text TYPE STANDARD TABLE OF ty_line.
  DATA lv_line TYPE ty_line.

  CLEAR cv_state.
  CALL FUNCTION 'LIST_FREE_MEMORY'.
  SUBMIT (gv_report)
    WITH show = 'X'
    WITH change = ' '
    WITH set_user = ' '
    EXPORTING LIST TO MEMORY
    AND RETURN.
  CALL FUNCTION 'LIST_FROM_MEMORY'
    TABLES
      listobject = lt_list
    EXCEPTIONS
      OTHERS = 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
  CALL FUNCTION 'LIST_TO_ASCI'
    TABLES
      listasci   = lt_text
      listobject = lt_list
    EXCEPTIONS
      OTHERS = 1.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.
* 'INACTIVE'/'INAKTIV' must be tested before 'ACTIVE'/'AKTIV'
* because the latter are substrings of the former.
  LOOP AT lt_text INTO lv_line.
    TRANSLATE lv_line TO UPPER CASE.
    IF lv_line CS 'INACTIVE' OR lv_line CS 'NOT ACTIVE'
        OR lv_line CS 'INAKTIV'.
      cv_state = 'I'.
      RETURN.
    ENDIF.
    IF lv_line CS 'ACTIVE' OR lv_line CS 'AKTIV'.
      cv_state = 'A'.
      RETURN.
    ENDIF.
  ENDLOOP.
ENDFORM.

START-OF-SELECTION.
  IF sy-mandt <> '000'.
    PERFORM finish USING 'false' 'failed'
      'Run this report in client 000'.
  ENDIF.

  SELECT SINGLE name FROM trdir INTO @gv_prog_name
    WHERE name = @gv_report.
  IF sy-subrc <> 0.
    PERFORM finish USING 'false' 'failed'
      'Report R_JR_UTIL_1 does not exist in this system'.
  ENDIF.

  PERFORM read_state CHANGING gv_state.
  IF gv_state = 'A'.
    PERFORM finish USING
      'false'
      'ok'
      'Job repository automation is already active; no change made.'.
  ENDIF.
  IF gv_state IS INITIAL.
    PERFORM finish USING 'false' 'failed'
      'Could not determine the job repository status from R_JR_UTIL_1 output'.
  ENDIF.

* State is inactive: run R_JR_UTIL_1 in change mode via batch
* input. Answering Ja on the confirmation popup is only safe
* here because the popup can only ask about activation now.
  PERFORM bdc_dynpro USING gv_init_prog gv_init_screen.
  PERFORM bdc_field USING gv_prog_field gv_report.
  PERFORM bdc_field USING 'BDC_OKCODE' gv_init_ok.

  PERFORM bdc_dynpro USING gv_report gv_rep_screen.
  PERFORM bdc_field USING gv_show_field ' '.
  PERFORM bdc_field USING gv_change_field 'X'.
  PERFORM bdc_field USING 'BDC_OKCODE' gv_rep_ok.

  PERFORM bdc_dynpro USING gv_pop_prog gv_pop_screen.
  PERFORM bdc_field USING 'BDC_OKCODE' gv_pop_ok.

* The confirmation opens the standard ABAP list processor. Return from
* the list and leave the report selection screen so CALL TRANSACTION can
* finish cleanly. These dynpros were verified with SHDB on this system.
  PERFORM bdc_dynpro USING gv_list_prog gv_list_screen.
  PERFORM bdc_field USING 'BDC_OKCODE' gv_list_ok.

  PERFORM bdc_dynpro USING gv_report gv_rep_screen.
  PERFORM bdc_field USING 'BDC_OKCODE' gv_exit_ok.

  gs_opt-dismode = 'N'.
  gs_opt-updmode = 'S'.
  gs_opt-defsize = 'X'.

  CALL TRANSACTION gv_tcode USING gt_bdc OPTIONS FROM gs_opt
    MESSAGES INTO gt_msg.
  gv_subrc = sy-subrc.

  PERFORM collect_messages.

* Do not trust sy-subrc here: batch input may abort on a trailing
* list screen even after a successful activation. Re-read the
* state to decide the real outcome.
  PERFORM read_state CHANGING gv_state.
  IF gv_state = 'A'.
    PERFORM finish USING
      'true'
      'ok'
      'Job repository automation activated by R_JR_UTIL_1.'.
  ENDIF.

  IF gv_all_text IS INITIAL.
    gv_message =
      'R_JR_UTIL_1 was executed but activation could not be verified.'.
  ELSE.
    CONCATENATE
      'R_JR_UTIL_1 was executed but activation could not be verified:'
      gv_all_text INTO gv_message SEPARATED BY space.
  ENDIF.
  PERFORM finish USING 'false' 'failed' gv_message.
