CLASS zcl_json_transport_config_read DEFINITION
PUBLIC
FINAL
CREATE PUBLIC.

PUBLIC SECTION.
    INTERFACES zif_bulk_transport_config_read.

ENDCLASS.

CLASS zcl_json_transport_config_read IMPLEMENTATION.

METHOD zif_bulk_transport_config_read~load.

DATA lv_json TYPE string.
DATA lv_line TYPE string.

OPEN DATASET iv_file_path
  FOR INPUT
  IN TEXT MODE
  ENCODING UTF-8.

IF sy-subrc <> 0.
  RAISE EXCEPTION TYPE zcx_bulk_transport
    EXPORTING
      iv_detail = |Could not open configuration file: { iv_file_path }|.
ENDIF.

DO.
  READ DATASET iv_file_path INTO lv_line.

  IF sy-subrc <> 0.
    EXIT.
  ENDIF.

  lv_json = lv_json && lv_line.
ENDDO.

CLOSE DATASET iv_file_path.

IF lv_json IS INITIAL.
  RAISE EXCEPTION TYPE zcx_bulk_transport
    EXPORTING
      iv_detail = |Configuration file is empty: { iv_file_path }|.
ENDIF.

TRY.
    /ui2/cl_json=>deserialize(
      EXPORTING
        json        = lv_json
        pretty_name = /ui2/cl_json=>pretty_mode-camel_case
      CHANGING
        data        = rs_config
    ).

  CATCH cx_root INTO DATA(lx_error).
    RAISE EXCEPTION TYPE zcx_bulk_transport
      EXPORTING
        iv_detail = |Could not parse JSON configuration: { lx_error->get_text( ) }|.
ENDTRY.

ENDMETHOD.

ENDCLASS.
