INTERFACE zif_sicf_gateway PUBLIC.

  METHODS get_state
    IMPORTING
      iv_virtual_host  TYPE string
      iv_service_path  TYPE string
    RETURNING
      VALUE(rv_state)  TYPE string.

  METHODS activate
    IMPORTING
      iv_virtual_host      TYPE string
      iv_service_path      TYPE string
      iv_with_subservices  TYPE abap_bool
    RETURNING
      VALUE(rv_status)     TYPE string.

ENDINTERFACE.
