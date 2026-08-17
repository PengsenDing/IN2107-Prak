REPORT z_user_customization.

TYPE-POOLS abap.

PARAMETERS p_init(40) TYPE c LOWER CASE.
PARAMETERS p_comp AS CHECKBOX DEFAULT 'X'.
PARAMETERS p_setpw AS CHECKBOX DEFAULT 'X'.

CONSTANTS c_bapi_change TYPE funcname VALUE 'BAPI_USER_CHANGE'.
CONSTANTS c_bapi_unlock TYPE funcname VALUE 'BAPI_USER_UNLOCK'.
CONSTANTS c_bapi_commit TYPE funcname VALUE 'BAPI_TRANSACTION_COMMIT'.
CONSTANTS c_bapi_rollback TYPE funcname VALUE 'BAPI_TRANSACTION_ROLLBACK'.

TYPES ty_name TYPE c LENGTH 30.
TYPES ty_bname TYPE c LENGTH 12.
TYPES ty_params TYPE abap_func_parmbind_tab.

TYPES: BEGIN OF ty_user_cfg,
         bname TYPE ty_bname,
         setpw TYPE c LENGTH 1,
         unlock TYPE c LENGTH 1,
       END OF ty_user_cfg.

DATA gt_users TYPE STANDARD TABLE OF ty_user_cfg.
DATA gs_user TYPE ty_user_cfg.

DATA gv_client TYPE string.
DATA gv_company_key TYPE string.
DATA gv_company_name TYPE string.
DATA gv_street TYPE string.
DATA gv_house_no TYPE string.
DATA gv_post_code TYPE string.
DATA gv_city TYPE string.
DATA gv_country TYPE string.
DATA gv_region TYPE string.
DATA gv_timezone TYPE string.
DATA gv_initial_pw TYPE string.
DATA gv_final_pw TYPE string.
DATA gv_assign_company TYPE c LENGTH 1.
DATA gv_set_passwords TYPE c LENGTH 1.
DATA gv_finalize_pw TYPE c LENGTH 1.
DATA gv_changed TYPE c LENGTH 1.
DATA gv_checked TYPE i.
DATA gv_changed_count TYPE i.

DATA gt_return TYPE STANDARD TABLE OF bapiret2.
DATA gs_return TYPE bapiret2.

FORM write_pair USING iv_key TYPE string
                      iv_value TYPE string.
  DATA lv_line TYPE string.
  CONCATENATE iv_key '=' iv_value INTO lv_line.
  WRITE / lv_line.
ENDFORM.

FORM finish USING iv_changed TYPE string
                  iv_status TYPE string
                  iv_message TYPE string.
  DATA lv_checked TYPE string.
  DATA lv_changed TYPE string.
  lv_checked = gv_checked.
  lv_changed = gv_changed_count.
  WRITE / 'RESULT_BEGIN'.
  PERFORM write_pair USING 'changed' iv_changed.
  PERFORM write_pair USING 'status' iv_status.
  PERFORM write_pair USING 'message' iv_message.
  PERFORM write_pair USING 'client' gv_client.
  PERFORM write_pair USING 'users' lv_checked.
  PERFORM write_pair USING 'updated_users' lv_changed.
  WRITE / 'RESULT_END'.
  STOP.
ENDFORM.

FORM fail USING iv_message TYPE string.
  CALL FUNCTION c_bapi_rollback.
  PERFORM finish USING 'false' 'failed' iv_message.
ENDFORM.

FORM add_param_if_exists USING iv_fm TYPE funcname
                               iv_name TYPE ty_name
                               ir_value TYPE REF TO data
                         CHANGING ct_params TYPE ty_params
                                  cv_added TYPE c.
  DATA lv_paramtype TYPE c LENGTH 1.
  DATA ls_bind TYPE abap_func_parmbind.

  cv_added = space.
  SELECT SINGLE paramtype FROM fupararef INTO lv_paramtype
    WHERE funcname = iv_fm
      AND parameter = iv_name.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  ls_bind-name = iv_name.
  CASE lv_paramtype.
    WHEN 'I'.
      ls_bind-kind = abap_func_exporting.
    WHEN 'E'.
      ls_bind-kind = abap_func_importing.
    WHEN 'C'.
      ls_bind-kind = abap_func_changing.
    WHEN 'T'.
      ls_bind-kind = abap_func_tables.
    WHEN OTHERS.
      RETURN.
  ENDCASE.
  ls_bind-value = ir_value.
  INSERT ls_bind INTO TABLE ct_params.
  IF sy-subrc = 0.
    cv_added = 'X'.
  ENDIF.
