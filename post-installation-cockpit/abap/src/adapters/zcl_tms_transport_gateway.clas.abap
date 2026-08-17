CLASS zcl_tms_transport_gateway DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_bulk_transport_gateway.

    METHODS constructor
      IMPORTING
        iv_system TYPE tmscsys-sysnam OPTIONAL.

  PRIVATE SECTION.
    DATA mv_system TYPE tmscsys-sysnam.

ENDCLASS.


CLASS zcl_tms_transport_gateway IMPLEMENTATION.

  METHOD constructor.

    IF iv_system IS INITIAL.
      mv_system = sy-sysid.
    ELSE.
      mv_system = iv_system.
    ENDIF.

  ENDMETHOD.


  METHOD zif_bulk_transport_gateway~get_state.

    DATA lt_buffer TYPE STANDARD TABLE OF tmsbuffer.
    DATA ls_buffer TYPE tmsbuffer.
    DATA lv_detail TYPE string.
    DATA lv_system TYPE tmscsys-sysnam.
    DATA lv_request TYPE tmsbuffer-trkorr.
    DATA lv_subrc TYPE sy-subrc.

    lv_system = mv_system.
    lv_request = iv_request_id.

    CALL FUNCTION 'TMS_MGR_GREP_TRANSPORT_QUEUE'
      EXPORTING
        iv_system             = lv_system
        iv_request            = lv_request
        iv_refresh_queue      = abap_true
        iv_full_queue         = abap_true
        iv_pending_requests   = abap_true
        iv_completed_requests = abap_true
        iv_refused_requests   = abap_true
        iv_deleted_requests   = abap_true
        iv_monitor            = abap_false
      TABLES
        tt_buffer             = lt_buffer
      EXCEPTIONS
        read_config_failed       = 1
        read_import_queue_failed = 2
        OTHERS                   = 3.

    IF sy-subrc <> 0.
      lv_subrc = sy-subrc.
      RAISE EXCEPTION TYPE zcx_bulk_transport
        EXPORTING
          iv_detail =
            |Could not read import queue for { iv_request_id } in system { lv_system }; subrc={ lv_subrc }; message={ sy-msgid } { sy-msgno } { sy-msgv1 } { sy-msgv2 } { sy-msgv3 } { sy-msgv4 }|.
    ENDIF.

    READ TABLE lt_buffer INTO ls_buffer
      WITH KEY trkorr = iv_request_id
               tarcli = iv_target_client.

    IF sy-subrc <> 0.
      READ TABLE lt_buffer INTO ls_buffer
        WITH KEY trkorr = iv_request_id.
    ENDIF.

    IF sy-subrc <> 0.
      rs_state-available_in_buffer = abap_false.
      rs_state-imported_before     = abap_false.
      rs_state-import_running      = abap_false.
      rs_state-last_return_code    = 0.
      rs_state-details             =
        |Transport { iv_request_id } is not in the import queue for system { lv_system }|.
      RETURN.
    ENDIF.

    rs_state-last_return_code = ls_buffer-maxrc.

    IF ls_buffer-jobid IS NOT INITIAL
       OR ls_buffer-tpstatid IS NOT INITIAL
       OR ls_buffer-impsing = abap_true.
      rs_state-import_running = abap_true.
    ELSE.
      rs_state-import_running = abap_false.
    ENDIF.

    IF ls_buffer-impflg = '2'.
      rs_state-imported_before     = abap_true.
      rs_state-available_in_buffer = abap_false.
      rs_state-details =
        |Transport { iv_request_id } was already imported with return code { ls_buffer-maxrc }|.
      RETURN.
    ENDIF.

    IF ls_buffer-actflg = 'D'.
      rs_state-imported_before     = abap_false.
      rs_state-available_in_buffer = abap_false.
      rs_state-details =
        |Transport { iv_request_id } is deleted or denied in the import queue|.
      RETURN.
    ENDIF.

    rs_state-imported_before     = abap_false.
    rs_state-available_in_buffer = abap_true.

    lv_detail = |Transport { iv_request_id } is available for import|.

    IF ls_buffer-tarcli IS NOT INITIAL.
      lv_detail = |{ lv_detail } in client { ls_buffer-tarcli }|.
    ENDIF.

    rs_state-details = lv_detail.

  ENDMETHOD.


  METHOD zif_bulk_transport_gateway~queue_request.

    DATA lv_system TYPE tmscsys-sysnam.
    DATA lv_request TYPE tmsbuffer-trkorr.
    DATA lv_client TYPE tmsbuffer-tarcli.
    DATA lv_subrc TYPE sy-subrc.

    lv_system = mv_system.
    lv_request = iv_request_id.
    lv_client = iv_target_client.

    CALL FUNCTION 'TMS_MGR_FORWARD_TR_REQUEST'
      EXPORTING
        iv_request = lv_request
        iv_target  = lv_system
        iv_tarcli  = lv_client
        iv_monitor = abap_false
      EXCEPTIONS
        read_config_failed        = 1
        table_of_requests_is_empty = 2
        OTHERS                    = 3.

    IF sy-subrc <> 0.
      lv_subrc = sy-subrc.
      RAISE EXCEPTION TYPE zcx_bulk_transport
        EXPORTING
          iv_detail =
            |Could not add transport { iv_request_id } to import queue for system { lv_system }; subrc={ lv_subrc }; message={ sy-msgid } { sy-msgno } { sy-msgv1 } { sy-msgv2 } { sy-msgv3 } { sy-msgv4 }|.
    ENDIF.

  ENDMETHOD.


  METHOD zif_bulk_transport_gateway~import_request.

    DATA lv_tp_ret_code TYPE stpa-retcode.
    DATA lv_tp_alog TYPE stpa-file.
    DATA lv_tp_slog TYPE stpa-file.
    DATA lv_tp_pid TYPE stpa-pid.
    DATA lv_ignore_cvers TYPE stms_flag.
    DATA lv_system TYPE tmscsys-sysnam.
    DATA lv_request TYPE tmsbuffer-trkorr.
    DATA lv_client TYPE stpa-client.

    lv_system = mv_system.
    lv_request = iv_request_id.
    lv_client = iv_target_client.

    IF is_options-ignore_invalid_comp_version = abap_true.
      lv_ignore_cvers = abap_true.
    ELSE.
      lv_ignore_cvers = abap_false.
    ENDIF.

    CALL FUNCTION 'TMS_MGR_IMPORT_TR_REQUEST'
      EXPORTING
        iv_system       = lv_system
        iv_request      = lv_request
        iv_client       = lv_client
        iv_ignore_cvers = lv_ignore_cvers
        iv_monitor      = abap_false
      IMPORTING
        ev_tp_ret_code  = lv_tp_ret_code
        ev_tp_alog      = lv_tp_alog
        ev_tp_slog      = lv_tp_slog
        ev_tp_pid       = lv_tp_pid
      EXCEPTIONS
        read_config_failed        = 1
        table_of_requests_is_empty = 2
        OTHERS                    = 3.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_bulk_transport
        EXPORTING
          iv_detail =
            |Could not start import for { iv_request_id } in client { iv_target_client } on system { lv_system }|.
    ENDIF.

    rs_result-return_code = lv_tp_ret_code.
    rs_result-details =
      |Import finished for { iv_request_id } in client { iv_target_client }; ALOG={ lv_tp_alog }; SLOG={ lv_tp_slog }; PID={ lv_tp_pid }|.

  ENDMETHOD.

ENDCLASS.
