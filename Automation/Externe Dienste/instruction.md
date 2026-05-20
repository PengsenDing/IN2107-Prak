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
2. Saprouter konfigurieren