ENDFORM.

FORM bind_first USING iv_fm TYPE funcname
                      iv_a TYPE ty_name
                      iv_b TYPE ty_name
                      iv_c TYPE ty_name
                      iv_d TYPE ty_name
                      iv_e TYPE ty_name
                      ir_value TYPE REF TO data
                CHANGING ct_params TYPE ty_params
                         cv_bound TYPE c.
  DATA lv_added TYPE c LENGTH 1.

  cv_bound = space.
  IF iv_a IS NOT INITIAL.
    PERFORM add_param_if_exists USING iv_fm iv_a ir_value
      CHANGING ct_params lv_added.
    IF lv_added = 'X'. cv_bound = 'X'. RETURN. ENDIF.
  ENDIF.
  IF iv_b IS NOT INITIAL.
    PERFORM add_param_if_exists USING iv_fm iv_b ir_value
      CHANGING ct_params lv_added.
    IF lv_added = 'X'. cv_bound = 'X'. RETURN. ENDIF.
  ENDIF.
  IF iv_c IS NOT INITIAL.
    PERFORM add_param_if_exists USING iv_fm iv_c ir_value
      CHANGING ct_params lv_added.
    IF lv_added = 'X'. cv_bound = 'X'. RETURN. ENDIF.
  ENDIF.
  IF iv_d IS NOT INITIAL.
    PERFORM add_param_if_exists USING iv_fm iv_d ir_value
      CHANGING ct_params lv_added.
    IF lv_added = 'X'. cv_bound = 'X'. RETURN. ENDIF.
  ENDIF.
  IF iv_e IS NOT INITIAL.
    PERFORM add_param_if_exists USING iv_fm iv_e ir_value
      CHANGING ct_params lv_added.
    IF lv_added = 'X'. cv_bound = 'X'. RETURN. ENDIF.
  ENDIF.
ENDFORM.

FORM call_fm USING iv_fm TYPE funcname
             CHANGING ct_params TYPE ty_params
                      cv_subrc TYPE sysubrc
                      cv_error TYPE string.
  DATA lt_excepts TYPE abap_func_excpbind_tab.
  DATA ls_excp TYPE abap_func_excpbind.
  DATA lx_call TYPE REF TO cx_sy_dyn_call_error.

  CLEAR cv_error.
  ls_excp-name = 'OTHERS'.
  ls_excp-value = 99.
  INSERT ls_excp INTO TABLE lt_excepts.

  TRY.
      CALL FUNCTION iv_fm
        PARAMETER-TABLE ct_params
        EXCEPTION-TABLE lt_excepts.
      cv_subrc = sy-subrc.
    CATCH cx_sy_dyn_call_error INTO lx_call.
      cv_subrc = 98.
      cv_error = lx_call->get_text( ).
  ENDTRY.
ENDFORM.

FORM check_return USING iv_action TYPE string.
  DATA lv_message TYPE string.
  LOOP AT gt_return INTO gs_return
      WHERE type = 'E'
         OR type = 'A'
         OR type = 'X'.
    CONCATENATE iv_action gs_return-message INTO lv_message
      SEPARATED BY space.
    PERFORM fail USING lv_message.
  ENDLOOP.
ENDFORM.

FORM commit_work.
  CALL FUNCTION c_bapi_commit
    EXPORTING
      wait = 'X'.
ENDFORM.

FORM create_struct USING iv_type TYPE ty_name
                   CHANGING cr_data TYPE REF TO data.
  DATA lx_root TYPE REF TO cx_root.
  DATA lv_error TYPE string.
  TRY.
      CREATE DATA cr_data TYPE (iv_type).
    CATCH cx_root INTO lx_root.
      lv_error = lx_root->get_text( ).
      PERFORM fail USING lv_error.
  ENDTRY.
ENDFORM.

