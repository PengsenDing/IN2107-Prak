CLASS zcl_client_prov_gateway DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES zif_client_prov_gateway.

  PRIVATE SECTION.

    METHODS is_authorized
      RETURNING
        VALUE(rv_authorized) TYPE abap_bool.

    METHODS fill_client
      IMPORTING
        is_settings      TYPE zif_client_prov_gateway=>ty_client_settings
      RETURNING
        VALUE(rs_client) TYPE t000.

ENDCLASS.


CLASS zcl_client_prov_gateway IMPLEMENTATION.

  METHOD zif_client_prov_gateway~get_logsys_state.

    DATA lv_found TYPE tbdls-logsys.

    SELECT SINGLE logsys
      FROM tbdls
      INTO lv_found
      WHERE logsys = iv_logical_system.

    IF sy-subrc = 0.
      rv_state = `exists`.
    ELSE.
      rv_state = `missing`.
    ENDIF.

  ENDMETHOD.

  METHOD zif_client_prov_gateway~create_logsys.

    DATA ls_logsys TYPE tbdls.
    DATA ls_text TYPE tbdlst.

    IF is_authorized( ) = abap_false.
      rv_status = `unauthorized`.
      RETURN.
    ENDIF.

    IF me->zif_client_prov_gateway~get_logsys_state( iv_logical_system ) = `exists`.
      rv_status = `already_exists`.
      RETURN.
    ENDIF.

    ls_logsys-logsys = iv_logical_system.
    INSERT tbdls FROM ls_logsys.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      rv_status = `failed`.
      RETURN.
    ENDIF.

    ls_text-langu  = sy-langu.
    ls_text-logsys = iv_logical_system.
    ls_text-stext  = iv_description.
    INSERT tbdlst FROM ls_text.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      rv_status = `failed`.
      RETURN.
    ENDIF.

    COMMIT WORK AND WAIT.
    rv_status = `created`.

  ENDMETHOD.

  METHOD zif_client_prov_gateway~get_client_state.

    DATA ls_actual TYPE t000.
    DATA ls_expected TYPE t000.

    SELECT SINGLE *
      FROM t000
      INTO ls_actual
      WHERE mandt = is_settings-client.

    IF sy-subrc <> 0.
      rv_state = `missing`.
      RETURN.
    ENDIF.

    ls_expected = fill_client( is_settings ).

    IF ls_actual-mtext       = ls_expected-mtext
       AND ls_actual-ort01       = ls_expected-ort01
       AND ls_actual-mwaer       = ls_expected-mwaer
       AND ls_actual-logsys      = ls_expected-logsys
       AND ls_actual-cccategory  = ls_expected-cccategory
       AND ls_actual-cccoractiv  = ls_expected-cccoractiv
       AND ls_actual-ccnocliind  = ls_expected-ccnocliind
       AND ls_actual-cccopylock  = ls_expected-cccopylock
       AND ls_actual-ccnocascad  = ls_expected-ccnocascad
       AND ls_actual-ccsoftlock  = ls_expected-ccsoftlock
       AND ls_actual-ccimaildis  = ls_expected-ccimaildis
       AND ls_actual-cctemplock  = ls_expected-cctemplock.
      rv_state = `matching`.
    ELSE.
      rv_state = `different`.
    ENDIF.

  ENDMETHOD.

  METHOD zif_client_prov_gateway~create_client.

    DATA ls_client TYPE t000.

    IF is_authorized( ) = abap_false.
      rv_status = `unauthorized`.
      RETURN.
    ENDIF.

    IF me->zif_client_prov_gateway~get_client_state( is_settings ) <> `missing`.
      rv_status = `already_exists`.
      RETURN.
    ENDIF.

    ls_client = fill_client( is_settings ).
    INSERT t000 FROM ls_client.
    IF sy-subrc <> 0.
      ROLLBACK WORK.
      rv_status = `failed`.
      RETURN.
    ENDIF.

    COMMIT WORK AND WAIT.
    rv_status = `created`.

  ENDMETHOD.

  METHOD zif_client_prov_gateway~update_client.

    DATA ls_client TYPE t000.

    IF is_authorized( ) = abap_false.
      rv_status = `unauthorized`.
      RETURN.
    ENDIF.

    IF me->zif_client_prov_gateway~get_client_state( is_settings ) = `missing`.
      rv_status = `missing`.
      RETURN.
    ENDIF.

    ls_client = fill_client( is_settings ).
    UPDATE t000 SET
      mtext      = ls_client-mtext
      ort01      = ls_client-ort01
      mwaer      = ls_client-mwaer
      logsys     = ls_client-logsys
      cccategory = ls_client-cccategory
      cccoractiv = ls_client-cccoractiv
      ccnocliind = ls_client-ccnocliind
      cccopylock = ls_client-cccopylock
      ccnocascad = ls_client-ccnocascad
      ccsoftlock = ls_client-ccsoftlock
      ccimaildis = ls_client-ccimaildis
      cctemplock = ls_client-cctemplock
      changeuser = sy-uname
      changedate = sy-datum
      WHERE mandt = is_settings-client.

    IF sy-subrc <> 0.
      ROLLBACK WORK.
      rv_status = `failed`.
      RETURN.
    ENDIF.

    COMMIT WORK AND WAIT.
    rv_status = `updated`.

  ENDMETHOD.

  METHOD is_authorized.

    rv_authorized = abap_false.

    AUTHORITY-CHECK OBJECT 'S_ADMI_FCD'
      ID 'S_ADMI_FCD' FIELD 'T000'.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    AUTHORITY-CHECK OBJECT 'S_TABU_CLI'
      ID 'CLIIDMAINT' FIELD 'X'.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    AUTHORITY-CHECK OBJECT 'S_TABU_DIS'
      ID 'DICBERCLS' FIELD 'SS'
      ID 'ACTVT'     FIELD '02'.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    rv_authorized = abap_true.

  ENDMETHOD.

  METHOD fill_client.

    DATA lv_role TYPE string.

    rs_client-mandt       = is_settings-client.
    rs_client-mtext       = is_settings-description.
    rs_client-ort01       = is_settings-city.
    rs_client-mwaer       = is_settings-currency.
    rs_client-logsys      = is_settings-logical_system.
    rs_client-cccopylock  = space.
    rs_client-ccnocascad  = space.
    rs_client-ccsoftlock  = space.
    rs_client-ccimaildis  = space.
    rs_client-cctemplock  = space.
    rs_client-changeuser  = sy-uname.
    rs_client-changedate  = sy-datum.

    lv_role = is_settings-role.
    TRANSLATE lv_role TO UPPER CASE.
    CONDENSE lv_role NO-GAPS.

    CASE lv_role.
      WHEN `PRODUCTION` OR `LIVE`.
        rs_client-cccategory = 'P'.
      WHEN `TEST`.
        rs_client-cccategory = 'T'.
      WHEN `CUSTOMIZING`.
        rs_client-cccategory = 'C'.
      WHEN `DEMO`.
        rs_client-cccategory = 'D'.
      WHEN `SAPREFERENCE`.
        rs_client-cccategory = 'S'.
      WHEN OTHERS.
        rs_client-cccategory = 'E'.
    ENDCASE.

    IF is_settings-preset = zcl_client_prov_planner=>gc_preset_development.
      rs_client-cccoractiv = space.
      rs_client-ccnocliind = space.
    ELSE.
      rs_client-cccoractiv = '2'.
      rs_client-ccnocliind = '3'.
    ENDIF.

  ENDMETHOD.

ENDCLASS.
