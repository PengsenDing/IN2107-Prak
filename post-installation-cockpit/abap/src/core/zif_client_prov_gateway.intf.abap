INTERFACE zif_client_prov_gateway PUBLIC.

  TYPES:
    BEGIN OF ty_client_settings,
      client         TYPE n LENGTH 3,
      logical_system TYPE string,
      description    TYPE string,
      city           TYPE string,
      currency       TYPE c LENGTH 3,
      role           TYPE string,
      preset         TYPE string,
    END OF ty_client_settings.

  METHODS get_logsys_state
    IMPORTING
      iv_logical_system TYPE string
    RETURNING
      VALUE(rv_state)   TYPE string.

  METHODS create_logsys
    IMPORTING
      iv_logical_system TYPE string
      iv_description    TYPE string
    RETURNING
      VALUE(rv_status)  TYPE string.

  METHODS get_client_state
    IMPORTING
      is_settings     TYPE ty_client_settings
    RETURNING
      VALUE(rv_state) TYPE string.

  METHODS create_client
    IMPORTING
      is_settings      TYPE ty_client_settings
    RETURNING
      VALUE(rv_status) TYPE string.

  METHODS update_client
    IMPORTING
      is_settings      TYPE ty_client_settings
    RETURNING
      VALUE(rv_status) TYPE string.

ENDINTERFACE.
