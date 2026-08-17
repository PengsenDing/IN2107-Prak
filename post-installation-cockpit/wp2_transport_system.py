"""Manual WP2 instructions for setting up the SAP transport system."""

from __future__ import annotations

import streamlit as st


IMAGE_DIR = "images/wp2/Setting Up Transport System"


def render_wp2_transport_system() -> None:
    """Render the manual transport-system setup in the pre-transport flow."""
    st.header("Setting Up Transport System (Manual)")

    with st.container(border=True):
        st.caption(
            "These steps are not automated in this dashboard and must be completed "
            "manually before importing transport requests."
        )

        with st.expander("1. Prepare the operating system", expanded=False):
            st.markdown(
                "Stop the application server (AS) and ASCS first. As `<sid>adm`, "
                "confirm that both instances are completely **GRAY**:"
            )
            st.code(
                "sapcontrol -nr 00 -function GetProcessList\n"
                "sapcontrol -nr <sidnr> -function GetProcessList\n"
                "exit",
                language="bash",
            )
            st.warning(
                "The next command permanently deletes everything below "
                "`/usr/sap/trans`. Verify the path and that both instances are stopped "
                "before running it. Do not delete any other files or directories."
            )
            st.code("cd /usr/sap/trans\nrm -r /usr/sap/trans/*", language="bash")
            st.markdown(
                "Open `/etc/fstab`, add the NFS transport share, leave the editor, "
                "and mount all configured filesystems:"
            )
            st.code(
                "vi /etc/fstab\n\n"
                "# Add this line:\n"
                "uccnfs-power10.ucc.cit.tum.de:/nfs/trans  /usr/sap/trans  nfs  defaults  0 0\n\n"
                "# After saving and closing the editor:\n"
                "mount -a",
                language="bash",
            )

        with st.expander("2. Restart and verify the application server", expanded=False):
            st.markdown(
                "The NFS share and common transport domain are now mounted. Switch to "
                "`<sid>adm` and start the application server:"
            )
            st.code(
                "su - <sid>adm\n"
                "sapcontrol -nr 00 -function StartSystem",
                language="bash",
            )
            st.markdown(
                "Wait for AS and ASCS to start completely. Continue only when all "
                "processes are **GREEN**:"
            )
            st.code(
                "sapcontrol -nr 00 -function GetProcessList\n"
                "sapcontrol -nr <sidnr> -function GetProcessList",
                language="bash",
            )

        with st.expander(
            "3. Create the transport domain on the application server", expanded=False
        ):
            st.markdown(
                "1. Reconnect to the application server in SAP GUI and sign in to client "
                "`000` as `master-adm` (password: see the team password manager). Open "
                "transaction `STMS`.\n"
                "2. Confirm the proposed domain `DOMAIN_I04`. Enter the description using "
                "the pattern `<Product> - <AS Release>`, for example "
                "`GB 4.3 Shared - S/4HANA 2023` or "
                "`GB 4.3 Exclusive - S/4HANA 2023`.\n"
                "3. Choose **Save** and enter the transport-domain password from the "
                "team password manager when prompted."
            )
            st.image(
                f"{IMAGE_DIR}/image-2025-8-18_11-57-28 (1).png",
                caption="Confirm the proposed transport-domain and domain-controller settings.",
                use_container_width=True,
            )

        with st.expander(
            "4. Accept the system in the I04 domain controller", expanded=False
        ):
            st.markdown(
                "1. Sign in to system `I04` in SAP GUI and open transaction `STMS`. "
                "Choose **System Overview**."
            )
            st.image(
                f"{IMAGE_DIR}/image2020-7-24_14-34-8 (1).png",
                caption="Open System Overview from the STMS main screen.",
                use_container_width=True,
            )
            st.markdown(
                "2. Select your system in the list and choose the **Accept** magic-wand "
                "icon. Answer the first prompt with **Yes**. Answer the second prompt "
                "(**Distribute and activate**) with **No**."
            )
            st.image(
                f"{IMAGE_DIR}/image2020-7-24_14-36-15.png",
                caption="Select the system and use the highlighted Accept action.",
                use_container_width=True,
            )

        with st.expander(
            "5. Configure, distribute, and activate the transport routes", expanded=False
        ):
            st.markdown(
                "1. Return to the STMS main screen and choose **Transport Routes**.\n"
                "2. Switch to edit mode and scroll down until the systems `SM2`, `Z04`, "
                "`I04`, and `DMY` are visible. Configure the route so it matches the "
                "completed layout shown below."
            )
            st.image(
                f"{IMAGE_DIR}/image-2023-12-20_15-46-11.png",
                caption="Transport routes before adding the shared-system connection.",
                use_container_width=True,
            )
            st.image(
                f"{IMAGE_DIR}/image-2023-12-20_15-43-48.png",
                caption="Completed transport-route layout, including the shared system.",
                use_container_width=True,
            )
            st.markdown(
                "3. Save the draft. When asked whether the configuration should be "
                "distributed and activated system-wide, choose **Yes**. Distribution and "
                "activation can take some time.\n\n"
                "After it finishes, close the SAP GUI session on `I04`."
            )
