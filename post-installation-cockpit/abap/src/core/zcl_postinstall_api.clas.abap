CLASS zcl_postinstall_api DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    CONSTANTS:
      gc_api_version TYPE string VALUE `1`,
      gc_operation_ping TYPE string VALUE `PING`,
      gc_op_frontend_print_validate TYPE string
        VALUE `FRONTEND_PRINT_VALIDATE`,
      gc_op_frontend_print_activate TYPE string
        VALUE `FRONTEND_PRINT_ACTIVATE`,
      gc_op_client_prov_validate TYPE string
        VALUE `CLIENT_PROVISION_VALIDATE`,
      gc_op_client_prov_execute TYPE string
        VALUE `CLIENT_PROVISION_EXECUTE`,
      gc_op_bulk_transport_validate TYPE string
        VALUE `BULK_TRANSPORT_VALIDATE`,
      gc_op_bulk_transport_import TYPE string
        VALUE `BULK_TRANSPORT_IMPORT`.

    TYPES:
      BEGIN OF ty_frontend_print_parameters,
        virtual_host     TYPE string,
        include_optional TYPE abap_bool,
      END OF ty_frontend_print_parameters.

    TYPES:
      BEGIN OF ty_client_prov_parameters,
        sid             TYPE string,
        system_type     TYPE string,
        client_from     TYPE string,
        client_to       TYPE string,
        update_existing TYPE abap_bool,
      END OF ty_client_prov_parameters.

    TYPES:
      BEGIN OF ty_bulk_transport_parameters,
        config_file_path TYPE string,
        stop_on_warning  TYPE abap_bool,
      END OF ty_bulk_transport_parameters.

    TYPES:
      BEGIN OF ty_item,
        sequence     TYPE i,
        service_path TYPE string,
        status       TYPE string,
        message      TYPE string,
        reason       TYPE string,
        phase        TYPE string,
        client       TYPE string,
        logical_system TYPE string,
        action       TYPE string,
      END OF ty_item.

    TYPES tt_items TYPE STANDARD TABLE OF ty_item WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_response,
        api_version TYPE string,
        request_id  TYPE string,
        operation   TYPE string,
        status      TYPE string,
        system_id   TYPE string,
        client      TYPE string,
        user        TYPE string,
        server_time TYPE string,
        message     TYPE string,
        items       TYPE tt_items,
      END OF ty_response.

    CLASS-METHODS execute
      IMPORTING
        iv_operation       TYPE string
        iv_parameters_json TYPE string OPTIONAL
        iv_request_id      TYPE string OPTIONAL
      EXPORTING
        ev_status          TYPE string
        ev_message         TYPE string
        ev_result_json     TYPE string.

  PRIVATE SECTION.

    CLASS-METHODS initialize_response
      IMPORTING
        iv_operation  TYPE string
        iv_request_id TYPE string
      RETURNING
        VALUE(rs_response) TYPE ty_response.

    CLASS-METHODS run_frontend_print_validation
      IMPORTING
        iv_parameters_json TYPE string
        iv_activate        TYPE abap_bool DEFAULT abap_false
      CHANGING
        cs_response        TYPE ty_response.

    CLASS-METHODS run_client_provisioning
      IMPORTING
        iv_parameters_json TYPE string
        iv_execute         TYPE abap_bool
      CHANGING
        cs_response        TYPE ty_response.

    CLASS-METHODS run_bulk_transport_import
      IMPORTING
        iv_parameters_json TYPE string
        iv_import          TYPE abap_bool
      CHANGING
        cs_response        TYPE ty_response.

    CLASS-METHODS serialize_response
      IMPORTING
        is_response          TYPE ty_response
      RETURNING
        VALUE(rv_result_json) TYPE string.

ENDCLASS.


