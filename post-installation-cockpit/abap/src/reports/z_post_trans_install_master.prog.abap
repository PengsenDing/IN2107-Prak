*&---------------------------------------------------------------------*
*& Report Z_POST_TRANS_INSTALL_MASTER
*& Description: Unified Next-Gen Data Center Automation Dashboard
*&---------------------------------------------------------------------*
REPORT z_post_trans_install_master NO STANDARD PAGE HEADING LINE-SIZE 255.

" =====================================================================
" 1. DATA DECLARATIONS (Unified for all modules)
" =====================================================================
" For Logical Systems
DATA: lv_sysid TYPE sy-sysid, lv_sysid_low TYPE c LENGTH 3.
" For RFC/SMLG BDC Engine
DATA: lt_bdcdata TYPE TABLE OF bdcdata, ls_bdcdata TYPE bdcdata.
" For SPOOL
DATA: ls_nriv TYPE nriv.
" For ZMONTH
TYPES: BEGIN OF ty_cc, bukrs TYPE bukrs, END OF ty_cc.
DATA: lt_cc TYPE TABLE OF ty_cc, ls_cc TYPE ty_cc.
" For SICF Ping
DATA: lo_icf TYPE REF TO cl_icf_tree.

" =====================================================================
" 2. SELECTION SCREEN (The Client Dashboard)
" =====================================================================
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  SELECTION-SCREEN COMMENT /1(50) comm1.

  " Cross-Client Tasks (Run in 000)
  PARAMETERS: p_logsys AS CHECKBOX DEFAULT 'X', " BD54 & SCC4
              p_rfc    AS CHECKBOX DEFAULT 'X', " RZ12 & SMLG
              p_spool  AS CHECKBOX DEFAULT 'X', " Spool Increase
              p_ping   AS CHECKBOX DEFAULT 'X'." SICF Ping
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
  SELECTION-SCREEN COMMENT /1(50) comm2.

  " Client-Specific Task (Run in 800/999)
  PARAMETERS: p_bdls   AS CHECKBOX," BDLS Conversion
              p_zmonth AS CHECKBOX. " ZMONTH Custom Job
SELECTION-SCREEN END OF BLOCK b2.

" Initialization to set dashboard text dynamically
INITIALIZATION.
  comm1 = 'CROSS-CLIENT TASKS (Recommended to run in 000)'.
  comm2 = 'CLIENT-SPECIFIC TASKS (Run in 800 or 999)'.

  " Auto-uncheck cross-client tasks if NOT in client 000 to prevent accidents
  IF sy-mandt <> '000'.
    p_logsys = ' '. p_rfc = ' '. p_spool = ' '. p_ping = ' '.
    p_bdls = 'X'.

    " NEW LOGIC: Check specifically for client 800
    IF sy-mandt = '800'.
      p_zmonth = ' '. " Unchecked for 800
    ELSE.
      p_zmonth = 'X'. " Checked for 999 or others
    ENDIF.
  ENDIF.

" =====================================================================
" 3. MAIN EXECUTION CONTROLLER
" =====================================================================
START-OF-SELECTION.
  lv_sysid = sy-sysid.
  lv_sysid_low = sy-sysid.
  TRANSLATE lv_sysid_low TO LOWER CASE.

  WRITE: / '# STARTING UNIFIED AUTOMATION PIPELINE FOR SYSTEM:', sy-sysid.
  WRITE: / 'CURRENT CLIENT:', sy-mandt.
  WRITE: / '================================================================'.

  IF p_logsys = 'X'. PERFORM task_logical_systems. ENDIF.
  IF p_spool  = 'X'. PERFORM task_spool_increase.  ENDIF.
  IF p_ping   = 'X'. PERFORM task_enable_ping.     ENDIF.
  IF p_rfc    = 'X'. PERFORM task_rfc_smlg.        ENDIF.

  IF p_zmonth = 'X'. PERFORM task_zmonth.          ENDIF.
  IF p_bdls   = 'X'. PERFORM task_bdls_engine.     ENDIF.

  WRITE: / '================================================================'.
  WRITE: / '# PIPELINE EXECUTION COMPLETE.'.


" =====================================================================
" 4. TASK IMPLEMENTATIONS (SUBROUTINES)
" =====================================================================

*&---------------------------------------------------------------------*
FORM task_logical_systems.
  WRITE: / '-> Executing Task: Logical System Creation (BD54/SCC4)'.
  DATA: lv_logsys TYPE tbdls-logsys, lv_desc TYPE tbdlst-stext.

  CONCATENATE lv_sysid 'CLNT000' INTO lv_logsys.
  CONCATENATE 'System' lv_sysid 'Mandant 000' INTO lv_desc SEPARATED BY space.
  PERFORM check_create_assign USING lv_logsys lv_desc '000'.

  CONCATENATE lv_sysid 'CLNT800' INTO lv_logsys.
  CONCATENATE 'System' lv_sysid 'Mandant 800' INTO lv_desc SEPARATED BY space.
  PERFORM check_create_assign USING lv_logsys lv_desc '800'.

  CONCATENATE lv_sysid 'CLNT999' INTO lv_logsys.
  CONCATENATE 'System' lv_sysid 'Mandant 999' INTO lv_desc SEPARATED BY space.
  PERFORM check_create_assign USING lv_logsys lv_desc '999'.
  SKIP 1.
