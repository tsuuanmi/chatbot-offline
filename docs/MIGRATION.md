# Migration Rules

The previous implementation is located at:

    /home/superman/workspaces/chatbot

The new implementation is:

    /home/superman/workspaces/chatbot-offline

## Rules

1. Never copy the whole old repository.

2. Copy only a component required by the current milestone.

3. Before copying code, determine whether the selected framework already
   provides the same functionality.

4. Prefer rewriting small domain-specific components over carrying legacy
   infrastructure into the new repository.

5. Do not preserve compatibility code unless there is a current requirement.

6. Every migrated domain rule must have tests.

7. Models, secrets, database files, Docker archives, and generated indexes
   belong under runtime/ and are not committed.

8. CPU execution must remain fully functional regardless of GPU availability.

9. Ubuntu and RHEL must use the same application images and application
   configuration. Host-specific differences belong only in installation and
   host integration code.

10. Do not disable SELinux to make RHEL deployment work.
