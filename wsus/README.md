# Set up WSUS by using the automation script

This content supports the [Plan deployment for updating Windows VMs in Azure](https://learn.microsoft.com/azure/architecture/example-scenario/wsus/) Azure Architecture Center article. For information about these files please see that article.

## Contents

* [Configure-WSUSServer](./Configure-WSUSServer.ps1) script that allows you to quickly set up a WSUS server that will automatically synchronize and approve updates for a chosen set of products and languages.
* [WSUS Configuration](./WSUS-Config.json) JSON file which allow you to configure these options:

- Whether update payloads should be stored locally (and, if so, where they should be stored), or left on the Microsoft servers.
- Which products, update classifications, and languages should be available on the server.
- Whether the server should automatically approve updates for installation or leave updates unapproved unless an administrator approves them.
- Whether the server should automatically retrieve new updates from Microsoft, and, if so, how often.
- Whether Express update packages should be used. (Express update packages reduce server-to-client bandwidth at the expense of client CPU/disk usage and server-to-server bandwidth.)
- Whether the script should overwrite its previous settings. (Normally, to avoid inadvertent reconfiguration that might disrupt server operation, the script will run only once on a given server.)