CLASS zcl_postinstall_api IMPLEMENTATION.

  METHOD execute.

    DATA lv_operation TYPE string.
    DATA ls_response TYPE ty_response.

    lv_operation = iv_operation.
    CONDENSE lv_operation NO-GAPS.
    TRANSLATE lv_operation TO UPPER CASE.

    ls_response = initialize_response(
      iv_operation  = lv_operation
      iv_request_id = iv_request_id ).

    TRY.
        CASE lv_operation.
          WHEN gc_operation_ping.
            ls_response-status = `ok`.
            ls_response-message = `SAP post-installation API is available.`.

          WHEN gc_op_frontend_print_validate.
            run_frontend_print_validation(
              EXPORTING
                iv_parameters_json = iv_parameters_json
                iv_activate        = abap_false
              CHANGING
                cs_response        = ls_response ).

          WHEN gc_op_frontend_print_activate.
            run_frontend_print_validation(
              EXPORTING
                iv_parameters_json = iv_parameters_json
                iv_activate        = abap_true
              CHANGING
                cs_response        = ls_response ).

          WHEN gc_op_client_prov_validate.
            run_client_provisioning(
              EXPORTING
                iv_parameters_json = iv_parameters_json
                iv_execute         = abap_false
              CHANGING
                cs_response        = ls_response ).

          WHEN gc_op_client_prov_execute.
            run_client_provisioning(
              EXPORTING
                iv_parameters_json = iv_parameters_json
                iv_execute         = abap_true
              CHANGING
                cs_response        = ls_response ).

          WHEN gc_op_bulk_transport_validate.
            run_bulk_transport_import(
              EXPORTING
                iv_parameters_json = iv_parameters_json
                iv_import          = abap_false
              CHANGING
                cs_response        = ls_response ).

          WHEN gc_op_bulk_transport_import.
            run_bulk_transport_import(
              EXPORTING
                iv_parameters_json = iv_parameters_json
                iv_import          = abap_true
              CHANGING
                cs_response        = ls_response ).

          WHEN OTHERS.
            ls_response-status = `error`.
            ls_response-message = |Unsupported operation: { lv_operation }|.
        ENDCASE.

      CATCH cx_root INTO DATA(lx_error).
        ls_response-status = `error`.
        ls_response-message = lx_error->get_text( ).
    ENDTRY.

    ev_status = ls_response-status.
    ev_message = ls_response-message.
    ev_result_json = serialize_response( ls_response ).

  ENDMETHOD.

  METHOD initialize_response.

    rs_response-api_version = gc_api_version.
    rs_response-request_id = iv_request_id.
    rs_response-operation = iv_operation.
    rs_response-status = `error`.
    rs_response-system_id = sy-sysid.
    rs_response-client = sy-mandt.
    rs_response-user = sy-uname.
    rs_response-server_time = |{ sy-datum }{ sy-uzeit }|.

  ENDMETHOD.

  METHOD run_frontend_print_validation.

    DATA ls_parameters TYPE ty_frontend_print_parameters.
    DATA ls_config TYPE zcl_frontend_print_planner=>ty_config.
    DATA lt_plan TYPE zcl_frontend_print_planner=>tt_services.
    DATA lt_result TYPE zcl_frontend_print_runner=>tt_results.
    DATA lo_planner TYPE REF TO zcl_frontend_print_planner.
    DATA lo_runner TYPE REF TO zcl_frontend_print_runner.
    DATA lo_gateway TYPE REF TO zif_sicf_gateway.

    ls_parameters-include_optional = abap_true.

    IF iv_parameters_json IS NOT INITIAL.
      /ui2/cl_json=>deserialize(
        EXPORTING
          json        = iv_parameters_json
          pretty_name = /ui2/cl_json=>pretty_mode-camel_case
        CHANGING
          data        = ls_parameters ).
    ENDIF.

    ls_config = zcl_frontend_print_planner=>default_config( ).
    ls_config-client = sy-mandt.
    ls_config-run_user = sy-uname.
    ls_config-include_optional = ls_parameters-include_optional.

    IF ls_parameters-virtual_host IS NOT INITIAL.
      ls_config-virtual_host = ls_parameters-virtual_host.
      CONDENSE ls_config-virtual_host NO-GAPS.
    ENDIF.

    CREATE OBJECT lo_planner.
    lt_plan = lo_planner->build_plan( ls_config ).

    IF iv_activate = abap_true.
      CREATE OBJECT lo_gateway TYPE zcl_sicf_gateway.
    ENDIF.
    IF lo_gateway IS BOUND.
      CREATE OBJECT lo_runner
        EXPORTING
          io_gateway = lo_gateway.
    ELSE.
      CREATE OBJECT lo_runner.
    ENDIF.
    lt_result = lo_runner->execute(
      it_plan    = lt_plan
      iv_dry_run = xsdbool( iv_activate = abap_false ) ).

    LOOP AT lt_result INTO DATA(ls_result).
      READ TABLE lt_plan INTO DATA(ls_service) INDEX ls_result-sequence.

      APPEND VALUE #(
        sequence     = ls_result-sequence
        service_path = ls_result-service_path
        status       = ls_result-status
        message      = ls_result-message
        reason       = COND string(
          WHEN sy-subrc = 0 THEN ls_service-reason
          ELSE `` ) )
        TO cs_response-items.
    ENDLOOP.

    cs_response-status = `ok`.
    cs_response-message = COND string(
      WHEN iv_activate = abap_true
      THEN |Activation processed { lines( cs_response-items ) } service entries.|
      ELSE |Validation produced { lines( cs_response-items ) } planned service entries.| ).

  ENDMETHOD.

  METHOD run_client_provisioning.

    DATA ls_parameters TYPE ty_client_prov_parameters.
    DATA ls_config TYPE zcl_client_prov_planner=>ty_config.
    DATA lt_plan TYPE zcl_client_prov_planner=>tt_plan.
    DATA lt_results TYPE zcl_client_prov_runner=>tt_results.
    DATA lo_planner TYPE REF TO zcl_client_prov_planner.
    DATA lo_runner TYPE REF TO zcl_client_prov_runner.
    DATA lo_gateway TYPE REF TO zif_client_prov_gateway.
    DATA lv_system_type TYPE string.

    IF iv_parameters_json IS NOT INITIAL.
      /ui2/cl_json=>deserialize(
        EXPORTING
          json        = iv_parameters_json
          pretty_name = /ui2/cl_json=>pretty_mode-camel_case
        CHANGING
          data        = ls_parameters ).
    ENDIF.

    IF iv_execute = abap_true AND sy-mandt <> `000`.
      cs_response-status = `error`.
      cs_response-message = `Client provisioning execution is only allowed in client 000.`.
      RETURN.
    ENDIF.

    lv_system_type = ls_parameters-system_type.
    TRANSLATE lv_system_type TO UPPER CASE.
    CONDENSE lv_system_type NO-GAPS.
    IF lv_system_type IS INITIAL.
      lv_system_type = zcl_client_prov_planner=>gc_system_shared.
    ENDIF.

    IF ls_parameters-sid IS INITIAL.
      ls_parameters-sid = sy-sysid.
    ENDIF.

    ls_config = zcl_client_prov_planner=>default_config(
      iv_sid         = ls_parameters-sid
      iv_system_type = lv_system_type ).

    IF ls_parameters-client_from IS NOT INITIAL.
      ls_config-client_from = ls_parameters-client_from.
    ENDIF.
    IF ls_parameters-client_to IS NOT INITIAL.
      ls_config-client_to = ls_parameters-client_to.
    ENDIF.

    CREATE OBJECT lo_planner.
    lt_plan = lo_planner->build_plan( ls_config ).

    IF iv_execute = abap_true.
      CREATE OBJECT lo_gateway TYPE zcl_client_prov_gateway.
      CREATE OBJECT lo_runner
        EXPORTING
          io_gateway = lo_gateway.
    ELSE.
      CREATE OBJECT lo_runner.
    ENDIF.

    lt_results = lo_runner->execute(
      is_config          = ls_config
      it_plan            = lt_plan
      iv_dry_run         = xsdbool( iv_execute = abap_false )
      iv_update_existing = ls_parameters-update_existing ).

    LOOP AT lt_results INTO DATA(ls_result).
      APPEND VALUE #(
        sequence       = ls_result-sequence
        status         = ls_result-status
        message        = ls_result-message
        phase          = ls_result-phase
        client         = ls_result-client
        logical_system = ls_result-logical_system )
        TO cs_response-items.
    ENDLOOP.

    cs_response-status = `ok`.
    cs_response-message = COND string(
      WHEN iv_execute = abap_true
      THEN |Client provisioning executed with { lines( cs_response-items ) } result entries.|
      ELSE |Client provisioning validation produced { lines( cs_response-items ) } planned entries.| ).

  ENDMETHOD.

  METHOD run_bulk_transport_import.

    DATA ls_parameters TYPE ty_bulk_transport_parameters.
    DATA lo_config_reader TYPE REF TO zcl_json_transport_config_read.
    DATA lo_validator TYPE REF TO zcl_bulk_transport_config_vali.
    DATA lo_gateway TYPE REF TO zif_bulk_transport_gateway.
    DATA lo_runner TYPE REF TO zcl_bulk_transport_runner.
    DATA lt_results TYPE zcl_bulk_transport_runner=>tt_results.
    DATA lv_mode TYPE zcl_bulk_transport_runner=>ty_execution_mode.

    ls_parameters-stop_on_warning = abap_true.
    IF iv_parameters_json IS NOT INITIAL.
      /ui2/cl_json=>deserialize(
        EXPORTING
          json        = iv_parameters_json
          pretty_name = /ui2/cl_json=>pretty_mode-camel_case
        CHANGING
          data        = ls_parameters ).
    ENDIF.

    IF ls_parameters-config_file_path IS INITIAL.
      cs_response-status = `error`.
      cs_response-message = `A configuration file path on the SAP application server is required.`.
      RETURN.
    ENDIF.

    CREATE OBJECT lo_config_reader.
    CREATE OBJECT lo_validator.
    CREATE OBJECT lo_gateway TYPE zcl_tms_transport_gateway
      EXPORTING
        iv_system = sy-sysid.
    CREATE OBJECT lo_runner
      EXPORTING
        io_config_reader = lo_config_reader
        io_validator     = lo_validator
        io_gateway       = lo_gateway.

    lv_mode = COND #(
      WHEN iv_import = abap_true THEN zcl_bulk_transport_runner=>gc_mode_import
      ELSE zcl_bulk_transport_runner=>gc_mode_validate ).
    lt_results = lo_runner->run(
      iv_file_path       = ls_parameters-config_file_path
      iv_execution_mode  = lv_mode
      iv_stop_on_warning = ls_parameters-stop_on_warning ).

    LOOP AT lt_results INTO DATA(ls_result).
      APPEND VALUE #(
        sequence    = ls_result-sequence
        service_path = ls_result-transport_request
        client      = ls_result-client
        status      = ls_result-status
        message     = ls_result-message
        reason      = |Return code { ls_result-return_code }| )
        TO cs_response-items.
    ENDLOOP.

    cs_response-status = `ok`.
    cs_response-message = COND string(
      WHEN iv_import = abap_true
      THEN |Bulk transport import returned { lines( cs_response-items ) } entries.|
      ELSE |Bulk transport validation returned { lines( cs_response-items ) } entries.| ).

  ENDMETHOD.

  METHOD serialize_response.

    rv_result_json = /ui2/cl_json=>serialize(
      data        = is_response
      compress    = abap_true
      pretty_name = /ui2/cl_json=>pretty_mode-camel_case ).

  ENDMETHOD.

ENDCLASS.
