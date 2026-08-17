CLASS ltcl_postinstall_api DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    METHODS ping_returns_context FOR TESTING.
    METHODS rejects_unknown_operation FOR TESTING.
    METHODS frontend_print_is_validation_only FOR TESTING.
    METHODS client_provisioning_is_validation_only FOR TESTING.
ENDCLASS.


CLASS ltcl_postinstall_api IMPLEMENTATION.

  METHOD ping_returns_context.

    DATA lv_status TYPE string.
    DATA lv_message TYPE string.
    DATA lv_json TYPE string.

    zcl_postinstall_api=>execute(
      EXPORTING
        iv_operation   = `PING`
        iv_request_id  = `unit-test-ping`
      IMPORTING
        ev_status      = lv_status
        ev_message     = lv_message
        ev_result_json = lv_json ).

    cl_abap_unit_assert=>assert_equals(
      act = lv_status
      exp = `ok` ).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lv_json CS `unit-test-ping` ) ).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lv_json CS sy-sysid ) ).

  ENDMETHOD.

  METHOD rejects_unknown_operation.

    DATA lv_status TYPE string.
    DATA lv_message TYPE string.
    DATA lv_json TYPE string.

    zcl_postinstall_api=>execute(
      EXPORTING
        iv_operation   = `DELETE_EVERYTHING`
      IMPORTING
        ev_status      = lv_status
        ev_message     = lv_message
        ev_result_json = lv_json ).

    cl_abap_unit_assert=>assert_equals(
      act = lv_status
      exp = `error` ).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lv_message CP `Unsupported operation:*` ) ).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lv_json CS `DELETE_EVERYTHING` ) ).

  ENDMETHOD.

  METHOD frontend_print_is_validation_only.

    DATA lv_status TYPE string.
    DATA lv_message TYPE string.
    DATA lv_json TYPE string.

    zcl_postinstall_api=>execute(
      EXPORTING
        iv_operation       = `FRONTEND_PRINT_VALIDATE`
        iv_parameters_json = `{"virtualHost":"DEFAULT_HOST","includeOptional":false}`
      IMPORTING
        ev_status          = lv_status
        ev_message         = lv_message
        ev_result_json     = lv_json ).

    cl_abap_unit_assert=>assert_equals(
      act = lv_status
      exp = `ok` ).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lv_json CS `planned` ) ).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lv_message CP `Validation produced 5 planned service entries.*` ) ).

  ENDMETHOD.

  METHOD client_provisioning_is_validation_only.

    DATA lv_status TYPE string.
    DATA lv_message TYPE string.
    DATA lv_json TYPE string.

    zcl_postinstall_api=>execute(
      EXPORTING
        iv_operation       = `CLIENT_PROVISION_VALIDATE`
        iv_parameters_json = `{"sid":"Z31","systemType":"exclusive","clientFrom":"300","clientTo":"300"}`
      IMPORTING
        ev_status          = lv_status
        ev_message         = lv_message
        ev_result_json     = lv_json ).

    cl_abap_unit_assert=>assert_equals(
      act = lv_status
      exp = `ok` ).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lv_json CS `Z31CLNT300` ) ).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lv_message CP `Client provisioning validation produced *` ) ).

  ENDMETHOD.

ENDCLASS.
