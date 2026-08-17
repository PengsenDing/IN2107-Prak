CLASS zcl_client_prov_planner DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    CONSTANTS:
      gc_system_exclusive          TYPE string VALUE 'EXCLUSIVE',
      gc_system_shared             TYPE string VALUE 'SHARED',
      gc_system_shared_development TYPE string VALUE 'SHAREDDEVELOPMENT',
      gc_preset_shared             TYPE string VALUE 'SHARED',
      gc_preset_development        TYPE string VALUE 'EXCLUSIVEORSHAREDDEVELOPMENT',
      gc_strategy_mass_report      TYPE string VALUE 'MASSREPORT',
      gc_strategy_sccln            TYPE string VALUE 'SCCLNMANUALSCHEDULE',
      gc_strategy_none             TYPE string VALUE 'NONE'.

    TYPES ty_client TYPE n LENGTH 3.
    TYPES ty_sid TYPE c LENGTH 3.

    TYPES:
      BEGIN OF ty_config,
        profile_id           TYPE string,
        sid                  TYPE ty_sid,
        system_type          TYPE string,
        scc4_preset          TYPE string,
        client_from          TYPE ty_client,
        client_to            TYPE ty_client,
        description_template TYPE string,
        city                 TYPE string,
        currency             TYPE c LENGTH 3,
        role                 TYPE string,
        copy_enabled         TYPE abap_bool,
        copy_strategy        TYPE string,
        mass_report          TYPE string,
        source_client        TYPE ty_client,
        copy_profile         TYPE string,
        job_user             TYPE string,
        first_start_date     TYPE d,
        first_start_time     TYPE t,
        interval_minutes     TYPE i,
        parallel_processes   TYPE i,
      END OF ty_config.

    TYPES:
      BEGIN OF ty_plan_line,
        sequence       TYPE i,
        phase          TYPE string,
        client         TYPE ty_client,
        logical_system TYPE string,
        action         TYPE string,
        details        TYPE string,
      END OF ty_plan_line.

    TYPES tt_plan TYPE STANDARD TABLE OF ty_plan_line WITH EMPTY KEY.

    CLASS-METHODS default_config
      IMPORTING
        iv_sid           TYPE ty_sid
        iv_system_type   TYPE string
      RETURNING
        VALUE(rs_config) TYPE ty_config.

    METHODS build_plan
      IMPORTING
        is_config      TYPE ty_config
      RETURNING
        VALUE(rt_plan) TYPE tt_plan.

  PRIVATE SECTION.

    METHODS add_line
      IMPORTING
        iv_phase          TYPE string
        iv_client         TYPE ty_client OPTIONAL
        iv_logical_system TYPE string OPTIONAL
        iv_action         TYPE string
        iv_details        TYPE string
      CHANGING
        ct_plan           TYPE tt_plan.

    METHODS add_validation
      IMPORTING
        is_config TYPE ty_config
      CHANGING
        ct_plan   TYPE tt_plan.

    METHODS add_scc4_preset
      IMPORTING
        is_config TYPE ty_config
        iv_client TYPE ty_client
        iv_logsys TYPE string
      CHANGING
        ct_plan   TYPE tt_plan.

    METHODS format_logical_system
      IMPORTING
        is_config        TYPE ty_config
        iv_client        TYPE ty_client
      RETURNING
        VALUE(rv_logsys) TYPE string.

ENDCLASS.


