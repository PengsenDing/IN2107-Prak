CLASS zcl_client_prov_runner DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_result,
        sequence       TYPE i,
        phase          TYPE string,
        client         TYPE zcl_client_prov_planner=>ty_client,
        logical_system TYPE string,
        status         TYPE string,
        message        TYPE string,
      END OF ty_result.

    TYPES tt_results TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    METHODS constructor
      IMPORTING
        io_gateway TYPE REF TO zif_client_prov_gateway OPTIONAL.

    METHODS execute
      IMPORTING
        is_config          TYPE zcl_client_prov_planner=>ty_config
        it_plan            TYPE zcl_client_prov_planner=>tt_plan
        iv_dry_run         TYPE abap_bool DEFAULT 'X'
        iv_update_existing TYPE abap_bool DEFAULT space
      RETURNING
        VALUE(rt_result)   TYPE tt_results.

  PRIVATE SECTION.

    DATA mo_gateway TYPE REF TO zif_client_prov_gateway.

    METHODS add_result
      IMPORTING
        is_plan    TYPE zcl_client_prov_planner=>ty_plan_line
        iv_status  TYPE string
        iv_message TYPE string
      CHANGING
        ct_result  TYPE tt_results.

    METHODS build_settings
      IMPORTING
        is_config          TYPE zcl_client_prov_planner=>ty_config
        is_plan            TYPE zcl_client_prov_planner=>ty_plan_line
      RETURNING
        VALUE(rs_settings) TYPE zif_client_prov_gateway=>ty_client_settings.

ENDCLASS.


CLASS zcl_client_prov_runner IMPLEMENTATION.

  METHOD constructor.

    mo_gateway = io_gateway.

  ENDMETHOD.

  METHOD execute.

    DATA lv_has_error TYPE abap_bool.
    DATA lv_state TYPE string.
    DATA lv_status TYPE string.
    DATA ls_settings TYPE zif_client_prov_gateway=>ty_client_settings.

    LOOP AT it_plan TRANSPORTING NO FIELDS
      WHERE phase = `VALIDATION`
        AND action = `Configuration error`.
      lv_has_error = abap_true.
      EXIT.
    ENDLOOP.

    LOOP AT it_plan INTO DATA(ls_plan).

      IF ls_plan-phase = `VALIDATION`.
        IF ls_plan-action = `Configuration error`.
          lv_status = `validation_error`.
        ELSE.
          lv_status = `validation_warning`.
        ENDIF.
        add_result(
          EXPORTING
            is_plan    = ls_plan
            iv_status  = lv_status
            iv_message = ls_plan-details
          CHANGING
            ct_result  = rt_result ).
        CONTINUE.
      ENDIF.

      IF iv_dry_run = abap_true.
        add_result(
          EXPORTING
            is_plan    = ls_plan
            iv_status  = `planned`
            iv_message = |Would execute: { ls_plan-action }.|
          CHANGING
            ct_result  = rt_result ).
        CONTINUE.
      ENDIF.

      IF lv_has_error = abap_true.
        add_result(
          EXPORTING
            is_plan    = ls_plan
            iv_status  = `blocked`
            iv_message = `Execution was blocked by configuration errors.`
          CHANGING
            ct_result  = rt_result ).
        CONTINUE.
      ENDIF.

      IF mo_gateway IS NOT BOUND.
        add_result(
          EXPORTING
            is_plan    = ls_plan
            iv_status  = `failed`
            iv_message = `No client provisioning gateway is configured.`
          CHANGING
            ct_result  = rt_result ).
        CONTINUE.
      ENDIF.

      IF ls_plan-phase = `BD54`.
        lv_state = mo_gateway->get_logsys_state( ls_plan-logical_system ).
        IF lv_state = `exists`.
          lv_status = `already_exists`.
        ELSEIF lv_state = `missing`.
          lv_status = mo_gateway->create_logsys(
            iv_logical_system = ls_plan-logical_system
            iv_description    = is_config-description_template ).
        ELSE.
          lv_status = `failed`.
        ENDIF.
        add_result(
          EXPORTING
            is_plan    = ls_plan
            iv_status  = lv_status
            iv_message = |Logical system result: { lv_status }.|
          CHANGING
            ct_result  = rt_result ).
        CONTINUE.
      ENDIF.

      IF ls_plan-phase = `SCC4`.
        ls_settings = build_settings(
          is_config = is_config
          is_plan   = ls_plan ).
        lv_state = mo_gateway->get_client_state( ls_settings ).

        IF ls_plan-action = `Create client`.
          IF lv_state = `missing`.
            lv_status = mo_gateway->create_client( ls_settings ).
          ELSEIF lv_state = `matching` OR lv_state = `different`.
            lv_status = `already_exists`.
          ELSE.
            lv_status = `failed`.
          ENDIF.
        ELSEIF lv_state = `matching`.
          lv_status = `already_configured`.
        ELSEIF lv_state = `different`
           AND iv_update_existing = abap_true.
          lv_status = mo_gateway->update_client( ls_settings ).
        ELSEIF lv_state = `different`.
          lv_status = `update_skipped`.
        ELSE.
          lv_status = `failed`.
        ENDIF.

        add_result(
          EXPORTING
            is_plan    = ls_plan
            iv_status  = lv_status
            iv_message = |Client result: { lv_status }.|
          CHANGING
            ct_result  = rt_result ).
        CONTINUE.
      ENDIF.

      IF ls_plan-phase = `SCCLN`.
        add_result(
          EXPORTING
            is_plan    = ls_plan
            iv_status  = `manual_required`
            iv_message = `Client-copy scheduling remains an explicit manual follow-up.`
          CHANGING
            ct_result  = rt_result ).
      ELSE.
        add_result(
          EXPORTING
            is_plan    = ls_plan
            iv_status  = `information`
            iv_message = ls_plan-details
          CHANGING
            ct_result  = rt_result ).
      ENDIF.

    ENDLOOP.

  ENDMETHOD.

  METHOD add_result.

    DATA ls_result TYPE ty_result.

    ls_result-sequence       = is_plan-sequence.
    ls_result-phase          = is_plan-phase.
    ls_result-client         = is_plan-client.
    ls_result-logical_system = is_plan-logical_system.
    ls_result-status         = iv_status.
    ls_result-message        = iv_message.

    APPEND ls_result TO ct_result.

  ENDMETHOD.

  METHOD build_settings.

    rs_settings-client         = is_plan-client.
    rs_settings-logical_system = is_plan-logical_system.
    rs_settings-description    = is_config-description_template.
    rs_settings-city           = is_config-city.
    rs_settings-currency       = is_config-currency.
    rs_settings-role           = is_config-role.
    rs_settings-preset         = is_config-scc4_preset.

  ENDMETHOD.

ENDCLASS.
