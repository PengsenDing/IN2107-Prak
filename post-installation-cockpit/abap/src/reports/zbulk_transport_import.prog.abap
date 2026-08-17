REPORT zbulk_transport_import.

TYPES ty_file_path TYPE c LENGTH 255.

PARAMETERS p_file TYPE ty_file_path
  LOWER CASE
  OBLIGATORY.

PARAMETERS:
  p_valid RADIOBUTTON GROUP mode DEFAULT 'X',
  p_import RADIOBUTTON GROUP mode.

PARAMETERS p_conf AS CHECKBOX.
PARAMETERS p_stopw AS CHECKBOX DEFAULT 'X'.
PARAMETERS p_tarsys TYPE tmscsys-sysnam DEFAULT sy-sysid.


START-OF-SELECTION.

  DATA lo_config_reader TYPE REF TO zcl_json_transport_config_read.
  DATA lo_validator TYPE REF TO zcl_bulk_transport_config_vali.
  DATA lo_gateway TYPE REF TO zif_bulk_transport_gateway.
  DATA lo_runner TYPE REF TO zcl_bulk_transport_runner.
  DATA lv_execution_mode TYPE zcl_bulk_transport_runner=>ty_execution_mode.
  DATA lt_results TYPE zcl_bulk_transport_runner=>tt_results.
  DATA ls_result TYPE zcl_bulk_transport_runner=>ty_result.
  DATA lv_file_path TYPE string.

  TRY.

      IF p_import = abap_true
         AND p_conf = abap_false.

        RAISE EXCEPTION TYPE zcx_bulk_transport
          EXPORTING
            iv_detail =
              `Import mode requires explicit confirmation`.

      ENDIF.

      CREATE OBJECT lo_config_reader.

      CREATE OBJECT lo_validator.

      CREATE OBJECT lo_gateway TYPE zcl_tms_transport_gateway
        EXPORTING
          iv_system = p_tarsys.

      CREATE OBJECT lo_runner
        EXPORTING
          io_config_reader = lo_config_reader
          io_validator     = lo_validator
          io_gateway       = lo_gateway.

      IF p_valid = abap_true.
        lv_execution_mode = zcl_bulk_transport_runner=>gc_mode_validate.
      ELSE.
        lv_execution_mode = zcl_bulk_transport_runner=>gc_mode_import.
      ENDIF.

      lv_file_path = p_file.

      lt_results = lo_runner->run(
        iv_file_path      = lv_file_path
        iv_execution_mode = lv_execution_mode
        iv_stop_on_warning = p_stopw ).

      LOOP AT lt_results INTO ls_result.

        WRITE:
          / ls_result-sequence,
            ls_result-transport_request,
            ls_result-client,
            ls_result-status,
            ls_result-return_code,
            ls_result-message.

      ENDLOOP.

    CATCH zcx_bulk_transport INTO DATA(lx_transport).

      WRITE:
        / `ERROR:`,
          lx_transport->detail.

  ENDTRY.
