## Prerequisites

1. [ngrok](https://ngrok.com/).
1. Microsoft Teams.
1. .NET Core SDK version 3.1.
1. clone this repo: `git clone https://github.com/mspnp/solution-architectures.git`.
1. navigate to the cicdbots folder

   ```bash
   cd ./solutions-architectures/cicdbots
   ```

1. create the Azure Resource Group

   ```bash
   az group create -n rg-cicd-bots -l eastus2
   ```

## Create the EchoBot app

1. install the Microsoft Bot generators

   ```bash
   dotnet new -i Microsoft.Bot.Framework.CSharp.EchoBot --nuget-source https://botbuilder.myget.org/F/aitemplates/api/v3/index.json
   ```

   > Note: this step uses the .NET Core Templates for [Bot Framework v4](https://dev.botframework.com). You could choose among other more advanced  bots if you want to. For more information, please visit [https://github.com/Microsoft/BotBuilder-Samples/tree/main/generators/dotnet-templates](https://github.com/Microsoft/BotBuilder-Samples/tree/main/generators/dotnet-templates).

1. generate an echo bot in your local working copy:

   ```bash
   dotnet new echobot -n echo-bot
   ```

## Register a new Azure Bot in your Azure subscription

1. Choose a passwork for your bot

   ```bash
   export APP_SECRET=<at-least-sixteen-characters-here>
   ```

1. register a new Azure AD App for the EchoBot

   ```bash
   export APP_DETAILS_CICD_BOTS=$(az ad app create --display-name "echobot" --password ${APP_SECRET} --available-to-other-tenants -o json) && \
   export APP_ID_CICD_BOTS=$(echo $APP_DETAILS_CICD_BOTS | jq ".appId" -r)
   ```

1. deploy the Azure Bot resource

   ```bash
   az deployment group create \
      -g "rg-cicd-bots" \
      --template-file "./echo-bot/DeploymentTemplates/template-with-preexisting-rg.json" \
      --parameters appId=${APP_ID_CICD_BOTS} \
      appSecret=${APP_SECRET} \
      botId="bot-echo" \
      newAppServicePlanName="appplanweb-echo-bot" \
      newWebAppName="appsvc-echo-bot" \
      appServicePlanLocation="eastus2" \
      -n "deploy-bot"
   ```

1. execute the following to add the MS Teams channel:

   ```bash
   az bot msteams create -n bot-echo -g rg-cicd-bots
   ```

## Save your progress

take a moment to save the env vars you have configured already. This can be later used to resume your the progress. :warning: It must not be used in prod to prevent from leaking in-memory sensetive data.

```bash
chmod +x ./saveenv.sh
./saveenv.sh
```

## Run the EchoBot app locally

1. navigate to `./solutions-architectures/cicdbots/echo-bot`
1. configure the `appsettings.json` using new bot client id and password
   ```bash
   sed -i 's/"MicrosoftAppId": ""/"MicrosoftAppId": "'"$APP_ID_CICD_BOTS"'"/#g'  appsettings.json && \
   sed -i 's/"MicrosoftAppPassword": ""/"MicrosoftAppPassword": "'"$APP_SECRET"'"/g' appsettings.json
   ```
1. execute `ngrok http -host-header=rewrite 3978`
1. open another terminal window, and update the Azure Bot endpoint with the `ngrok` generated `https` forwarding url:

   ```bash
   az bot update -g rg-cicd-bots -n bot-echo -e https://<unique-identifier>.ngrok.io/api/messages
   ```

1. execute `dotnet run`

## Local validation

1. navigate to `./solutions-architectures/cicdbots/teams-bot-manifest` folder
1. then edit the `manifest.json` to replace your Microsoft App Id (that was created when you registered your bot earlier) everywhere you see the place holder string \<\<YOUR-MICROSOFT-APP-ID\>\>
1. zip up the contents of the teamsAppManifest folder to create a manifest.zip: `zip -r manifest.zip *`
1. upload the `manifest.zip` to Teams. Go to the `Apps` view and click "Upload a custom app"
1. send any message and wait for the echo reply

## Create a new Azure DevOps CI/CD pipeline for the EchoBot

1. create a new yaml pipeline

   ```bash
   touch echo-bot/azure-pipelines.yml
   ```

1. trigger the pipeline when your forked repo receives a new commit into the `main` branch if and only if a file gets modified under the `echo-bot` folder structure:

   ```bash
   cat >> echo-bot/azure-pipelines.yml <<EOF
   trigger:
     branches:
       include:
       - main
     paths:
       include:
       - cicdbots/echo-bot
   EOF
   ```

1. add the first stage to build the EchoBot application:

   ```bash
   cat >> echo-bot/azure-pipelines.yml <<EOF

   stages:
   - stage: Build
     jobs:
     - job: EchoBotBuild
       displayName: EchoBot Continous Integration
       pool:
         vmImage: 'ubuntu-20.04'
       continueOnError: false
       steps:
       - task: DotNetCoreCLI@2
         displayName: Restore
         inputs:
           command: restore
           projects: cicdbots/echo-bot/echo-bot.csproj

       - task: DotNetCoreCLI@2
         displayName: Build
         inputs:
           projects: cicdbots/echo-bot/echo-bot.csproj
           arguments: '--configuration release'

       - task: DotNetCoreCLI@2
         displayName: Publish
         inputs:
           command: publish
           publishWebProjects: false
           workingDirectory: cicdbots/echo-bot
           arguments: '--configuration release --output "\$(Build.ArtifactStagingDirectory)" --no-restore'
           zipAfterPublish: false
   EOF
   ```

1. archive the output from the build and publish this as an artifact in your pipeline:

   ```bash
   cat >> echo-bot/azure-pipelines.yml <<EOF

       - task: ArchiveFiles@2
         displayName: 'Archive files'
         inputs:
           rootFolderOrFile: '\$(Build.ArtifactStagingDirectory)'
           includeRootFolder: false
           archiveType: zip
           archiveFile: '\$(Build.ArtifactStagingDirectory)/echo-bot.zip'

       - task: PublishPipelineArtifact@1
         displayName: 'Publish Artifact'
         inputs:
           targetPath: '\$(Build.ArtifactStagingDirectory)/echo-bot.zip'
           artifactName: 'drop-\$(Build.BuildId)'
   EOF
   ```

   :book: the artifact that is published as part of this building stage is later being used by the deployment stage

1. create the final stage that deploys your recently published artifcat

   ```bash
   cat >> echo-bot/azure-pipelines.yml <<EOF

   - stage: Deploy
     dependsOn:
     - Build
     jobs:
     - deployment: EchoBotDeploy
       displayName: EchoBot Continous Deployment
       pool:
         vmImage: 'ubuntu-20.04'
       environment: 'echobot-prod'
       strategy:
         runOnce:
           deploy:
             steps:
             - script: echo foobar
               displayName: 'test task'
               name: echoTask
   EOF
   ```