FORM set_comp USING ir_struct TYPE REF TO data
                    iv_name TYPE ty_name
                    iv_value TYPE string
              CHANGING cv_set TYPE c.
  FIELD-SYMBOLS <struct> TYPE any.
  FIELD-SYMBOLS <field> TYPE any.

  cv_set = space.
  ASSIGN ir_struct->* TO <struct>.
  IF sy-subrc <> 0. RETURN. ENDIF.
  ASSIGN COMPONENT iv_name OF STRUCTURE <struct> TO <field>.
  IF sy-subrc <> 0. RETURN. ENDIF.
  <field> = iv_value.
  cv_set = 'X'.
ENDFORM.

FORM set_x_comp USING ir_struct TYPE REF TO data
                      iv_name TYPE ty_name.
  DATA lv_set TYPE c LENGTH 1.
  PERFORM set_comp USING ir_struct iv_name 'X' CHANGING lv_set.
ENDFORM.

FORM set_alias USING ir_struct TYPE REF TO data
                     iv_value TYPE string
                     iv_a TYPE ty_name
                     iv_b TYPE ty_name
                     iv_c TYPE ty_name
                     iv_d TYPE ty_name
                     iv_e TYPE ty_name
               CHANGING cv_name TYPE ty_name.
  DATA lv_set TYPE c LENGTH 1.

  CLEAR cv_name.
  IF iv_a IS NOT INITIAL.
    PERFORM set_comp USING ir_struct iv_a iv_value CHANGING lv_set.
    IF lv_set = 'X'. cv_name = iv_a. RETURN. ENDIF.
  ENDIF.
  IF iv_b IS NOT INITIAL.
    PERFORM set_comp USING ir_struct iv_b iv_value CHANGING lv_set.
    IF lv_set = 'X'. cv_name = iv_b. RETURN. ENDIF.
  ENDIF.
  IF iv_c IS NOT INITIAL.
    PERFORM set_comp USING ir_struct iv_c iv_value CHANGING lv_set.
    IF lv_set = 'X'. cv_name = iv_c. RETURN. ENDIF.
  ENDIF.
  IF iv_d IS NOT INITIAL.
    PERFORM set_comp USING ir_struct iv_d iv_value CHANGING lv_set.
    IF lv_set = 'X'. cv_name = iv_d. RETURN. ENDIF.
  ENDIF.
  IF iv_e IS NOT INITIAL.
    PERFORM set_comp USING ir_struct iv_e iv_value CHANGING lv_set.
    IF lv_set = 'X'. cv_name = iv_e. RETURN. ENDIF.
  ENDIF.
ENDFORM.

FORM set_company USING ir_company TYPE REF TO data
                       ir_companyx TYPE REF TO data.
  DATA lv_field TYPE ty_name.

  PERFORM set_alias USING ir_company gv_company_key
    'COMPANY' 'COMPANY_ID' 'COMPANYID' 'COMPANY_NO' 'COMPANYNO'
    CHANGING lv_field.
  IF lv_field IS INITIAL.
    PERFORM fail USING 'BAPIUSCOMP has no company-key field'.
  ENDIF.
  PERFORM set_x_comp USING ir_companyx lv_field.
ENDFORM.

