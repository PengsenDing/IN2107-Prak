CLASS zcl_sicf_gateway DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    INTERFACES zif_sicf_gateway.

ENDCLASS.


CLASS zcl_sicf_gateway IMPLEMENTATION.

  METHOD zif_sicf_gateway~get_state.

    DATA lv_active TYPE icfactive.
    DATA lv_host TYPE icfvirhost-icf_name.
    DATA lv_hostnumber TYPE icfhostnum.
    DATA lv_nodeguid TYPE icfnodguid.
    DATA lv_urlsuffix TYPE icfredurl.

    lv_host = iv_virtual_host.
    TRANSLATE lv_host TO UPPER CASE.

    SELECT SINGLE hostnumber
      FROM icfvirhost
      INTO lv_hostnumber
      WHERE icf_name = lv_host.

    IF sy-subrc <> 0.
      rv_state = `failed`.
      RETURN.
    ENDIF.

    CALL METHOD cl_icf_tree=>if_icf_tree~service_from_url
      EXPORTING
        hostnumber     = lv_hostnumber
        url            = iv_service_path
        authority_check = abap_true
      IMPORTING
        icfnodguid     = lv_nodeguid
        icfactive      = lv_active
        urlsuffix      = lv_urlsuffix
      EXCEPTIONS
        wrong_application     = 1
        no_application        = 2
        not_allow_application = 3
        wrong_url             = 4
        no_authority          = 5
        OTHERS                = 6.

    IF sy-subrc = 5.
      rv_state = `failed`.
    ELSEIF sy-subrc <> 0
       OR lv_nodeguid IS INITIAL
       OR lv_urlsuffix IS NOT INITIAL.
      rv_state = `missing`.
    ELSEIF lv_active = abap_true.
      rv_state = `active`.
    ELSE.
      rv_state = `inactive`.
    ENDIF.

  ENDMETHOD.

  METHOD zif_sicf_gateway~activate.

    DATA lv_state TYPE string.

    CALL FUNCTION 'HTTP_ACTIVATE_NODE'
      EXPORTING
        url                      = iv_service_path
        hostname                 = iv_virtual_host
        expand                   = iv_with_subservices
      EXCEPTIONS
        node_not_existing        = 1
        enqueue_error            = 2
        no_authority             = 3
        url_and_nodeguid_space   = 4
        url_and_nodeguid_fill_in = 5
        OTHERS                   = 6.

    IF sy-subrc <> 0.
      rv_status = `failed`.
      RETURN.
    ENDIF.

    COMMIT WORK AND WAIT.

    lv_state = me->zif_sicf_gateway~get_state(
      iv_virtual_host = iv_virtual_host
      iv_service_path = iv_service_path ).

    IF lv_state <> `active`.
      rv_status = `failed`.
      RETURN.
    ENDIF.

    IF iv_with_subservices = abap_true.
      rv_status = `activated_with_subservices`.
    ELSE.
      rv_status = `activated`.
    ENDIF.

  ENDMETHOD.

ENDCLASS.
