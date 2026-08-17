"""SAP connectivity config section: base aggregate job launcher + Manual Configurations.

This module is self-contained on purpose: it does not import anything from
app.py (the report launcher is passed in as a parameter instead), so it can
be dropped anywhere in the app - or moved between files - without dragging
dependencies along. To reposition this whole section in app.py, just move
the two-line call:

    st.markdown("---")
    render_connectivity_config(config, render_sap_report_launcher)

to wherever it should appear, and remove it from its old spot.

Formatting follows the WP2 convention: every manual procedure lives inside
a bordered `st.container`, and every individual step (or small group of
related steps) is collapsed into its own `st.expander` so the page stays
scannable. Known errors / troubleshooting notes get their own expanders as
well, clearly labelled "Known error: ...".
"""

from __future__ import annotations

from typing import Any, Callable

import streamlit as st


def render_connectivity_config(
    config: dict[str, Any],
    render_sap_report_launcher: Callable[..., None],
) -> None:
    """Render the full SAP connectivity config section: the automated base aggregate job
    launcher, followed by every step that isn't automated by this dashboard.

    `render_sap_report_launcher` is passed in from app.py (rather than
    imported) to avoid a circular import between the two modules.
    """
    render_sap_report_launcher(
        config,
        title="Execute Core System Configuration",
        default_report="Z_POST_TRANS_INSTALL_MASTER",
        description=(
            "Bundles logical systems (BD54/SCC4), RFC group maintenance "
            "(RZ12/SMLG), SICF ping, spool range increase, and month-end "
            "automation in one report. Choose which checkboxes to run on "
            "the selection screen — cross-client tasks require client 000."
        ),
        key_prefix="post_install_master",
    )

    st.markdown("---")
    st.header("Manual Configurations")
    st.caption("After executing the core system configuration. These steps must be completed manually.")

    # ------------------------------------------------------------------
    # SNOTE Connection Configuration
    # ------------------------------------------------------------------
    with st.container(border=True):
        st.subheader("SNOTE Connection Configuration")
        st.caption(
            "Sets up the security certificates and connections required for the "
            "SAP system to communicate with the SAP Support Backbone."
        )

        with st.expander("1. Certificate configuration (Transaction STRUST)", expanded=False):
            st.markdown(
                """
The first major phase involves setting up the correct security certificates so your SAP system can securely communicate with the SAP Support Backbone.

* Log in to System client 000 and open transaction `STRUST`.
* Double-click on the "SSL client SSL Client (Standard)" container.
                """
            )
            st.image("images/sap_connectivity/snote/snote_1.png")
            st.markdown(
                """
In this case download all root certificates required by SAP (also available on NFS: `/global/shared/SSL SAP Backbone`):

[Backbone.zip](https://collab.dvb.bayern/download/attachments/67919499/Backbone.zip?version=1&modificationDate=1746813631310&api=v2)

* If an SSL client PSE container already exists, you must delete it first and then create a new one.
                """
            )
            st.image("images/sap_connectivity/snote/snote_2.png")
            st.markdown(
                """
* If no PSE exists (indicated by a red cross), right-click on "SSL client SSL Client (Standard)", select "Create PSE", and accept the default settings.
                """
            )
            st.image("images/sap_connectivity/snote/snote_3.png")
            st.image("images/sap_connectivity/snote/snote_4.png")
            st.markdown(
                """
* Change to Edit mode → Import Certificate
                """
            )
            st.image("images/sap_connectivity/snote/snote_5.png")
            st.markdown(
                """
* Import all required root certificates downloaded from SAP (such as VeriSign, Baltimore CyberTrust, and DigiCert) into this container.
                """
            )
            st.image("images/sap_connectivity/snote/snote_6.png")
            st.image("images/sap_connectivity/snote/snote_7.png")
            st.markdown(
                """
* Click on "Add to Certificate List" and save your changes.
                """
            )
            st.image("images/sap_connectivity/snote/snote_8.png")
            st.markdown(
                """
* Import all certificates → Result
                """
            )
            st.image("images/sap_connectivity/snote/snote_9.png")
            st.markdown(
                """
* If you are operating on an S/4HANA 2020 system or newer, you must repeat all of these exact steps for the "SSL client SSL Client (Anonym)" container as well.
                """
            )

        with st.expander("2. Generate the tasklist (Transaction STC01)", expanded=False):
            st.markdown(
                """
Once the certificates are in place, you need to run an automated configuration task list.

* Open transaction `STC01`.
* Generate and start the tasklist named `SAP_BASIS_CONFIG_OSS_COMM`.
                """
            )
            st.image("images/sap_connectivity/snote/snote_10.png")
            st.image("images/sap_connectivity/snote/snote_11.png")

        with st.expander("3. Update connection credentials (Transaction SM59)", expanded=False):
            st.markdown(
                """
After the task list has finished executing, you must manually update the connection credentials.

* Open transaction `SM59`.
* You will need to update three specific RFC destinations: `SAP-SUPPORT_PORTAL`, `SAP-SUPPORT_NOTE_DOWNLOAD`, and `SAP-SUPPORT_PARCELBOX`.
                """
            )
            st.image("images/sap_connectivity/snote/snote_12.png")
            st.markdown(
                """
* For the note download and parcelbox destinations, enter the S-User (the approved SAP support technical user) and password under the Basic Authentication settings.
* Save the password and ensure the "PW Status" changes to reflect that it is saved and not initial.
                """
            )
            st.image("images/sap_connectivity/snote/snote_13.png")
            st.image("images/sap_connectivity/snote/snote_14.png")
            st.markdown(
                """
* For the `SAP-SUPPORT_PORTAL` destination, ensure you maintain the language as EN and the client as 001 before saving.
                """
            )
            st.image("images/sap_connectivity/snote/snote_15.png")

        with st.expander(
            "Known error: No P-Users (tasklist SAP_BASIS_CONFIG_OSS_COMM)", expanded=False
        ):
            st.markdown(
                """
* Run a connection test (Verbindungstest) for the destinations; you should ideally receive a Status HTTP-Response of 200.
* Known errors in SAP_BASIS_CONFIG_OSS_COMM
* No P-users
                """
            )
            st.image("images/sap_connectivity/snote/snote_16.png")
            st.markdown(
                """
* Fill parameters:
                """
            )
            st.image("images/sap_connectivity/snote/snote_17.png")
            st.markdown(
                """
* Enter S-User and Password (see Keepass). Save the window.
                """
            )
            st.image("images/sap_connectivity/snote/snote_18.png")
            st.markdown(
                """
* After that restart the Taskrun.
                """
            )
            st.image("images/sap_connectivity/snote/snote_19.png")

        with st.expander("Known error: No certificate list", expanded=False):
            st.markdown(
                """
* No certificate-List
                """
            )
            st.image("images/sap_connectivity/snote/snote_20.png")
            st.markdown(
                """
* This error occurs, when you either forgot to import any or all of the above mentioned SSL-Certificates in STRUST, or when you didn't double-click on the "SSL client SSL Client (Standard)" container and therefore imported the certificates in the wrong container.
* Go to STRUST, double-click on "SSL client SSL Client (Standard)" and import all above mentioned certificates. If the error still occurs, delete the "SSL client SSL Client (Standard)" PSE container and start with a new one. Of course you have to upload all certificates in this new container too.
* Sometimes, you also have to add all the certificates to the "SSL-Client SSL-Client (Anonym)" Container, again by double-Clicking and uploading all certificates into it.
                """
            )

        with st.expander("Known error: Destination HTTP response errors", expanded=False):
            st.markdown(
                """
* Destination Errors
* Sometimes you get in the fifth step an error from type "Destination SAP* - HTTP Response
                """
            )
            st.image("images/sap_connectivity/snote/snote_21.png")
            st.markdown(
                """
* This error is due to missing technical user information within the respective Destination.
* Go to Transaction SM59 and search for the respective Destination:
                """
            )
            st.image("images/sap_connectivity/snote/snote_22.png")
            st.markdown(
                """
* Double click on the destination, activate Change mode and switch to "Login & Security".
* Here, enter the user <SAP_SUPPORT_USER> and Password (in Keepass) into the red marked fields. After that, click on save.
                """
            )
            st.image("images/sap_connectivity/snote/snote_23.png")
            st.markdown(
                """
* Now click on Test connection (Verbindungstest). Here you should get a Status 200 result.
                """
            )
            st.image("images/sap_connectivity/snote/snote_24.png")

        with st.expander("Known error: S-User locked", expanded=False):
            st.markdown(
                """
* S-User locked
* Symptom: When you start the Connection Test in SAP-SUPPORT_PARCELBOX, the system asks for additional login data.
                """
            )
            st.image("images/sap_connectivity/snote/snote_25.jpg")
            st.markdown(
                """
* This error arises, when the technical S-User <SAP_SUPPORT_USER> is locked.
* Go to SAP for me an into the user management and unlock <SAP_SUPPORT_USER>. If this does not work, contact the SAP Support.
                """
            )

        with st.expander("Known error: TLS protocol version not enabled", expanded=False):
            st.markdown(
                """
* TLS-Protokollversion
* Symptom: Step two fails with the error message "BEST-Option für höchste TLS-Protokollversion nicht aktiviert, >117<>0000 0111 0101<"
                """
            )
            st.image("images/sap_connectivity/snote/snote_26.png")
            st.markdown("**Solution:**")
            st.markdown(
                "You must enter new security parameters to your instance profile "
                "`<SID>_D<InstanceNumber>_<hostname>`:"
            )
            st.code(
                "ssl/client_ciphersuites    150:PFS:HIGH::EC_P256:EC_HIGH\n"
                "ssl/ciphersuites           135:PFS:HIGH::EC_P256:EC_HIGH",
                language="text",
            )
            st.markdown(
                """
* Enter the new parameters and save the changed profile.
                """
            )
            st.image("images/sap_connectivity/snote/snote_27.png")
            st.markdown(
                """
* After that, restart the application server.
                """
            )

    # ------------------------------------------------------------------
    # Deactivate Job CRBPA_DC_BGR
    # ------------------------------------------------------------------
    with st.container(border=True):
        st.subheader("Deactivate Job CRBPA_DC_BGR")

        with st.expander("1–2. Open SJOBREPO and run without filters", expanded=False):
            st.markdown(
                "1. Log in via SAP GUI on the system in question with the user "
                "`master-adm` on client 000 and start the transaction `SJOBREPO`."
            )
            st.image("images/sap_connectivity/job/job1.png")
            st.markdown("2. Select **Run** without filling anything out.")
            st.image("images/sap_connectivity/job/job2.png")

        with st.expander("3–4. Select and disable job CRBPA_DC_BGR", expanded=False):
            st.markdown(
                "3. Scroll down the list until you find the job `CRBPA_DC_BGR` "
                "and mark it with a checkmark."
            )
            st.image("images/sap_connectivity/job/job3.png")
            st.markdown(
                "4. Now select the button **Disable job def. in all clients** (Ctrl+F2)."
            )
            st.image("images/sap_connectivity/job/job4.png")

        with st.expander("5–6. Confirm the prompts", expanded=False):
            st.markdown("5. In the next window, select **Yes**.")
            st.image("images/sap_connectivity/job/job5.png")
            st.markdown("6. Select **Yes** again.")
            st.image("images/sap_connectivity/job/job6.png")

        with st.expander("7–9. Create the transport order", expanded=False):
            st.markdown("7. Create a new transport order:")
            st.image("images/sap_connectivity/job/job7.png")
            st.markdown('8. Select **"Workbench Order"** as the type.')
            st.image("images/sap_connectivity/job/job8.png")
            st.markdown('9. Name the job **"Deactivation Job CRBPA_DC_BGR"**.')
            st.image("images/sap_connectivity/job/job9.png")

        with st.expander("10–11. Save and verify deactivation", expanded=False):
            st.markdown("10. Select the green tick.")
            st.image("images/sap_connectivity/job/job10.png")
            st.markdown(
                '11. Now the information **"Technical job definition deactivated"** '
                "should be displayed."
            )
            st.image("images/sap_connectivity/job/job11.png")

        st.markdown(
            "This means that you have successfully scheduled job CRBPA_DC_BGR and "
            "the messages should no longer be displayed in the log in transaction SM21."
        )

    # ------------------------------------------------------------------
    # Manage RFC Connections
    # ------------------------------------------------------------------
    with st.container(border=True):
        st.subheader("Manage RFC Connections")
        st.caption(
            "According to the official guide, this task is split into Connection "
            "Creation and Connection Routing."
        )

        with st.expander("1. Create the connections (Transaction SM59)", expanded=False):
            st.markdown(
                "* Open transaction `SM59` and create two new ABAP connections "
                "(Type 3) named `FINBASIS_000` and `FINBASIS_999`."
            )
            st.image("images/sap_connectivity/rfc/rfc_1.png")
            st.image("images/sap_connectivity/rfc/rfc_2.png")
            st.markdown(
                """
* In the "Login and Security" tab, you must configure them with:
    * Language: German
    * Client: 000 and 999 respectively
    * User: `MASTER-ADM`
    * Password: The master password.
                """
            )
            st.image("images/sap_connectivity/rfc/rfc_3.png")
            st.image("images/sap_connectivity/rfc/rfc_4.png")
            st.markdown(
                "* Cleanup: Delete any old RFC connections starting with `E55` "
                "(leftover from the UCC Magdeburg system export)."
            )
            st.image("images/sap_connectivity/rfc/rfc_5.png")

        with st.expander(
            "2. Map the routing tables (FINB_TR_DEST & MDG_TR_DEST)", expanded=False
        ):
            st.markdown(
                '* Open transaction `FINB_TR_DEST`, click "New Entries", and map '
                "Client 000 to `FINBASIS_000`, and Client 999 to `FINBASIS_999`."
            )
            st.image("images/sap_connectivity/rfc/rfc_6.png")
            st.markdown(
                '* Open transaction `MDG_TR_DEST`, click "New Entries", and map '
                "Client 000 to `FINBASIS_000`, and Client 999 to `FINBASIS_999`."
            )
            st.image("images/sap_connectivity/rfc/rfc_7.png")

    # ------------------------------------------------------------------
    # SLD Configuration
    # ------------------------------------------------------------------
    st.subheader("SLD Configuration")

    with st.container(border=True):
        st.subheader("Part 1: SLD API Customization (SLDAPICUST)")

        with st.expander("1. Maintain the SLD destination entry", expanded=False):
            st.markdown(
                """
1. Log into Client 000 and open transaction `/nSLDAPICUST`.
2. Switch to edit mode by clicking the Display/Change (Glasses and Pen 👓✏️) icon.
3. Click the New Entries button (usually a blank page icon).
4. Fill in the new row exactly as you noted:
    1. Alias: `UCC_SLD`
    2. Host: `sldlp1.in.tum.de`
    3. Port: `50000`
    4. User: `SLD_CL_SLD`
    5. Password: the password from the approved secret store
5. Click Save 💾.
                """
            )
            st.image("images/sap_connectivity/sld/sld_1.png")

        with st.expander("2. Test the connection", expanded=False):
            st.markdown(
                """
6. Now, the moment of truth: Highlight the newly created row by clicking the gray square on the far left.
7. Click the Test button (usually a small computer or lightning bolt icon).
                """
            )
            st.image("images/sap_connectivity/sld/sld_2.png")

    with st.container(border=True):
        st.subheader("Part 2: The Heartbeat Configuration (RZ70)")

        with st.expander("1. Configure the gateway and start data collection", expanded=False):
            st.markdown(
                """
1. Log into Client 000 and open transaction `/nRZ70`.
2. Locate the SLD Bridge: Gateway Information section on the screen.
3. Enter the Host `sldlp1.in.tum.de`.
4. Enter the Service `sapgw01`.
5. Click the Save (Floppy Disk) icon at the top of the screen to lock in the target.
6. Click the Start Data Collection button (the icon that looks like a play button or two overlapping pages with an activation symbol).
7. A prompt will appear asking if you want to start the data collection. Click Yes.
                """
            )
            st.image("images/sap_connectivity/sld/sld_3.png")

    # ------------------------------------------------------------------
    # SAP Fiori Configuration
    # ------------------------------------------------------------------
    st.subheader("SAP Fiori Configuration")

    with st.container(border=True):
        st.subheader("Step 1: Configure the ushell Node (Login Screen Customization)")

        with st.expander("1–3. Navigate to the ushell node in SICF", expanded=False):
            st.markdown("1. Log into Client 000 and open transaction `/nSICF`.")
            st.markdown('2. Leave the "Hierarchy Type" as SERVICE and click Execute (F8).')
            st.image("images/sap_connectivity/fiori/fiori_1.png")
            st.markdown(
                "3. In the tree on the left, navigate down this exact path: "
                "`default_host -> sap -> bc -> ui5_ui5 -> ui2 -> ushell`"
            )
            st.image("images/sap_connectivity/fiori/fiori_2.png")

        with st.expander("4–8. Enter edit mode and configure the error page", expanded=False):
            st.markdown(
                "4. Double-click the ushell node to open it, and click the "
                "Display/Change (pencil) icon at the top to enter Edit Mode."
            )
            st.markdown("5. Switch to the Error Pages (Fehlerseiten) tab.")
            st.image("images/sap_connectivity/fiori/fiori_3.png")
            st.markdown(
                '6. Scroll down to the bottom. Under "System Logon" (Systemanmeldung), '
                "click the Configuration button."
            )
            st.markdown(
                '7. A popup will appear. Select the radio button for "Define '
                'Service-Specific Settings" (Definiere service-spezifische Einstellungen).'
            )
            st.markdown(
                """
8. Check the boxes for:
    * Client (Mandant)
    * Language (Sprache)
    * Switch Off Default Framebust (Default framebust ausschalten)
                """
            )

        with st.expander(
            "9–11. Save with a transport request and set protocol selection", expanded=False
        ):
            st.markdown(
                '9. Click the Green Checkmark. A prompt for a Transport Request will '
                'appear. Create a new one (e.g., "Fiori Customization") and hit the '
                "green checkmark again."
            )
            st.image("images/sap_connectivity/fiori/fiori_4.png")
            st.markdown(
                '10. Back on the main screen, find Protocol Selection (Protokollwahl) '
                'and set it to "Do Not Switch" (Nicht umschalten).'
            )
            st.image("images/sap_connectivity/fiori/fiori_5.png")
            st.markdown("11. Click Save at the top.")
            st.image("images/sap_connectivity/fiori/fiori_6.png")

        with st.expander("12. Verify the launchpad", expanded=False):
            st.markdown(
                "12. Check the address: "
                "https://<sid>lp1.ucc.cit.tum.de:8100/sap/bc/ui5_ui5/ui2/ushell/shells/abap/FioriLaunchpad.html "
                "if the Launchpad meets your expectations:"
            )
            st.image("images/sap_connectivity/fiori/fiori_7.png")

    with st.container(border=True):
        st.subheader("Step 2: Configure the flp Node (Fiori Launchpad)")

        with st.expander("1–3. Navigate to the flp node and enter edit mode", expanded=False):
            st.markdown("1. Hit the Back arrow to return to the SICF tree.")
            st.markdown(
                "2. Now, navigate to this path: `default_host -> sap -> bc -> ui2 -> flp`"
            )
            st.image("images/sap_connectivity/fiori/fiori_8.png")
            st.markdown("3. Double-click flp and enter Edit Mode (pencil icon).")

        with st.expander(
            "4–6. Configure logon data and error page settings", expanded=False
        ):
            st.markdown(
                '4. Switch to the Logon Data (Anmelde-Daten) tab. Change the '
                'Security Requirement (Sicherheitsanforderung) to "Standard".'
            )
            st.image("images/sap_connectivity/fiori/fiori_9.png")
            st.markdown(
                '5. Switch to the Error Pages (Fehlerseiten) tab, scroll down, and '
                'click Configuration under "System Logon".'
            )
            st.image("images/sap_connectivity/fiori/fiori_10.png")
            st.markdown(
                '6. Set the Protocol Selection (Protokollwahl) to "Do Not Switch" '
                '(Nicht umschalten).'
            )
            st.image("images/sap_connectivity/fiori/fiori_11.png")

        with st.expander(
            "7. Save, create a transport order, and reset default security", expanded=False
        ):
            st.markdown(
                "7. Now click Save. Create a new order, click on the green tick again."
            )
            st.markdown(
                "IMPORTANT: Now go to /sap/bc/ui2/start_up and set the security "
                "requirement to default in the Login Data tab."
            )
            st.image("images/sap_connectivity/fiori/fiori_12.png")

        with st.expander("Verify the launchpad", expanded=False):
            st.markdown(
                "Check at the address: "
                "https://<sid>lp1.ucc.cit.tum.de:8100/sap/bc/ui2/flp if the launchpad "
                "meets your expectations:"
            )
            st.image("images/sap_connectivity/fiori/fiori_13.png")

    # ------------------------------------------------------------------
    # Problems with "arsrvc_spb_admn"
    # ------------------------------------------------------------------
    st.subheader('Problems with "arsrvc_spb_admn"')

    with st.container(border=True):
        st.subheader("The Execution Steps")

        with st.expander(
            "1–7. Change the security requirement in SICF", expanded=False
        ):
            st.markdown(
                """
1. Open `/nSICF` in Client 000 and hit Execute (F8).
2. Drill down this exact path: `default_host -> sap -> bc -> ui5_ui5 -> sap -> arsrvc_upb_admn`
3. Double-click the node and hit the Pencil icon ✏️ to enter Edit mode.
4. Go to the Logon Data tab.
5. Change the Security Requirement dropdown from SSL to "Standard".
6. Hit the Save 💾 icon.
7. When the Transport Request popup appears, click the "Own Requests" button to select the exact same "Fiori Customization" request you created earlier, or just create a new one. Hit the green checkmark.
                """
            )