FORM ensure_company.
  DATA ls_company TYPE uscompany.
  DATA ls_address TYPE addr1_data.
  DATA ls_reference TYPE addr_ref.
  DATA lv_address_number TYPE ad_addrnum.
  DATA lv_returncode TYPE szad_field-returncode.
  DATA lv_handle TYPE szad_field-handle.
  DATA lv_nr_return TYPE inri-returncode.
  DATA lt_errors TYPE STANDARD TABLE OF addr_error.
  DATA lv_message TYPE string.
  DATA lv_subrc_text TYPE c LENGTH 3.
  DATA lv_company_field TYPE uscompany-company.
  DATA lv_company_object_key TYPE c LENGTH 45.

  ls_address-name1 = gv_company_name.
  ls_address-street = gv_street.
  ls_address-house_num1 = gv_house_no.
  ls_address-post_code1 = gv_post_code.
  ls_address-city1 = gv_city.
  ls_address-country = gv_country.
  ls_address-region = gv_region.
  ls_address-time_zone = gv_timezone.
  ls_address-langu = sy-langu.

  SELECT SINGLE * FROM uscompany INTO ls_company
    WHERE company = gv_company_key.
  IF sy-subrc = 0.
    lv_address_number = ls_company-addrnumber.
    CALL FUNCTION 'ADDR_UPDATE'
      EXPORTING
        address_data = ls_address
        address_number = lv_address_number
      IMPORTING
        returncode = lv_returncode
      TABLES
        error_table = lt_errors
      EXCEPTIONS
        address_not_exist = 1
        parameter_error = 2
        version_not_exist = 3
        internal_error = 4
        address_blocked = 5
        OTHERS = 6.
  ELSE.
    ls_reference-appl_table = 'USCOMPANY'.
    ls_reference-appl_field = 'ADDRNUMBER'.
    lv_company_field = gv_company_key.
    CONCATENATE sy-mandt lv_company_field
      INTO lv_company_object_key RESPECTING BLANKS.
    ls_reference-appl_key = lv_company_object_key.
    ls_reference-addr_group = 'BC01'.
    ls_reference-owner = 'X'.

    lv_handle = gv_company_key.
    CALL FUNCTION 'ADDR_INSERT'
      EXPORTING
        address_data = ls_address
        address_group = 'BC01'
        address_handle = lv_handle
      IMPORTING
        returncode = lv_returncode
      TABLES
        error_table = lt_errors
      EXCEPTIONS
        address_exists = 1
        parameter_error = 2
        internal_error = 3
        OTHERS = 4.
    IF sy-subrc <> 0 OR lv_returncode = 'E'.
      lv_subrc_text = sy-subrc.
      CONCATENATE 'ADDR_INSERT failed' lv_subrc_text
        sy-msgid sy-msgno INTO lv_message SEPARATED BY space.
      PERFORM fail USING lv_message.
    ENDIF.

    CALL FUNCTION 'ADDR_NUMBER_GET'
      EXPORTING
        address_handle = lv_handle
        address_reference = ls_reference
      IMPORTING
        address_number = lv_address_number
        returncode_numberrange = lv_nr_return
      EXCEPTIONS
        address_handle_not_exist = 1
        internal_error = 2
        parameter_error = 3
        OTHERS = 4.
    IF sy-subrc <> 0 OR lv_nr_return IS NOT INITIAL.
      lv_subrc_text = sy-subrc.
      CONCATENATE 'ADDR_NUMBER_GET failed' lv_subrc_text
        sy-msgid sy-msgno INTO lv_message SEPARATED BY space.
      PERFORM fail USING lv_message.
    ENDIF.

    CLEAR ls_company.
    ls_company-mandt = sy-mandt.
    ls_company-company = gv_company_key.
    ls_company-addrnumber = lv_address_number.
    INSERT uscompany FROM ls_company.
    IF sy-subrc <> 0.
      PERFORM fail USING 'Could not create USCOMPANY entry'.
    ENDIF.
  ENDIF.

  IF sy-subrc <> 0 OR lv_returncode = 'E'.
    CONCATENATE 'Company address creation/update failed'
      sy-msgid sy-msgno INTO lv_message SEPARATED BY space.
    PERFORM fail USING lv_message.
  ENDIF.

  CALL FUNCTION 'ADDR_MEMORY_SAVE'
    EXCEPTIONS
      address_number_missing = 1
      person_number_missing = 2
      internal_error = 3
      database_error = 4
      reference_missing = 5
      OTHERS = 6.
  IF sy-subrc <> 0.
    PERFORM fail USING 'ADDR_MEMORY_SAVE failed'.
  ENDIF.
ENDFORM.

FORM set_password_struct USING ir_password TYPE REF TO data.
  DATA lv_field TYPE ty_name.
  PERFORM set_alias USING ir_password gv_initial_pw
    'BAPIPWD' 'PASSWORD' 'PASSWD' 'PWD' ''
    CHANGING lv_field.
  IF lv_field IS INITIAL.
    PERFORM fail USING 'Could not fill BAPIPWD password structure'.
  ENDIF.
ENDFORM.

FORM set_password_x_struct USING ir_passwordx TYPE REF TO data.
  DATA lv_field TYPE ty_name.
  PERFORM set_alias USING ir_passwordx 'X'
    'BAPIPWD' 'PASSWORD' 'PASSWD' 'PWD' ''
    CHANGING lv_field.
  IF lv_field IS INITIAL.
    PERFORM fail USING 'Could not fill BAPIPWDX change structure'.
  ENDIF.
