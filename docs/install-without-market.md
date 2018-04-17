
## How to install Task without VSTS Market

1. Load source code
2. Open console in root folder
3. Install tfx-cli tool (*npm should be preinstalled on local machine*)

    `> npm i -g tfx-cli`
4. Login into your VSTS account

    `> tfx login`
    * Service URL: `https://<account-name>.visualstudio.com/DefaultCollection`
    * Personal access token: [see instuction how to generate new](/docs/new-connected-service.md)

5. Upload Task to VSTS instance

    `> tfx build tasks upload --task-path .\Tasks\CreateRelease`

6. Open any release definition and add new task to `Agent Phase`

![add Create Release Task](/imgs/create-release-task-step-1.png)

7. Set task options

![set task options](/imgs/create-release-task-step-2.png)