ENDFORM.

*&---------------------------------------------------------------------*
FORM task_bdls_engine.
  WRITE: / '-> Executing Task: BDLS Data Conversion'.
  DATA: lv_old TYPE tbdls-logsys, lv_new TYPE tbdls-logsys, lv_current TYPE t000-logsys.

  IF sy-mandt = '800' OR sy-mandt = '999'.
    CONCATENATE 'E55CLNT' sy-mandt INTO lv_old.
    CONCATENATE lv_sysid 'CLNT' sy-mandt INTO lv_new.

    " 1. Check which logical system is currently assigned to this client
    SELECT SINGLE logsys FROM t000 INTO @lv_current WHERE mandt = @sy-mandt.

    " 2. If it's already assigned to the new one, skip and state it
    IF lv_current = lv_new.
      WRITE: / '   # SKIPPED: The new logical system name', lv_new, 'is already assigned to the current client', sy-mandt.
    ELSE.
      WRITE: / '   # Mapping', lv_old, 'to', lv_new, '... please wait.'.
      SUBMIT rbdlsmap WITH old_ls = lv_old WITH new_ls = lv_new
                      WITH testrun = ' ' EXPORTING LIST TO MEMORY AND RETURN.
      WRITE: / '   # BDLS complete for client', sy-mandt.
    ENDIF.
  ELSE.
    WRITE: / '   # SKIPPED: BDLS must be run in client 800 or 999!'.
  ENDIF.
  SKIP 1.
ENDFORM.

*&---------------------------------------------------------------------*
FORM task_spool_increase.
  WRITE: / '-> Executing Task: Spool Range Increase'.
  SELECT SINGLE * FROM nriv INTO ls_nriv WHERE object = 'SPO_NUM' AND nrrangenr = '01'.
  IF sy-subrc = 0.
    ls_nriv-tonumber = '0001132000'.
    UPDATE nriv FROM ls_nriv.
    IF sy-subrc = 0.
      WRITE: / '   # Spool limit successfully extended to 0001132000!'.
    ENDIF.
  ENDIF.
  COMMIT WORK AND WAIT.
  SKIP 1.
ENDFORM.

*&---------------------------------------------------------------------*
FORM task_enable_ping.
  WRITE: / '-> Executing Task: SICF Ping Activation'.
  CREATE OBJECT lo_icf.
  TRY.
      lo_icf->activate_node( url = '/sap/bc/ping' nocheck_force_act = 'X' ).
      COMMIT WORK AND WAIT.
      WRITE: / '   # /sap/bc/ping activated successfully!'.
    CATCH cx_root.
      WRITE: / '   # SICF API Activation failed.'.
  ENDTRY.
  SKIP 1.
ENDFORM.

*&---------------------------------------------------------------------*
FORM task_zmonth.
  WRITE: / '-> Executing Task: ZMONTH Custom Job Automation'.

  DATA: lv_check TYPE bukrs.

  " 1. Define the internal table structure exactly as ZMONTH expects it
  CLEAR lt_cc.
  ls_cc-bukrs = 'DE00'. APPEND ls_cc TO lt_cc.
  ls_cc-bukrs = 'US00'. APPEND ls_cc TO lt_cc.

  " 2. Filter out company codes without a MARV period record to avoid infinite loops
  LOOP AT lt_cc INTO ls_cc.
    SELECT SINGLE bukrs FROM marv INTO lv_check WHERE bukrs = ls_cc-bukrs.
    IF sy-subrc <> 0.
      WRITE: / '   ! SKIPPED', ls_cc-bukrs, '- run MMPI once for this company code first.'.
      DELETE lt_cc WHERE bukrs = ls_cc-bukrs.
    ENDIF.
  ENDLOOP.

  " 3. Schedule jobs only if there are valid initialized company codes left
  IF lt_cc[] IS INITIAL.
    WRITE: / '   # Nothing to schedule - no company codes are initialized.'.
  ELSE.
    CALL FUNCTION 'Z_MONTHENDCLOSE_SCH_JOB'
      EXPORTING
        it_cc = lt_cc.
    WRITE: / '   # SUCCESS: Material Master Month Change Job Scheduled!'.

    CALL FUNCTION 'Z_MARKALLOW_SCH_JOB'
      EXPORTING
        it_cc = lt_cc.
    WRITE: / '   # SUCCESS: Marking Allowance Job Scheduled!'.
  ENDIF.
  SKIP 1.
ENDFORM.

