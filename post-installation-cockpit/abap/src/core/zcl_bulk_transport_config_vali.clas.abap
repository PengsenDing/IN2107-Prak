CLASS zcl_bulk_transport_config_vali DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS validate
      IMPORTING
        is_config TYPE zif_bulk_transport_config_read=>ty_config.

ENDCLASS.


CLASS zcl_bulk_transport_config_vali IMPLEMENTATION.

  METHOD validate.

    DATA lt_sequences TYPE SORTED TABLE OF i
      WITH UNIQUE KEY table_line.

    DATA lt_requests TYPE SORTED TABLE OF
      zif_bulk_transport_gateway=>ty_request_id
      WITH UNIQUE KEY table_line.

    DATA lv_highest_sequence TYPE i.

    IF is_config-schema_version <> 1.
      RAISE EXCEPTION TYPE zcx_bulk_transport
        EXPORTING
          iv_detail = |Unsupported schema version: { is_config-schema_version }|.
    ENDIF.

    IF is_config-profile_id IS INITIAL.
      RAISE EXCEPTION TYPE zcx_bulk_transport
        EXPORTING
          iv_detail = `The configuration has no profileId`.
    ENDIF.

    IF is_config-transports IS INITIAL.
      RAISE EXCEPTION TYPE zcx_bulk_transport
        EXPORTING
          iv_detail = |Profile { is_config-profile_id } contains no transports|.
    ENDIF.

    LOOP AT is_config-transports INTO DATA(ls_transport).

      IF ls_transport-sequence <= 0.
        RAISE EXCEPTION TYPE zcx_bulk_transport
          EXPORTING
            iv_detail = |Invalid sequence number for transport { ls_transport-transport_request }|.
      ENDIF.

      INSERT ls_transport-sequence INTO TABLE lt_sequences.

      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE zcx_bulk_transport
          EXPORTING
            iv_detail = |Duplicate sequence number: { ls_transport-sequence }|.
      ENDIF.

      IF ls_transport-transport_request IS INITIAL.
        RAISE EXCEPTION TYPE zcx_bulk_transport
          EXPORTING
            iv_detail = |Transport at sequence { ls_transport-sequence } has no request ID|.
      ENDIF.

      IF strlen( ls_transport-client ) <> 3.

        RAISE EXCEPTION TYPE zcx_bulk_transport
            EXPORTING
                iv_detail =
                    |Transport { ls_transport-transport_request } has invalid client: { ls_transport-client }|.

      ENDIF.

      IF ls_transport-type <> `Workbench`
        AND ls_transport-type <> `Customizing`.

        RAISE EXCEPTION TYPE zcx_bulk_transport
        EXPORTING
        iv_detail =
            |Transport { ls_transport-transport_request } has unsupported type: { ls_transport-type }|.

      ENDIF.

      INSERT ls_transport-transport_request INTO TABLE lt_requests.

      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE zcx_bulk_transport
          EXPORTING
            iv_detail = |Duplicate transport request: { ls_transport-transport_request }|.
      ENDIF.

      IF ls_transport-client IS INITIAL.
        RAISE EXCEPTION TYPE zcx_bulk_transport
          EXPORTING
            iv_detail = |Transport { ls_transport-transport_request } has no target client|.
      ENDIF.

      IF ls_transport-sequence > lv_highest_sequence.
        lv_highest_sequence = ls_transport-sequence.
      ENDIF.

    ENDLOOP.

    IF lv_highest_sequence <> lines( is_config-transports ).
      RAISE EXCEPTION TYPE zcx_bulk_transport
        EXPORTING
          iv_detail = `Transport sequence must start at 1 and contain no gaps`.
    ENDIF.

  ENDMETHOD.

ENDCLASS.
