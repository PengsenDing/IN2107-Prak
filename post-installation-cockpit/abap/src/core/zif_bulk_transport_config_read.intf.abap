INTERFACE zif_bulk_transport_config_read PUBLIC.

  " Keep all public configuration types in this interface. abapGit activates
  " interfaces before classes, so these declarations must not refer to a class.
  TYPES ty_request_id TYPE c LENGTH 10.
  TYPES ty_target_client TYPE c LENGTH 3.

  TYPES:
    BEGIN OF ty_settings,
      skip_already_imported TYPE abap_bool,
    END OF ty_settings.

  TYPES:
    BEGIN OF ty_import_options,
      ignore_invalid_comp_version TYPE abap_bool,
    END OF ty_import_options.

  TYPES:
    BEGIN OF ty_transport,
      sequence          TYPE i,
      disabled          TYPE abap_bool,
      transport_request TYPE ty_request_id,
      description       TYPE string,
      type              TYPE string,
      client            TYPE ty_target_client,
      import_options    TYPE ty_import_options,
      comment           TYPE string,
    END OF ty_transport.

  TYPES tt_transports TYPE STANDARD TABLE OF ty_transport
    WITH EMPTY KEY.

  TYPES:
    BEGIN OF ty_config,
      schema_version TYPE i,
      profile_id     TYPE string,
      profile_name   TYPE string,
      description    TYPE string,
      settings       TYPE ty_settings,
      transports     TYPE tt_transports,
    END OF ty_config.

METHODS load
IMPORTING
iv_file_path     TYPE string
RETURNING
VALUE(rs_config) TYPE ty_config.

ENDINTERFACE.