*&---------------------------------------------------------------------*
FORM task_rfc_smlg.
  WRITE: / '-> Executing Task: RZ12 and SMLG Automation'.
  DATA: lv_rz12_group TYPE c LENGTH 20, lv_applserver TYPE c LENGTH 50.
  CONCATENATE 'SPACE_' lv_sysid INTO lv_rz12_group.
  CONCATENATE lv_sysid_low 'lp1_' lv_sysid '_00' INTO lv_applserver.

  " --- RZ12 ---
  CLEAR lt_bdcdata.
  PERFORM bdc_dynpro USING 'SAPMSSY0' '0120'.
  PERFORM bdc_field  USING 'BDC_OKCODE' '=CREA'.
  PERFORM bdc_dynpro USING 'SAPMSMLG' '3007'.
  PERFORM bdc_field  USING 'BDC_OKCODE' '=SAVE'.
  PERFORM bdc_field  USING 'RZLLITAB-CLASSNAME' lv_rz12_group.
  PERFORM bdc_field  USING 'RZLLITAB-APPLSERVER' lv_applserver.
  PERFORM bdc_field  USING 'ARFCQUOTAS_EXT-USE_QUOTAS' '1'.
  PERFORM bdc_field  USING 'ARFCQUOTAS_EXT-MAX_NORMAL_QUOTA' '80'.
  PERFORM bdc_dynpro USING 'SAPMSSY0' '0120'.
  PERFORM bdc_field  USING 'BDC_OKCODE' '=SAVE'.
  PERFORM bdc_dynpro USING 'SAPMSSY0' '0120'.
  PERFORM bdc_field  USING 'BDC_OKCODE' '=RETN'.
  CALL TRANSACTION 'RZ12' USING lt_bdcdata MODE 'N' UPDATE 'S'.
  WRITE: / '   # RZ12 (RFC Group Space) configured!'.

  " --- SMLG ---
  CLEAR lt_bdcdata.
  PERFORM bdc_dynpro USING 'SAPMSSY0' '0120'.
  PERFORM bdc_field  USING 'BDC_OKCODE' '=CREA'.
  PERFORM bdc_dynpro USING 'SAPMSMLG' '3002'.
  PERFORM bdc_field  USING 'BDC_OKCODE' '=SAVE'.
  PERFORM bdc_field  USING 'RZLLITAB-CLASSNAME' 'SPACE'.
  PERFORM bdc_field  USING 'RZLLITAB-APPLSERVER' lv_applserver.
  PERFORM bdc_dynpro USING 'SAPMSSY0' '0120'.
  PERFORM bdc_field  USING 'BDC_OKCODE' '=SAVE'.
  PERFORM bdc_dynpro USING 'SAPMSSY0' '0120'.
  PERFORM bdc_field  USING 'BDC_OKCODE' '=RETN'.
  CALL TRANSACTION 'SMLG' USING lt_bdcdata MODE 'N' UPDATE 'S'.
  WRITE: / '   # SMLG (Logon Group) configured!'.
  SKIP 1.
ENDFORM.

" =====================================================================
" 5. UTILITY ROUTINES (Engines)
" =====================================================================
FORM check_create_assign USING p_logsys TYPE tbdls-logsys p_desc TYPE tbdlst-stext p_client TYPE t000-mandt.
  DATA: ls_tbdls TYPE tbdls, ls_tbdlst TYPE tbdlst, lv_current TYPE t000-logsys.

  SELECT SINGLE logsys FROM tbdls INTO @DATA(lv_ext) WHERE logsys = @p_logsys.
  IF sy-subrc <> 0. ls_tbdls-logsys = p_logsys. INSERT tbdls FROM ls_tbdls. ENDIF.

  ls_tbdlst-langu = sy-langu. ls_tbdlst-logsys = p_logsys. ls_tbdlst-stext = p_desc.
  MODIFY tbdlst FROM ls_tbdlst.

  SELECT SINGLE logsys FROM t000 INTO @lv_current WHERE mandt = @p_client.
  IF sy-subrc = 0.
    IF lv_current IS INITIAL.
      UPDATE t000 SET logsys = @p_logsys WHERE mandt = @p_client.
      WRITE: / '   # Client', p_client, 'assigned to', p_logsys.
    ELSEIF lv_current = p_logsys.
      " Added skip statement for SCC4 client assignment as well
      WRITE: / '   # SKIPPED: Client', p_client, 'is already assigned to', p_logsys.
    ENDIF.
  ENDIF.
ENDFORM.

FORM bdc_dynpro USING program dynpro.
  CLEAR ls_bdcdata. ls_bdcdata-program = program. ls_bdcdata-dynpro = dynpro. ls_bdcdata-dynbegin = 'X'.
  APPEND ls_bdcdata TO lt_bdcdata.
ENDFORM.

FORM bdc_field USING fnam fval.
  CLEAR ls_bdcdata. ls_bdcdata-fnam = fnam. ls_bdcdata-fval = fval.
  APPEND ls_bdcdata TO lt_bdcdata.
ENDFORM.
