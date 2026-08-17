INTERFACE zif_bulk_transport_gateway PUBLIC.

  TYPE-POOLS abap.

  TYPES ty_request_id TYPE c LENGTH 10.
  TYPES ty_target_client TYPE c LENGTH 3.

  TYPES:
    BEGIN OF ty_import_options,
      ignore_invalid_comp_version TYPE abap_bool,
    END OF ty_import_options.

  TYPES:
    BEGIN OF ty_request_state,
      available_in_buffer TYPE abap_bool,
      imported_before     TYPE abap_bool,
      import_running      TYPE abap_bool,
      last_return_code    TYPE i,
      details             TYPE string,
    END OF ty_request_state.

  TYPES:
    BEGIN OF ty_import_result,
      return_code TYPE i,
      details     TYPE string,
    END OF ty_import_result.

  METHODS get_state
    IMPORTING
      iv_request_id    TYPE ty_request_id
      iv_target_client TYPE ty_target_client
    RETURNING
      VALUE(rs_state) TYPE ty_request_state.

  METHODS queue_request
    IMPORTING
      iv_request_id    TYPE ty_request_id
      iv_target_client TYPE ty_target_client.

  METHODS import_request
    IMPORTING
      iv_request_id    TYPE ty_request_id
      iv_target_client TYPE ty_target_client
      is_options       TYPE ty_import_options
    RETURNING
      VALUE(rs_result) TYPE ty_import_result.

ENDINTERFACE.