ENDFORM.

FORM change_user USING iv_user TYPE ty_bname
                       iv_do_company TYPE c
                       iv_do_password TYPE c.
  DATA lt_params TYPE ty_params.
  DATA lv_added TYPE c LENGTH 1.
  DATA lv_subrc TYPE sysubrc.
  DATA lv_error TYPE string.
  DATA lv_message TYPE string.
  DATA lr_user TYPE REF TO data.
  DATA lr_return TYPE REF TO data.
  DATA lr_company TYPE REF TO data.
  DATA lr_companyx TYPE REF TO data.
  DATA lr_password TYPE REF TO data.
  DATA lr_passwordx TYPE REF TO data.

  CLEAR gt_return.
  GET REFERENCE OF iv_user INTO lr_user.
  GET REFERENCE OF gt_return INTO lr_return.

  PERFORM add_param_if_exists USING c_bapi_change 'USERNAME' lr_user
    CHANGING lt_params lv_added.
  IF lv_added <> 'X'.
    PERFORM fail USING 'BAPI_USER_CHANGE has no USERNAME parameter'.
  ENDIF.

  IF iv_do_company = 'X'.
    PERFORM create_struct USING 'BAPIUSCOMP' CHANGING lr_company.
    PERFORM create_struct USING 'BAPIUSCOMX' CHANGING lr_companyx.
    PERFORM set_company USING lr_company lr_companyx.
    PERFORM add_param_if_exists USING c_bapi_change 'COMPANY'
      lr_company CHANGING lt_params lv_added.
    IF lv_added <> 'X'.
      PERFORM fail USING 'BAPI_USER_CHANGE has no COMPANY parameter'.
    ENDIF.
    PERFORM add_param_if_exists USING c_bapi_change 'COMPANYX'
      lr_companyx CHANGING lt_params lv_added.
    IF lv_added <> 'X'.
      PERFORM fail USING 'BAPI_USER_CHANGE has no COMPANYX parameter'.
    ENDIF.
  ENDIF.

  IF iv_do_password = 'X'.
    PERFORM create_struct USING 'BAPIPWD' CHANGING lr_password.
    PERFORM create_struct USING 'BAPIPWDX' CHANGING lr_passwordx.
    PERFORM set_password_struct USING lr_password.
    PERFORM set_password_x_struct USING lr_passwordx.
    PERFORM add_param_if_exists USING c_bapi_change 'PASSWORD'
      lr_password CHANGING lt_params lv_added.
    IF lv_added <> 'X'.
      PERFORM fail USING 'BAPI_USER_CHANGE has no PASSWORD parameter'.
    ENDIF.
    PERFORM add_param_if_exists USING c_bapi_change 'PASSWORDX'
      lr_passwordx CHANGING lt_params lv_added.
    IF lv_added <> 'X'.
      PERFORM fail USING 'BAPI_USER_CHANGE has no PASSWORDX parameter'.
    ENDIF.
  ENDIF.

  PERFORM add_param_if_exists USING c_bapi_change 'RETURN'
    lr_return CHANGING lt_params lv_added.
  PERFORM call_fm USING c_bapi_change
    CHANGING lt_params lv_subrc lv_error.
  IF lv_subrc <> 0.
    lv_message = lv_subrc.
    CONCATENATE 'BAPI_USER_CHANGE failed for' iv_user lv_message
      lv_error INTO lv_message SEPARATED BY space.
    PERFORM fail USING lv_message.
  ENDIF.
  PERFORM check_return USING 'BAPI_USER_CHANGE'.
  gv_changed = 'X'.
  gv_changed_count = gv_changed_count + 1.
ENDFORM.

