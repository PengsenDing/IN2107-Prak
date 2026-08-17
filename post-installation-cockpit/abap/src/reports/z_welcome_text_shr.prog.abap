REPORT z_welcome_text_shr.

DATA gt_current TYPE STANDARD TABLE OF tline.
DATA gt_target TYPE STANDARD TABLE OF tline.
DATA gs_line TYPE tline.
DATA gv_line TYPE string.
DATA gv_line_count TYPE i.
DATA gv_line_count_text TYPE string.
DATA gv_doc_name_text TYPE string.
DATA gv_language_text TYPE string.
DATA gv_doc_class TYPE c LENGTH 2
  VALUE 'TX'.
DATA gv_doc_type TYPE c LENGTH 1
  VALUE 'E'.
DATA gv_doc_name TYPE c LENGTH 60
  VALUE 'ZLOGIN_SCREEN_INFO'.
DATA gv_language TYPE c LENGTH 1
  VALUE 'E'.

FORM write_pair USING iv_key TYPE string
                      iv_value TYPE string.
  DATA lv_line TYPE string.
  CONCATENATE iv_key '=' iv_value INTO lv_line.
  WRITE / lv_line.
ENDFORM.

FORM finish USING iv_changed TYPE string
                  iv_status TYPE string
                  iv_message TYPE string.
  gv_line_count = lines( gt_target ).
  gv_line_count_text = gv_line_count.
  gv_doc_name_text = gv_doc_name.
  gv_language_text = gv_language.
  WRITE / 'RESULT_BEGIN'.
  PERFORM write_pair USING 'changed' iv_changed.
  PERFORM write_pair USING 'status' iv_status.
  PERFORM write_pair USING 'message' iv_message.
  PERFORM write_pair USING 'document' gv_doc_name_text.
  PERFORM write_pair USING 'language' gv_language_text.
  PERFORM write_pair USING 'lines' gv_line_count_text.
  WRITE / 'RESULT_END'.
  STOP.
ENDFORM.

FORM fail USING iv_message TYPE string.
  PERFORM finish USING 'false' 'failed' iv_message.
ENDFORM.

FORM add_line USING iv_text TYPE string.
  DATA lv_text TYPE string.
  lv_text = iv_text.
  REPLACE ALL OCCURRENCES OF '<SID>' IN lv_text WITH sy-sysid.
  CLEAR gs_line.
  gs_line-tdformat = '*'.
  gs_line-tdline = lv_text.
  APPEND gs_line TO gt_target.
ENDFORM.

FORM build_target_text.


  CLEAR gv_line.


  CONCATENATE gv_line
    'Welcome to system <SID> hosted by the '
    INTO gv_line.

  CONCATENATE gv_line
    'SAP UCC in Munich, DE'
    INTO gv_line.

  PERFORM add_line USING gv_line.

  CLEAR gv_line.


  PERFORM add_line USING gv_line.

  CLEAR gv_line.


  CONCATENATE gv_line
    '@GA@ This server is running GB 4.3 bas'
    INTO gv_line.

  CONCATENATE gv_line
    'ed on S/4HANA 2023'
    INTO gv_line.

  PERFORM add_line USING gv_line.

  CLEAR gv_line.


  CONCATENATE gv_line
    'and SAP Basis 758 on HANA 2'
    INTO gv_line.

  PERFORM add_line USING gv_line.

  CLEAR gv_line.


  PERFORM add_line USING gv_line.

  CLEAR gv_line.


  CONCATENATE gv_line
    'Should you experience any difficulties'
    INTO gv_line.

  CONCATENATE gv_line
    ' during usage, you may reach'
    INTO gv_line.

  PERFORM add_line USING gv_line.

  CLEAR gv_line.


  CONCATENATE gv_line
    'us via our service desk at the followi'
    INTO gv_line.

  CONCATENATE gv_line
    'ng URL:'
    INTO gv_line.

  PERFORM add_line USING gv_line.

  CLEAR gv_line.


  CONCATENATE gv_line
    '@PA@  https://ucc.tum.de/ (Login via U'
    INTO gv_line.

  CONCATENATE gv_line
    '-User / H-User)'
    INTO gv_line.

  PERFORM add_line USING gv_line.

  CLEAR gv_line.


  PERFORM add_line USING gv_line.

  CLEAR gv_line.


  CONCATENATE gv_line
    '@19@ Please be aware of our weekly mai'
    INTO gv_line.

  CONCATENATE gv_line
    'ntenance window scheduled each'
    INTO gv_line.

  PERFORM add_line USING gv_line.

  CLEAR gv_line.


  CONCATENATE gv_line
    'Thursday from 06:00 PM to 10:00 PM (UT'
    INTO gv_line.

  CONCATENATE gv_line
    'C+1). If any activities are'
    INTO gv_line.

  PERFORM add_line USING gv_line.

  CLEAR gv_line.


  CONCATENATE gv_line
    'planned, we will inform you in advance'
    INTO gv_line.

  CONCATENATE gv_line
    '.'
    INTO gv_line.

  PERFORM add_line USING gv_line.

  CLEAR gv_line.


  PERFORM add_line USING gv_line.

  CLEAR gv_line.


  CONCATENATE gv_line
    'Available languages:'
    INTO gv_line.

  PERFORM add_line USING gv_line.

  CLEAR gv_line.


  CONCATENATE gv_line
    'DE - Deutsch           ES - Espagnol  '
    INTO gv_line.

  CONCATENATE gv_line
    '        RU - Русский'
    INTO gv_line.

  PERFORM add_line USING gv_line.

  CLEAR gv_line.


  CONCATENATE gv_line
    'EN - English           FR - Français  '
    INTO gv_line.

  CONCATENATE gv_line
    '        PT - Português'
    INTO gv_line.

  PERFORM add_line USING gv_line.

ENDFORM.

START-OF-SELECTION.
  IF sy-mandt <> '000'.
    PERFORM fail USING 'Run this report in client 000'.
  ENDIF.
  PERFORM build_target_text.

  CALL FUNCTION 'DOCU_GET'
    EXPORTING
      id = gv_doc_class
      langu = gv_language
      object = gv_doc_name
      typ = gv_doc_type
    TABLES
      line = gt_current
    EXCEPTIONS
      OTHERS = 99.

  IF sy-subrc <> 0.
    CLEAR gt_current.
  ENDIF.

  IF gt_current = gt_target.
    PERFORM finish USING
      'false'
      'ok'
      'SAP Logon welcome text already matches desired content.'.
  ENDIF.

  CALL FUNCTION 'DOCU_UPDATE'
    EXPORTING
      id = gv_doc_class
      langu = gv_language
      object = gv_doc_name
      typ = gv_doc_type
    TABLES
      line = gt_target
    EXCEPTIONS
      OTHERS = 99.

  IF sy-subrc <> 0.
    PERFORM fail USING 'DOCU_UPDATE failed for ZLOGIN_SCREEN_INFO.'.
  ENDIF.

  COMMIT WORK AND WAIT.

  PERFORM finish USING
    'true'
    'ok'
    'SAP Logon welcome text updated in SE61 document.'.
