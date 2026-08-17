REPORT zfrontend_print_plan.

PARAMETERS:
  p_host TYPE c LENGTH 32 DEFAULT 'DEFAULT_HOST',
  p_mandt TYPE n LENGTH 3 DEFAULT '000',
  p_user TYPE c LENGTH 20 DEFAULT 'master-adm',
  p_opt AS CHECKBOX DEFAULT 'X'.

PARAMETERS:
  p_valid RADIOBUTTON GROUP mode DEFAULT 'X',
  p_act   RADIOBUTTON GROUP mode.

PARAMETERS p_conf AS CHECKBOX.

START-OF-SELECTION.

  DATA ls_config TYPE zcl_frontend_print_planner=>ty_config.
  DATA lt_plan TYPE zcl_frontend_print_planner=>tt_services.
  DATA lt_result TYPE zcl_frontend_print_runner=>tt_results.
  DATA lo_planner TYPE REF TO zcl_frontend_print_planner.
  DATA lo_gateway TYPE REF TO zif_sicf_gateway.
  DATA lo_runner TYPE REF TO zcl_frontend_print_runner.

  IF p_act = abap_true
     AND p_conf = abap_false.
    WRITE: / 'ERROR: Activation mode requires explicit confirmation.'.
    RETURN.
  ENDIF.

  IF p_act = abap_true
     AND sy-mandt <> p_mandt.
    WRITE: / 'ERROR: Run the activation in client', p_mandt,
             'instead of client', sy-mandt.
    RETURN.
  ENDIF.

  ls_config = zcl_frontend_print_planner=>default_config( ).
  ls_config-virtual_host     = p_host.
  ls_config-client           = p_mandt.
  ls_config-run_user         = p_user.
  ls_config-include_optional = p_opt.

  CONDENSE ls_config-virtual_host NO-GAPS.
  CONDENSE ls_config-run_user NO-GAPS.

  CREATE OBJECT lo_planner.
  lt_plan = lo_planner->build_plan( ls_config ).

  IF p_act = abap_true.
    CREATE OBJECT lo_gateway TYPE zcl_sicf_gateway.
  ENDIF.

  CREATE OBJECT lo_runner
    EXPORTING
      io_gateway = lo_gateway.

  lt_result = lo_runner->execute(
    it_plan    = lt_plan
    iv_dry_run = p_valid ).

  WRITE: / 'Frontend print SICF service processing'.
  WRITE: / 'Profile:', ls_config-profile_id.
  WRITE: / 'Client/user:', ls_config-client, ls_config-run_user.
  IF p_valid = abap_true.
    WRITE: / 'Mode: dry run; no SICF services are changed.'.
  ELSE.
    WRITE: / 'Mode: activate required inactive SICF services.'.
  ENDIF.
  SKIP.

  LOOP AT lt_result INTO DATA(ls_result).
    READ TABLE lt_plan INTO DATA(ls_service) INDEX ls_result-sequence.
    IF sy-subrc <> 0.
      CLEAR ls_service.
    ENDIF.
    WRITE: / ls_result-sequence,
             ls_result-service_path,
             ls_result-status.
    WRITE: / '  ', ls_result-message.
    IF ls_service-reason IS NOT INITIAL.
      WRITE: / '  ', ls_service-reason.
    ENDIF.
  ENDLOOP.