FORM unlock_user USING iv_user TYPE ty_bname.
  DATA lt_params TYPE ty_params.
  DATA lv_added TYPE c LENGTH 1.
  DATA lv_subrc TYPE sysubrc.
  DATA lv_error TYPE string.
  DATA lv_message TYPE string.
  DATA lr_user TYPE REF TO data.
  DATA lr_return TYPE REF TO data.

  CLEAR gt_return.
  GET REFERENCE OF iv_user INTO lr_user.
  GET REFERENCE OF gt_return INTO lr_return.

  PERFORM add_param_if_exists USING c_bapi_unlock 'USERNAME' lr_user
    CHANGING lt_params lv_added.
  IF lv_added <> 'X'.
    PERFORM fail USING 'BAPI_USER_UNLOCK has no USERNAME parameter'.
  ENDIF.
  PERFORM add_param_if_exists USING c_bapi_unlock 'RETURN'
    lr_return CHANGING lt_params lv_added.
  PERFORM call_fm USING c_bapi_unlock
    CHANGING lt_params lv_subrc lv_error.
  IF lv_subrc <> 0.
    lv_message = lv_subrc.
    CONCATENATE 'BAPI_USER_UNLOCK failed for' iv_user lv_message
      lv_error INTO lv_message SEPARATED BY space.
    PERFORM fail USING lv_message.
  ENDIF.
  PERFORM check_return USING 'BAPI_USER_UNLOCK'.
  gv_changed = 'X'.
ENDFORM.

FORM process_user USING is_user TYPE ty_user_cfg.
  DATA lv_company TYPE c LENGTH 1.
  DATA lv_password TYPE c LENGTH 1.

  gv_checked = gv_checked + 1.
  lv_company = gv_assign_company.
  lv_password = space.
  IF gv_set_passwords = 'X' AND is_user-setpw = 'X'.
    lv_password = 'X'.
  ENDIF.

  IF lv_company = 'X' OR lv_password = 'X'.
    PERFORM change_user USING is_user-bname lv_company lv_password.
  ENDIF.

  IF is_user-unlock = 'X'.
    PERFORM unlock_user USING is_user-bname.
  ENDIF.

ENDFORM.
AT SELECTION-SCREEN OUTPUT.
  LOOP AT SCREEN.
    IF screen-name = 'P_INIT'.
      screen-invisible = '1'.
      IF p_setpw <> 'X'.
        screen-input = '0'.
      ENDIF.
      MODIFY SCREEN.
    ENDIF.
  ENDLOOP.

AT SELECTION-SCREEN.
  IF p_setpw = 'X' AND p_init IS INITIAL.
    MESSAGE 'Enter the initial password or clear Set passwords' TYPE 'E'.
  ENDIF.

START-OF-SELECTION.
  gv_client = sy-mandt.
  gv_company_key = 'SAP UCC MÜNCHEN'.
  gv_company_name = 'SAP UCC MÜNCHEN'.
  gv_street = 'Boltzmannstraße'.
  gv_house_no = '3'.
  gv_post_code = '85748'.
  gv_city = 'Garching bei München'.
  gv_country = 'DE'.
  gv_region = '09'.
  gv_timezone = 'CET'.
  gv_initial_pw = p_init.
  gv_assign_company = p_comp.
  gv_set_passwords = p_setpw.
  gv_finalize_pw = space.

  IF sy-mandt <> '000' AND sy-mandt <> '800'
      AND sy-mandt <> '999'.
    PERFORM fail USING 'Run this report only in client 000, 800, or 999'.
  ENDIF.

  IF gv_assign_company = 'X'.
    PERFORM ensure_company.
    gv_changed = 'X'.
  ENDIF.

  CLEAR gs_user.
  gs_user-bname = 'MASTER-ADM'.
  gs_user-setpw = p_setpw.
  APPEND gs_user TO gt_users.

  CLEAR gs_user.
  gs_user-bname = 'SAP*'.
  gs_user-setpw = p_setpw.
  IF sy-mandt = '800' OR sy-mandt = '999'.
    gs_user-unlock = 'X'.
  ENDIF.
  APPEND gs_user TO gt_users.

  CLEAR gs_user.
  gs_user-bname = 'DDIC'.
  gs_user-setpw = p_setpw.
  IF sy-mandt = '800' OR sy-mandt = '999'.
    gs_user-unlock = 'X'.
  ENDIF.
  APPEND gs_user TO gt_users.

  LOOP AT gt_users INTO gs_user.
    PERFORM process_user USING gs_user.
  ENDLOOP.

  IF gv_changed = 'X'.
    PERFORM commit_work.
  ENDIF.

  IF gv_changed = 'X'.
    PERFORM finish USING 'true' 'ok'
      'Adjusted company, initial passwords, and user locks'.
  ELSE.
    PERFORM finish USING 'false' 'ok'
      'No user customization changes were required'.
  ENDIF.
