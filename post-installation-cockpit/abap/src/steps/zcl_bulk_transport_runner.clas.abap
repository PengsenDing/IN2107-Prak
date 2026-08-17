CLASS zcl_bulk_transport_runner DEFINITION
PUBLIC
FINAL
CREATE PUBLIC.

PUBLIC SECTION.

TYPES ty_execution_mode TYPE c LENGTH 1.

CONSTANTS:
  gc_mode_validate TYPE ty_execution_mode VALUE 'V',
  gc_mode_import   TYPE ty_execution_mode VALUE 'I'.

TYPES:
  BEGIN OF ty_result,
    sequence          TYPE i,
    transport_request TYPE zif_bulk_transport_gateway=>ty_request_id,
    client            TYPE zif_bulk_transport_gateway=>ty_target_client,
    status            TYPE string,
    return_code       TYPE i,
    message           TYPE string,
  END OF ty_result.

TYPES tt_results TYPE STANDARD TABLE OF ty_result
  WITH EMPTY KEY.

METHODS constructor
  IMPORTING
    io_config_reader TYPE REF TO zif_bulk_transport_config_read
    io_validator     TYPE REF TO zcl_bulk_transport_config_vali
    io_gateway       TYPE REF TO zif_bulk_transport_gateway.

METHODS run
  IMPORTING
    iv_file_path      TYPE string
    iv_execution_mode TYPE ty_execution_mode
    iv_stop_on_warning TYPE abap_bool DEFAULT abap_true
  RETURNING
    VALUE(rt_results) TYPE tt_results.

PRIVATE SECTION.

DATA mo_config_reader TYPE REF TO zif_bulk_transport_config_read.
DATA mo_validator     TYPE REF TO zcl_bulk_transport_config_vali.
DATA mo_gateway       TYPE REF TO zif_bulk_transport_gateway.

ENDCLASS.

CLASS zcl_bulk_transport_runner IMPLEMENTATION.

METHOD constructor.

IF io_config_reader IS NOT BOUND.
  RAISE EXCEPTION TYPE zcx_bulk_transport
    EXPORTING
      iv_detail = `A configuration reader is required`.
ENDIF.

IF io_validator IS NOT BOUND.
  RAISE EXCEPTION TYPE zcx_bulk_transport
    EXPORTING
      iv_detail = `A configuration validator is required`.
ENDIF.

IF io_gateway IS NOT BOUND.
  RAISE EXCEPTION TYPE zcx_bulk_transport
    EXPORTING
      iv_detail = `A transport gateway is required`.
ENDIF.

mo_config_reader = io_config_reader.
mo_validator     = io_validator.
mo_gateway       = io_gateway.

ENDMETHOD.

METHOD run.

  IF iv_execution_mode <> gc_mode_validate
     AND iv_execution_mode <> gc_mode_import.

    RAISE EXCEPTION TYPE zcx_bulk_transport
      EXPORTING
        iv_detail = |Unsupported execution mode: { iv_execution_mode }|.

  ENDIF.

  DATA(ls_config) = mo_config_reader->load(
    iv_file_path = iv_file_path
  ).

  mo_validator->validate(
    is_config = ls_config
  ).

  DATA(lt_transports) = ls_config-transports.

  SORT lt_transports BY sequence ASCENDING.

  DATA lt_active_transports
  TYPE zif_bulk_transport_config_read=>tt_transports.

LOOP AT lt_transports INTO DATA(ls_transport).

  IF ls_transport-disabled = abap_true.

    APPEND VALUE #(
      sequence          = ls_transport-sequence
      transport_request = ls_transport-transport_request
      client            = ls_transport-client
      status            = `DISABLED`
      message           = `Transport is disabled in the configuration`
    ) TO rt_results.

    CONTINUE.

  ENDIF.

  APPEND ls_transport TO lt_active_transports.

ENDLOOP.

