REPORT zclient_provisioning.

PARAMETERS:
  p_valid  RADIOBUTTON GROUP mode DEFAULT 'X',
  p_exec   RADIOBUTTON GROUP mode,
  p_upd    AS CHECKBOX DEFAULT space,
  p_conf   AS CHECKBOX DEFAULT space,
  p_sid    TYPE c LENGTH 3 DEFAULT 'S31',
  p_syst   TYPE c LENGTH 24 DEFAULT 'shared',
  p_pres   TYPE c LENGTH 32 DEFAULT 'shared',
  p_from   TYPE n LENGTH 3 DEFAULT '300',
  p_to     TYPE n LENGTH 3 DEFAULT '330',
  p_desc   TYPE c LENGTH 60 DEFAULT 'Global Bike 4.2 Client',
  p_city   TYPE c LENGTH 40 DEFAULT 'Muenchen',
  p_curr   TYPE c LENGTH 3 DEFAULT 'EUR',
  p_role   TYPE c LENGTH 40 DEFAULT 'Training/Education',
  p_copy   AS CHECKBOX DEFAULT 'X',
  p_strat  TYPE c LENGTH 24 DEFAULT 'massReport',
  p_mass   TYPE c LENGTH 40 DEFAULT 'ZS4S_CLIENT_COPY_CHAIN_GEN',
  p_src    TYPE n LENGTH 3 DEFAULT '999',
  p_prof   TYPE c LENGTH 20 DEFAULT 'SAP_ALL',
  p_jobusr TYPE c LENGTH 20 DEFAULT 'master-adm',
  p_fdate  TYPE d DEFAULT sy-datum,
  p_ftime  TYPE t DEFAULT '230000',
  p_int    TYPE i DEFAULT 10,
  p_proc   TYPE i DEFAULT 8.

AT SELECTION-SCREEN.

  IF p_exec = abap_true AND p_conf <> abap_true.
    MESSAGE 'Confirm execution before changing BD54 and SCC4' TYPE 'E'.
  ENDIF.

  IF p_exec = abap_true AND sy-mandt <> '000'.
    MESSAGE 'Execution is only allowed in client 000' TYPE 'E'.
  ENDIF.

START-OF-SELECTION.

  DATA ls_config TYPE zcl_client_prov_planner=>ty_config.
  DATA lt_plan TYPE zcl_client_prov_planner=>tt_plan.
  DATA lo_planner TYPE REF TO zcl_client_prov_planner.
  DATA lo_gateway TYPE REF TO zcl_client_prov_gateway.
  DATA lo_runner TYPE REF TO zcl_client_prov_runner.
  DATA lt_result TYPE zcl_client_prov_runner=>tt_results.

  ls_config-profile_id           = |{ p_sid }-{ p_syst }-{ p_from }-{ p_to }|.
  ls_config-sid                  = p_sid.
  ls_config-system_type          = p_syst.
  ls_config-scc4_preset          = p_pres.
  ls_config-client_from          = p_from.
  ls_config-client_to            = p_to.
  ls_config-description_template = p_desc.
  ls_config-city                 = p_city.
  ls_config-currency             = p_curr.
  ls_config-role                 = p_role.
  ls_config-copy_enabled         = p_copy.
  ls_config-copy_strategy        = p_strat.
  ls_config-mass_report          = p_mass.
  ls_config-source_client        = p_src.
  ls_config-copy_profile         = p_prof.
  ls_config-job_user             = p_jobusr.
  ls_config-first_start_date     = p_fdate.
  ls_config-first_start_time     = p_ftime.
  ls_config-interval_minutes     = p_int.
  ls_config-parallel_processes   = p_proc.

  CONDENSE ls_config-system_type NO-GAPS.
  CONDENSE ls_config-scc4_preset NO-GAPS.
  CONDENSE ls_config-copy_strategy NO-GAPS.

  CREATE OBJECT lo_planner.
  lt_plan = lo_planner->build_plan( ls_config ).

  IF p_exec = abap_true.
    CREATE OBJECT lo_gateway.
    CREATE OBJECT lo_runner
      EXPORTING
        io_gateway = lo_gateway.
  ELSE.
    CREATE OBJECT lo_runner.
  ENDIF.

  lt_result = lo_runner->execute(
    is_config          = ls_config
    it_plan            = lt_plan
    iv_dry_run         = p_valid
    iv_update_existing = p_upd ).

  IF p_exec = abap_true.
    WRITE: / 'Client provisioning execution result'.
  ELSE.
    WRITE: / 'Client provisioning validation plan'.
  ENDIF.
  WRITE: / 'Profile:', ls_config-profile_id.
  WRITE: / 'BD54 and SCC4 changes:', COND string(
    WHEN p_exec = abap_true THEN 'enabled'
    ELSE 'not executed' ).
  WRITE: / 'Client-copy jobs: manual follow-up only.'.
  SKIP.

  LOOP AT lt_result INTO DATA(ls_result).
    WRITE: / ls_result-sequence,
             ls_result-phase,
             ls_result-client,
             ls_result-logical_system,
             ls_result-status.
    WRITE: / '  ', ls_result-message.
  ENDLOOP.
