"""Manual WP2 instructions for configuring SAP Secure Storage (SECSTORE)."""

from __future__ import annotations

import streamlit as st


IMAGE_DIR = "images/wp2/SECSTORE"


def render_wp2_secstore() -> None:
    """Render the manual SECSTORE procedure in the pre-transport flow."""
    st.header("SECSTORE (Manual)")

    with st.container(border=True):
        st.caption(
            "These steps configure SAP Secure Storage and must be completed "
            "manually in SAP GUI."
        )

        with st.expander("1. Check the secure-storage entries", expanded=False):
            st.markdown(
                "Open transaction `SECSTORE`. On the **Check Entries** tab, keep "
                "**All Applications** selected and choose **Execute**."
            )
            st.image(
                f"{IMAGE_DIR}/image2020-7-22_14-52-39.png",
                caption="Run the secure-storage check for all applications.",
                use_container_width=True,
            )

        with st.expander("2. Delete obsolete entries", expanded=False):
            st.markdown(
                "Review the results and identify every yellow entry whose message "
                "states that the entry can be deleted. Select only those entries, "
                "choose **Delete**, and then choose **Delete All** in the confirmation "
                "dialog. Do not delete green entries or yellow entries with a "
                "different message."
            )
            st.image(
                f"{IMAGE_DIR}/image-2024-1-22_12-15-15.png",
                caption="Delete only yellow entries explicitly marked as safe to remove.",
                use_container_width=True,
            )

        with st.expander("3. Generate a new secure-storage key", expanded=False):
            st.markdown(
                "Choose **Exit** to return to the SECSTORE main screen. Open the "
                "**Key Management** tab and choose **Generate**."
            )
            st.image(
                f"{IMAGE_DIR}/image2020-7-22_15-4-5.png",
                caption="Generate a new key from the Key Management tab.",
                use_container_width=True,
            )

        with st.expander("4. Back up the generated key securely", expanded=False):
            st.warning(
                "The generated key is required to read encrypted records. Losing it "
                "can make those records unreadable. Never store the key as plaintext "
                "in this application, source control, or an unsecured file."
            )
            st.markdown(
                "Record the **key identifier** and **key value** displayed in the "
                "lower part of the dialog in the approved **GB 4.3 Installation "
                "Protocol**, or in the approved secure external storage location. "
                "After confirming that the complete values were recorded correctly, "
                "choose **Continue**."
            )
            st.image(
                f"{IMAGE_DIR}/image2020-7-22_15-10-54.png",
                caption="Record the generated identifier and key value before continuing.",
                use_container_width=True,
            )

        with st.expander(
            "5. Confirm the backup and update existing records", expanded=False
        ):
            st.markdown(
                "Enter the requested character positions from the key value recorded "
                "in the installation protocol. Hyphens and spaces are ignored. Choose "
                "**Continue** when the requested positions are complete."
            )
            st.image(
                f"{IMAGE_DIR}/image2020-7-22_15-15-0.png",
                caption="Confirm the external key backup using the requested positions.",
                use_container_width=True,
            )
            st.markdown(
                "In the next dialog, choose **Continue** to update existing records "
                "with the new key. When processing finishes, choose **Exit** to leave "
                "transaction `SECSTORE`."
            )
            st.image(
                f"{IMAGE_DIR}/image2020-7-22_15-16-9.png",
                caption="Continue to update existing records with the new key.",
                use_container_width=True,
            )