LOOP AT lt_active_transports INTO ls_transport.

  DATA(ls_state) = mo_gateway->get_state(
    iv_request_id    = ls_transport-transport_request
    iv_target_client = ls_transport-client
  ).

  IF ls_state-import_running = abap_true.

    RAISE EXCEPTION TYPE zcx_bulk_transport
      EXPORTING
        iv_detail =
          |An import is already running for transport { ls_transport-transport_request }|.

  ENDIF.

  IF ls_state-available_in_buffer = abap_false
     AND ls_state-imported_before = abap_false
     AND iv_execution_mode = gc_mode_import.

    mo_gateway->queue_request(
      iv_request_id    = ls_transport-transport_request
      iv_target_client = ls_transport-client
    ).

    ls_state = mo_gateway->get_state(
      iv_request_id    = ls_transport-transport_request
      iv_target_client = ls_transport-client
    ).

  ENDIF.

  IF ls_state-available_in_buffer = abap_false
     AND ls_state-imported_before = abap_false
     AND iv_execution_mode = gc_mode_import.

    RAISE EXCEPTION TYPE zcx_bulk_transport
      EXPORTING
        iv_detail =
          |Transport { ls_transport-transport_request } is not available for import: { ls_state-details }|.

  ENDIF.

  IF ls_state-imported_before = abap_true
     AND ls_state-last_return_code >= 6.

    RAISE EXCEPTION TYPE zcx_bulk_transport
      EXPORTING
        iv_detail =
          |Transport { ls_transport-transport_request } has a previous unresolved return code { ls_state-last_return_code }|.

  ENDIF.

ENDLOOP.

IF iv_execution_mode = gc_mode_validate.

  LOOP AT lt_active_transports INTO ls_transport.

    ls_state = mo_gateway->get_state(
      iv_request_id    = ls_transport-transport_request
      iv_target_client = ls_transport-client
    ).

    IF ls_state-imported_before = abap_true.

      APPEND VALUE #(
        sequence          = ls_transport-sequence
        transport_request = ls_transport-transport_request
        client            = ls_transport-client
        status            = `ALREADY_IMPORTED`
        return_code       = ls_state-last_return_code
        message           = ls_state-details
      ) TO rt_results.

    ELSEIF ls_state-available_in_buffer = abap_true.

      APPEND VALUE #(
        sequence          = ls_transport-sequence
        transport_request = ls_transport-transport_request
        client            = ls_transport-client
        status            = `READY`
        message           = `Transport is available for import`
      ) TO rt_results.

    ELSE.

      APPEND VALUE #(
        sequence          = ls_transport-sequence
        transport_request = ls_transport-transport_request
        client            = ls_transport-client
        status            = `NOT_AVAILABLE`
        message           = ls_state-details
      ) TO rt_results.

    ENDIF.

  ENDLOOP.

  RETURN.

ENDIF.

LOOP AT lt_active_transports INTO ls_transport.

  ls_state = mo_gateway->get_state(
    iv_request_id    = ls_transport-transport_request
    iv_target_client = ls_transport-client
  ).

  IF ls_state-imported_before = abap_true.

    IF ls_config-settings-skip_already_imported = abap_true.

      APPEND VALUE #(
        sequence          = ls_transport-sequence
        transport_request = ls_transport-transport_request
        client            = ls_transport-client
        status            = `SKIPPED`
        return_code       = ls_state-last_return_code
        message           = `Transport was already imported`
      ) TO rt_results.

      CONTINUE.

    ENDIF.

    EXIT.

  ENDIF.

    DATA(ls_import_options) =
    VALUE zif_bulk_transport_gateway=>ty_import_options(
      ignore_invalid_comp_version =
        ls_transport-import_options-ignore_invalid_comp_version
    ).

  DATA(ls_import_result) = mo_gateway->import_request(
    iv_request_id    = ls_transport-transport_request
    iv_target_client = ls_transport-client
    is_options       = ls_import_options
  ).

  IF ls_import_result-return_code = 0.

    APPEND VALUE #(
      sequence          = ls_transport-sequence
      transport_request = ls_transport-transport_request
      client            = ls_transport-client
      status            = `IMPORTED`
      return_code       = ls_import_result-return_code
      message           = ls_import_result-details
    ) TO rt_results.

    CONTINUE.

  ENDIF.

    IF ls_import_result-return_code = 4.

    APPEND VALUE #(
      sequence          = ls_transport-sequence
      transport_request = ls_transport-transport_request
      client            = ls_transport-client
      status            = `WARNING`
      return_code       = ls_import_result-return_code
      message           = ls_import_result-details
    ) TO rt_results.

    IF iv_stop_on_warning = abap_true.

        EXIT.

    ENDIF.

    CONTINUE.

  ENDIF.

    APPEND VALUE #(
    sequence          = ls_transport-sequence
    transport_request = ls_transport-transport_request
    client            = ls_transport-client
    status            = `ERROR`
    return_code       = ls_import_result-return_code
    message           = ls_import_result-details
  ) TO rt_results.

  RAISE EXCEPTION TYPE zcx_bulk_transport
    EXPORTING
      iv_detail =
        |Transport { ls_transport-transport_request } failed with return code { ls_import_result-return_code }|.

ENDLOOP.

ENDMETHOD.

ENDCLASS.
