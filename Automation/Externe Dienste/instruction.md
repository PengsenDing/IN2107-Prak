1. Einbinden der Systeme in den UCC SAP webdispatcher
    Als nächstes solltest du das Fiori-Launchpad, im webdispatcher eintragen (System in Webdispatcher registrieren)
    1. Verbinde dich auf den Webdispatcher, dem du ein System hinzufügen willst.
        **Resource**: SAPUCC Webdispathcers (See link in Wiki)
    2. To automate this post-installation step, the most common and robust approach on Linux/Unix systems is using a **Bash script**.

        Based on your screenshot and description, you need a script that can dynamically locate the correct profile file (e.g., `UCC_W00_sqpacc` as seen in your WinSCP window) by ignoring the `DEFAULT.PFL` file, and then safely inject or modify parameters within it.

        Here is a standard bash script template you can use to automate this process.

        ### Bash Automation Script

        This script uses standard Linux commands (`find` and `sed`) to locate the file and edit it automatically.

        ```bash
        #!/bin/bash

        # 1. Define your SAP variables
        SID="UCC"                    # Replace with your actual SID if it changes
        INSTANCE_NUM="00"            # Replace with your instance number
        PROFILE_DIR="/sap/${SID}/sapmnt/profile"

        # 2. Find the correct profile file
        # This looks for a file starting with "<SID>_W<InstanceNumber>_" and ignores DEFAULT.PFL
        PROFILE_FILE=$(find "$PROFILE_DIR" -maxdepth 1 -type f -name "${SID}_W${INSTANCE_NUM}_*" | head -n 1)

        # Check if the file was actually found
        if [ -z "$PROFILE_FILE" ]; then
            echo "Error: Could not find the instance profile in $PROFILE_DIR"
            exit 1
        fi

        echo "Targeting profile file: $PROFILE_FILE"

        # 3. Create a backup before making automated changes (Highly Recommended)
        cp "$PROFILE_FILE" "${PROFILE_FILE}.bak_$(date +%F_%T)"
        echo "Created backup: ${PROFILE_FILE}.bak_$(date +%F_%T)"

        # 4. Automate your edits

        # SCENARIO A: Add a new parameter to the end of the file
        # Use 'echo' to append (>>) to the file
        echo "login/system_client = 100" >> "$PROFILE_FILE"
        echo "Added new parameter to profile."

        # SCENARIO B: Modify an existing parameter
        # Use 'sed' to search for an existing parameter and replace its value
        # Example: changing 'login/password_expiration_time = 30' to '90'
        sed -i 's/^login\/password_expiration_time = .*/login\/password_expiration_time = 90/' "$PROFILE_FILE"
        echo "Updated existing parameter."

        echo "Profile configuration automated successfully."

        ```

        ### How This Works:

        * **Dynamic Discovery (`find`):** Instead of hardcoding the hostname (like `sqpacc` in your screenshot), the `find` command uses a wildcard (`*`). It looks specifically for a file matching `UCC_W00_*` inside the target directory. This guarantees it grabs your instance profile and ignores `DEFAULT.PFL`.
        * **Backups:** The script automatically creates a timestamped backup of the profile before touching it, ensuring you can roll back if the automation fails.
        * **Appending vs. Modifying:** * If you just need to add new configuration lines at the bottom of the file, the `echo "..." >> file` method is the safest and easiest.
        * If you need to change a parameter that SAP already wrote into the file during installation, the `sed -i` command does an inline find-and-replace.



        ### Scaling Up (Ansible)

        If you are doing this across many SAP systems and want to move beyond basic shell scripts, you would typically use an **Ansible Playbook** with the `lineinfile` module. This module is idempotent, meaning it checks if the line is already correct before trying to change it, preventing duplicate entries if you run the script twice.

    3. System im Webdispatcher registrieren
        To automate this step, you run into a new challenge: **Dynamic Indexing**.

        Unlike the previous step where you could just search and replace a static value, the entries in your screenshots use sequential numbering (`wdisp/system_105`, `wdisp/system_106`, `icm/HTTP/redirect_116`, etc.). Your automation script must be smart enough to read the file, find the *highest existing number* for each parameter, and increment it for the new entries.

        A **Bash script** is perfect for this. It can use command-line text processing tools (`grep`, `sed`, `sort`) to calculate the next available index and append the new lines.

        Here is the script to automate this configuration:

        ### The Web Dispatcher Automation Script

        ```bash
        #!/bin/bash

        # ==========================================
        # 1. Define your variables here
        # ==========================================
        PROFILE_FILE="/sap/UCC/sapmnt/profile/UCC_W00_sqpacc" # Replace with the actual path to your Web Dispatcher profile
        NEW_SID="i94"                                         # The SID of the new backend system
        NEW_ADDRESS="${NEW_SID}.sapucc.in.tum.de"             # The new host address

        echo "Automating Web Dispatcher profile updates for SID: $NEW_SID"

        # ==========================================
        # 2. Create a safety backup
        # ==========================================
        cp "$PROFILE_FILE" "${PROFILE_FILE}.bak_$(date +%F_%T)"
        echo "Backup created."

        # ==========================================
        # 3. Calculate the next available index numbers
        # ==========================================

        # Find the highest number for wdisp/system_xxx
        MAX_WDISP=$(grep "^wdisp/system_" "$PROFILE_FILE" | sed -n 's/^wdisp\/system_\([0-9]*\).*/\1/p' | sort -n | tail -1)
        # If no entries exist yet, start at 0. Otherwise, add 1.
        if [ -z "$MAX_WDISP" ]; then NEXT_WDISP=0; else NEXT_WDISP=$((MAX_WDISP + 1)); fi

        # Find the highest number for icm/HTTP/redirect_xxx
        MAX_REDIRECT=$(grep "^icm/HTTP/redirect_" "$PROFILE_FILE" | sed -n 's/^icm\/HTTP\/redirect_\([0-9]*\).*/\1/p' | sort -n | tail -1)
        if [ -z "$MAX_REDIRECT" ]; then NEXT_REDIRECT=0; else NEXT_REDIRECT=$((MAX_REDIRECT + 1)); fi

        echo "Next wdisp/system index: $NEXT_WDISP"
        echo "Next icm/HTTP/redirect index: $NEXT_REDIRECT"

        # ==========================================
        # 4. Append the new configuration lines
        # ==========================================

        echo "" >> "$PROFILE_FILE"
        echo "# --- Automated entries for $NEW_SID ---" >> "$PROFILE_FILE"

        # Append Backend System
        echo "wdisp/system_${NEXT_WDISP} = SID=EXT, EXTSRV=http://${NEW_SID}lp1.ucc.in.tum.de:8000, SSL_ENCRYPT=0, SRCVHOST=${NEW_ADDRESS}" >> "$PROFILE_FILE"

        # Append HTTP to HTTPS Redirect
        echo "icm/HTTP/redirect_${NEXT_REDIRECT} = PREFIX=/, FOR=${NEW_ADDRESS}, FROMPROT=http, PROT=https, HOST=${NEW_ADDRESS}" >> "$PROFILE_FILE"
        NEXT_REDIRECT=$((NEXT_REDIRECT + 1)) # Increment index for the next line

        # Append Fiori Launchpad Redirect (Assuming >= 4.1 based on common modern setups. Change the TO= path if using <= 4.0)
        echo "icm/HTTP/redirect_${NEXT_REDIRECT} = PREFIX=/, FOR=${NEW_ADDRESS}, FROMPROT=https, TO=/sap/bc/ui2/flp" >> "$PROFILE_FILE"
        NEXT_REDIRECT=$((NEXT_REDIRECT + 1))

        # Append WebGUI Redirect
        echo "icm/HTTP/redirect_${NEXT_REDIRECT} = PREFIX=/, FOR=${NEW_ADDRESS}, FROMPROT=https, TO=/sap/bc/gui/sap/its/webgui" >> "$PROFILE_FILE"

        echo "Configuration successfully added to profile!"

        ```

        ### How this script works:

        * **Safety First:** It immediately creates a timestamped backup of your profile.
        * **`grep`, `sed`, and `sort`:** This combination looks at all lines starting with `wdisp/system_`, extracts *only* the numbers, sorts them numerically, and grabs the very last one (the highest number). It then does the math (`+ 1`) so you don't overwrite existing configurations.
        * **Dynamic Variables:** By defining `NEW_SID` at the top, you only have to change one line of code the next time you need to add a system. The script automatically populates the `EXTSRV` and `HOST` paths.

        ### Important Post-Script Step

        Remember that modifying the text file on the OS level doesn't immediately tell the active SAP Web Dispatcher about the new rules. After running this script, you will need to reload the profile. You can either restart the Web Dispatcher or trigger a soft reload using SAP `sapcontrol` or by sending a `kill -HUP <PID>` command to the Web Dispatcher process.

    4. Aktivierung der neuen Konfiguration
        1. Method 1
            This is the final, crucial step: telling the Web Dispatcher to read the new configuration you just injected without causing downtime (a soft reload).

            To automate this, we have to solve two distinct challenges presented in your screenshot:

            1. **The User Switch:** You cannot have a script pause and drop you into a new shell with `su - <sid>adm`. The script needs to run the command *as* that user and then immediately return.
            2. **The Manual Search:** The documentation tells you to use `ls` to look up the profile name. We will use our dynamic `find` trick from earlier so the script figures this out automatically.

            *(Note: The space in your documentation's `su - <sid> adm` command is a typo in their guide. The Linux user is always the lowercase SID immediately followed by adm, like `uccadm`.)*

            Here is the Bash script to fully automate this activation step. Note that **you must run this script as the `root` user** so it has the permission to switch to the `<sid>adm` user without being prompted for a password.

            ### The Reload Automation Script

            ```bash
            #!/bin/bash

            # ==========================================
            # 1. Define Variables
            # ==========================================
            SID="UCC"
            INSTANCE_NUM="00"

            # Automatically convert the SID to lowercase to create the username (e.g., UCC -> uccadm)
            SID_LOWER=$(echo "$SID" | tr '[:upper:]' '[:lower:]')
            SAP_USER="${SID_LOWER}adm"

            # The path as specified in your documentation
            PROFILE_DIR="/sapmnt/${SID}/profile"

            # ==========================================
            # 2. Dynamically Find the Profile
            # ==========================================
            # This replaces the manual 'ls' step
            PROFILE_FILE=$(find "$PROFILE_DIR" -maxdepth 1 -type f -name "${SID}_W${INSTANCE_NUM}_*" | head -n 1)

            if [ -z "$PROFILE_FILE" ]; then
                echo "Error: Could not find the instance profile in $PROFILE_DIR"
                exit 1
            fi

            echo "Targeting profile file: $PROFILE_FILE"

            # ==========================================
            # 3. Execute the Reload Command
            # ==========================================
            echo "Executing reload as user: $SAP_USER"

            # The '-c' flag tells 'su' to run this single command as the SAP user and then exit back to the script
            su - "$SAP_USER" -c "sapwebdisp pf=$PROFILE_FILE -reconfig profile"

            # Check if the command succeeded
            if [ $? -eq 0 ]; then
                echo "Web Dispatcher configuration reloaded successfully!"
            else
                echo "Error: Failed to reload Web Dispatcher configuration."
            fi

            ```

            ### How this automates the screenshot's steps:

            * **`su - <sid>adm` automation:** By using `su - "$SAP_USER" -c "..."`, we instruct Linux to switch to the `uccadm` user, run the exact command enclosed in the quotes, and then hand control back to the script. This completely bypasses the need for human interaction.
            * **`cd /sapmnt/<SID>/profile/` automation:** Because we pass the absolute, dynamic path of the file (`$PROFILE_FILE`) directly into the `sapwebdisp` command, we don't actually need to change directories (`cd`) first. The command will run perfectly from anywhere.
            * **The `-reconfig profile` flag:** This relies on the parameter `wdisp/config_reload = TRUE` being set (as mentioned in your screenshot). As long as that is in your profile, this command triggers the Web Dispatcher to ingest the new `wdisp/system_xxx` and `icm/HTTP/redirect_xxx` lines without dropping active user connections.

    5. TODO：Nur wenn wdisp/config_reload = FALSE !!
    6. TODO：Nur wenn wdisp/config_reload = FALSE !!

2. Saprouter konfigurieren
