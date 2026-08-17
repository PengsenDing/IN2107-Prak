CLASS zcl_frontend_print_runner DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_result,
        sequence     TYPE i,
        service_path TYPE string,
        status       TYPE string,
        message      TYPE string,
      END OF ty_result.

    TYPES tt_results TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    METHODS constructor
      IMPORTING
        io_gateway TYPE REF TO zif_sicf_gateway OPTIONAL.

    METHODS execute
      IMPORTING
        it_plan          TYPE zcl_frontend_print_planner=>tt_services
        iv_dry_run       TYPE abap_bool DEFAULT 'X'
      RETURNING
        VALUE(rt_result) TYPE tt_results.

  PRIVATE SECTION.

    DATA mo_gateway TYPE REF TO zif_sicf_gateway.

    METHODS add_result
      IMPORTING
        iv_sequence     TYPE i
        iv_service_path TYPE string
        iv_status       TYPE string
        iv_message      TYPE string
      CHANGING
        ct_result       TYPE tt_results.

ENDCLASS.


CLASS zcl_frontend_print_runner IMPLEMENTATION.

  METHOD constructor.

    mo_gateway = io_gateway.

  ENDMETHOD.

  METHOD execute.

    DATA lv_state TYPE string.
    DATA lv_status TYPE string.
    DATA lv_with_subservices TYPE abap_bool.

    LOOP AT it_plan INTO DATA(ls_service).

      IF iv_dry_run = abap_true.
        add_result(
          EXPORTING
            iv_sequence     = ls_service-sequence
            iv_service_path = ls_service-service_path
            iv_status       = `planned`
            iv_message      = |Would activate { ls_service-service_path } using mode { ls_service-activation_mode }.|
          CHANGING
            ct_result       = rt_result ).
        CONTINUE.
      ENDIF.

      IF mo_gateway IS NOT BOUND.
        add_result(
          EXPORTING
            iv_sequence     = ls_service-sequence
            iv_service_path = ls_service-service_path
            iv_status       = `failed`
            iv_message      = `No SICF gateway is configured.`
          CHANGING
            ct_result       = rt_result ).
        CONTINUE.
      ENDIF.

      lv_state = mo_gateway->get_state(
        iv_virtual_host = ls_service-virtual_host
        iv_service_path = ls_service-service_path ).

      IF lv_state = `missing`.
        add_result(
          EXPORTING
            iv_sequence     = ls_service-sequence
            iv_service_path = ls_service-service_path
            iv_status       = `missing`
            iv_message      = `Service does not exist in the selected virtual host.`
          CHANGING
            ct_result       = rt_result ).
        CONTINUE.
      ELSEIF lv_state <> `active`
         AND lv_state <> `inactive`.
        add_result(
          EXPORTING
            iv_sequence     = ls_service-sequence
            iv_service_path = ls_service-service_path
            iv_status       = `failed`
            iv_message      = |Could not determine service state: { lv_state }.|
          CHANGING
            ct_result       = rt_result ).
        CONTINUE.
      ENDIF.

      IF lv_state = `active`.
        add_result(
          EXPORTING
            iv_sequence     = ls_service-sequence
            iv_service_path = ls_service-service_path
            iv_status       = `already_active`
            iv_message      = `Service is already active.`
          CHANGING
            ct_result       = rt_result ).
        CONTINUE.
      ENDIF.

      IF ls_service-is_optional = abap_true.
        add_result(
          EXPORTING
            iv_sequence     = ls_service-sequence
            iv_service_path = ls_service-service_path
            iv_status       = `inactive_optional`
            iv_message      = `Optional validation service is inactive; it was not activated.`
          CHANGING
            ct_result       = rt_result ).
        CONTINUE.
      ENDIF.

      lv_with_subservices = xsdbool( ls_service-activation_mode = `with_subservices` ).
      lv_status = mo_gateway->activate(
        iv_virtual_host     = ls_service-virtual_host
        iv_service_path     = ls_service-service_path
        iv_with_subservices = lv_with_subservices ).

      add_result(
        EXPORTING
          iv_sequence     = ls_service-sequence
          iv_service_path = ls_service-service_path
          iv_status       = lv_status
          iv_message      = |Gateway returned { lv_status }.|
        CHANGING
          ct_result       = rt_result ).

    ENDLOOP.

  ENDMETHOD.

  METHOD add_result.

    DATA ls_result TYPE ty_result.

    ls_result-sequence     = iv_sequence.
    ls_result-service_path = iv_service_path.
    ls_result-status       = iv_status.
    ls_result-message      = iv_message.

    APPEND ls_result TO ct_result.

  ENDMETHOD.

ENDCLASS.
