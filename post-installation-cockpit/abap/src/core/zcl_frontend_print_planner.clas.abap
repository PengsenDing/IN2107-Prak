CLASS zcl_frontend_print_planner DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES:
      BEGIN OF ty_config,
        profile_id       TYPE string,
        virtual_host     TYPE string,
        client           TYPE n LENGTH 3,
        run_user         TYPE string,
        include_optional TYPE abap_bool,
      END OF ty_config.

    TYPES:
      BEGIN OF ty_service,
        sequence        TYPE i,
        virtual_host    TYPE string,
        service_path    TYPE string,
        service_name    TYPE string,
        activation_mode TYPE string,
        is_optional     TYPE abap_bool,
        expected_gb42   TYPE string,
        reason          TYPE string,
      END OF ty_service.

    TYPES tt_services TYPE STANDARD TABLE OF ty_service WITH EMPTY KEY.

    CLASS-METHODS default_config
      RETURNING
        VALUE(rs_config) TYPE ty_config.

    METHODS build_plan
      IMPORTING
        is_config      TYPE ty_config
      RETURNING
        VALUE(rt_plan) TYPE tt_services.

  PRIVATE SECTION.

    METHODS add_service
      IMPORTING
        iv_virtual_host    TYPE string
        iv_service_path    TYPE string
        iv_service_name    TYPE string
        iv_activation_mode TYPE string
        iv_optional        TYPE abap_bool
        iv_expected_gb42   TYPE string
        iv_reason          TYPE string
      CHANGING
        ct_plan            TYPE tt_services.

ENDCLASS.


CLASS zcl_frontend_print_planner IMPLEMENTATION.

  METHOD default_config.

    rs_config-profile_id       = `frontend-print-gb42`.
    rs_config-virtual_host     = `DEFAULT_HOST`.
    rs_config-client           = `000`.
    rs_config-run_user         = `master-adm`.
    rs_config-include_optional = abap_true.

  ENDMETHOD.

  METHOD build_plan.

    DATA lv_virtual_host TYPE string.

    lv_virtual_host = is_config-virtual_host.
    IF lv_virtual_host IS INITIAL.
      lv_virtual_host = `DEFAULT_HOST`.
    ENDIF.

    add_service(
      EXPORTING
        iv_virtual_host    = lv_virtual_host
        iv_service_path    = `/sap/bc/apc/sap/frontend_print`
        iv_service_name    = `frontend_print`
        iv_activation_mode = `single`
        iv_optional        = abap_false
        iv_expected_gb42   = `inactive`
        iv_reason          = `Frontend print APC endpoint; prevents HTTP 403 during empty PDF generation.`
      CHANGING
        ct_plan            = rt_plan ).

    add_service(
      EXPORTING
        iv_virtual_host    = lv_virtual_host
        iv_service_path    = `/sap/bc/bsp/sap/frontend_print`
        iv_service_name    = `frontend_print`
        iv_activation_mode = `single`
        iv_optional        = abap_false
        iv_expected_gb42   = `inactive`
        iv_reason          = `Frontend print BSP endpoint used by affected transactions.`
      CHANGING
        ct_plan            = rt_plan ).

    add_service(
      EXPORTING
        iv_virtual_host    = lv_virtual_host
        iv_service_path    = `/sap/bc/bsp/sap/system`
        iv_service_name    = `system`
        iv_activation_mode = `single`
        iv_optional        = abap_false
        iv_expected_gb42   = `inactive`
        iv_reason          = `Required BSP system service dependency.`
      CHANGING
        ct_plan            = rt_plan ).

    add_service(
      EXPORTING
        iv_virtual_host    = lv_virtual_host
        iv_service_path    = `/sap/bc/bsp/sap/public/bc`
        iv_service_name    = `bc`
        iv_activation_mode = `single`
        iv_optional        = abap_false
        iv_expected_gb42   = `inactive`
        iv_reason          = `Required public BSP dependency below /sap/bc.`
      CHANGING
        ct_plan            = rt_plan ).

    add_service(
      EXPORTING
        iv_virtual_host    = lv_virtual_host
        iv_service_path    = `/sap/public/bsp/sap`
        iv_service_name    = `sap`
        iv_activation_mode = `with_subservices`
        iv_optional        = abap_false
        iv_expected_gb42   = `inactive`
        iv_reason          = `Activate the public BSP subtree with all subservices.`
      CHANGING
        ct_plan            = rt_plan ).

    IF is_config-include_optional = abap_true.
      add_service(
        EXPORTING
          iv_virtual_host    = lv_virtual_host
          iv_service_path    = `/sap/bc/apc/sap/webgui_services`
          iv_service_name    = `webgui_services`
          iv_activation_mode = `single`
          iv_optional        = abap_true
          iv_expected_gb42   = `active`
          iv_reason          = `Usually already active in GB 4.2; keep in validation to avoid surprises.`
        CHANGING
          ct_plan            = rt_plan ).

      add_service(
        EXPORTING
          iv_virtual_host    = lv_virtual_host
          iv_service_path    = `/sap/public/bc`
          iv_service_name    = `bc`
          iv_activation_mode = `single`
          iv_optional        = abap_true
          iv_expected_gb42   = `active`
          iv_reason          = `Usually already active in GB 4.2.`
        CHANGING
          ct_plan            = rt_plan ).

      add_service(
        EXPORTING
          iv_virtual_host    = lv_virtual_host
          iv_service_path    = `/sap/public/bc/ur`
          iv_service_name    = `ur`
          iv_activation_mode = `single`
          iv_optional        = abap_true
          iv_expected_gb42   = `active`
          iv_reason          = `Usually already active in GB 4.2.`
        CHANGING
          ct_plan            = rt_plan ).
    ENDIF.

  ENDMETHOD.

  METHOD add_service.

    DATA ls_service TYPE ty_service.

    ls_service-sequence        = lines( ct_plan ) + 1.
    ls_service-virtual_host    = iv_virtual_host.
    ls_service-service_path    = iv_service_path.
    ls_service-service_name    = iv_service_name.
    ls_service-activation_mode = iv_activation_mode.
    ls_service-is_optional     = iv_optional.
    ls_service-expected_gb42   = iv_expected_gb42.
    ls_service-reason          = iv_reason.

    APPEND ls_service TO ct_plan.

  ENDMETHOD.

ENDCLASS.