CLASS zcl_client_prov_planner IMPLEMENTATION.

  METHOD default_config.

    rs_config-profile_id           = |{ iv_system_type }-{ iv_sid }|.
    rs_config-sid                  = iv_sid.
    rs_config-system_type          = iv_system_type.
    rs_config-description_template = `Global Bike 4.2 Client`.
    rs_config-city                 = `Muenchen`.
    rs_config-currency             = `EUR`.
    rs_config-role                 = `Training/Education`.
    rs_config-copy_enabled         = abap_true.
    rs_config-copy_strategy        = gc_strategy_mass_report.
    rs_config-mass_report          = `ZS4S_CLIENT_COPY_CHAIN_GEN`.
    rs_config-source_client        = `999`.
    rs_config-copy_profile         = `SAP_ALL`.
    rs_config-job_user             = `master-adm`.
    rs_config-interval_minutes     = 10.
    rs_config-parallel_processes   = 8.

    IF iv_system_type = gc_system_shared.
      rs_config-client_from = `300`.
      rs_config-client_to   = `330`.
      rs_config-scc4_preset = gc_preset_shared.
    ELSE.
      rs_config-client_from = `300`.
      rs_config-client_to   = `304`.
      rs_config-scc4_preset = gc_preset_development.
    ENDIF.

  ENDMETHOD.

  METHOD build_plan.

    DATA lv_current TYPE i.
    DATA lv_to TYPE i.
    DATA lv_client TYPE ty_client.
    DATA lv_logsys TYPE string.
    DATA lv_offset TYPE i.

    add_validation(
      EXPORTING
        is_config = is_config
      CHANGING
        ct_plan   = rt_plan ).

    lv_current = is_config-client_from.
    lv_to      = is_config-client_to.

    WHILE lv_current <= lv_to.

      lv_client = lv_current.
      lv_logsys = format_logical_system(
        is_config = is_config
        iv_client = lv_client ).

      add_line(
        EXPORTING
          iv_phase          = `BD54`
          iv_client         = lv_client
          iv_logical_system = lv_logsys
          iv_action         = `Create logical system`
          iv_details        = |Name { lv_logsys }, description { is_config-description_template }|
        CHANGING
          ct_plan           = rt_plan ).

      add_scc4_preset(
        EXPORTING
          is_config = is_config
          iv_client = lv_client
          iv_logsys = lv_logsys
        CHANGING
          ct_plan   = rt_plan ).

      IF is_config-copy_enabled = abap_true.
        IF is_config-copy_strategy = gc_strategy_mass_report.
          lv_offset = ( lv_current - is_config-client_from ) * is_config-interval_minutes.
          add_line(
            EXPORTING
              iv_phase          = `SCCLN`
              iv_client         = lv_client
              iv_logical_system = lv_logsys
              iv_action         = `Schedule via mass copy report`
              iv_details        = |Run { is_config-mass_report } in client 000: |
                                  && |source { is_config-source_client }, target { lv_client }, |
                                  && |profile { is_config-copy_profile }, job user { is_config-job_user }, |
                                  && |first start { is_config-first_start_date } { is_config-first_start_time }, |
                                  && |offset { lv_offset } minutes, interval { is_config-interval_minutes } minutes, |
                                  && |processes { is_config-parallel_processes }|
            CHANGING
              ct_plan           = rt_plan ).
        ELSEIF is_config-copy_strategy = gc_strategy_sccln.
          lv_offset = ( lv_current - is_config-client_from ) * is_config-interval_minutes.
          add_line(
            EXPORTING
              iv_phase          = `SCCLN`
              iv_client         = lv_client
              iv_logical_system = lv_logsys
              iv_action         = `Schedule manual SCCLN task list`
              iv_details        = |Source { is_config-source_client }, target { lv_client }, |
                                  && |profile { is_config-copy_profile }, lock source client, |
                                  && |exclusive columns, processes { is_config-parallel_processes }, |
                                  && |start offset { lv_offset } minutes|
            CHANGING
              ct_plan           = rt_plan ).
        ENDIF.
      ENDIF.

      lv_current = lv_current + 1.

    ENDWHILE.

    add_line(
      EXPORTING
        iv_phase   = `MONITOR`
        iv_action  = `Monitor copy progress`
        iv_details = `Use SCC3 for copy history/current run and SM37 for scheduled STCTM_* jobs.`
      CHANGING
        ct_plan    = rt_plan ).

  ENDMETHOD.

  METHOD add_line.

    DATA ls_plan TYPE ty_plan_line.

    ls_plan-sequence       = lines( ct_plan ) + 1.
    ls_plan-phase          = iv_phase.
    ls_plan-client         = iv_client.
    ls_plan-logical_system = iv_logical_system.
    ls_plan-action         = iv_action.
    ls_plan-details        = iv_details.

    APPEND ls_plan TO ct_plan.

  ENDMETHOD.

  METHOD add_validation.

    DATA lv_role TYPE string.

    IF is_config-sid IS INITIAL.
      add_line(
        EXPORTING
          iv_phase   = `VALIDATION`
          iv_action  = `Configuration error`
          iv_details = `SID is required.`
        CHANGING
          ct_plan    = ct_plan ).
    ENDIF.

    IF is_config-client_from > is_config-client_to.
      add_line(
        EXPORTING
          iv_phase   = `VALIDATION`
          iv_action  = `Configuration error`
          iv_details = `Client range must start before it ends.`
        CHANGING
          ct_plan    = ct_plan ).
    ENDIF.

    IF is_config-scc4_preset <> gc_preset_shared
       AND is_config-scc4_preset <> gc_preset_development.
      add_line(
        EXPORTING
          iv_phase   = `VALIDATION`
          iv_action  = `Configuration error`
          iv_details = |Unknown SCC4 preset { is_config-scc4_preset }.|
        CHANGING
          ct_plan    = ct_plan ).
    ENDIF.

    lv_role = is_config-role.
    TRANSLATE lv_role TO UPPER CASE.
    CONDENSE lv_role NO-GAPS.

    IF lv_role <> `PRODUCTION`
       AND lv_role <> `LIVE`
       AND lv_role <> `TEST`
       AND lv_role <> `CUSTOMIZING`
       AND lv_role <> `DEMO`
       AND lv_role <> `TRAINING/EDUCATION`
       AND lv_role <> `SAPREFERENCE`.
      add_line(
        EXPORTING
          iv_phase   = `VALIDATION`
          iv_action  = `Configuration error`
          iv_details = |Unknown client role { is_config-role }.|
        CHANGING
          ct_plan    = ct_plan ).
    ENDIF.

    IF is_config-copy_enabled = abap_true
       AND is_config-source_client IS INITIAL.
      add_line(
        EXPORTING
          iv_phase   = `VALIDATION`
          iv_action  = `Configuration error`
          iv_details = `Source client is required when client copy is enabled.`
        CHANGING
          ct_plan    = ct_plan ).
    ENDIF.

  ENDMETHOD.

  METHOD add_scc4_preset.

    DATA lv_change_recording TYPE string.
    DATA lv_cross_client TYPE string.

    IF is_config-scc4_preset = gc_preset_development.
      lv_change_recording = `Aenderungen ohne automat. Aufzeichnung`.
      lv_cross_client     = `Aenderungen an Repository und mand.unabh. Customizing erlaubt`.
    ELSE.
      lv_change_recording = `keine Aenderungen erlaubt`.
      lv_cross_client     = `keine Aenderung von Repository- und mand.unabh. Cust.-Obj.`.
    ENDIF.

    add_line(
      EXPORTING
        iv_phase          = `SCC4`
        iv_client         = iv_client
        iv_logical_system = iv_logsys
        iv_action         = `Create client`
        iv_details        = |Description { is_config-description_template }, city { is_config-city }, |
                            && |logical system { iv_logsys }, currency { is_config-currency }, |
                            && |role { is_config-role }|
      CHANGING
        ct_plan           = ct_plan ).

    add_line(
      EXPORTING
        iv_phase          = `SCC4`
        iv_client         = iv_client
        iv_logical_system = iv_logsys
        iv_action         = `Apply SCC4 preset`
        iv_details        = |Preset { is_config-scc4_preset }: { lv_change_recording }; |
                            && |{ lv_cross_client }; Schutzstufe 0: keine Beschraenkung; |
                            && |eCATT und CATT nicht erlaubt; Wegen Mandantenkopie gesperrt false; |
                            && |Schutz gegen SAP-Upgrade false|
      CHANGING
        ct_plan           = ct_plan ).

  ENDMETHOD.

  METHOD format_logical_system.

    rv_logsys = |{ is_config-sid }CLNT{ iv_client }|.

  ENDMETHOD.

ENDCLASS.
