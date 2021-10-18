## Prerequisites

1. An Azure subscription. You can [open an account for free](https://azure.microsoft.com/free).
1. An Azure DevOps account. You can [start free](https://azure.microsoft.com/services/devops/).
1. create a PAT, see [Use personal access tokens](https://docs.microsoft.com/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops#create-a-pat).

   :important: ensure your PAT expires in just a few days, and give it the least priviledges by selecting the specific scope this token needs to be authorized for.  Build: `Read & execute`  Environment: `Read & manage`  Release: `Read, write, execute & manage`  Project and Team: `Read, write & manage`  Service Connections: `Read, query & manage`.  Finally, ensure you save the generated PAT in a secure maner until you use this a few steps below.

1. Latest [Azure CLI installed](https://docs.microsoft.com/cli/azure/install-azure-cli?view=azure-cli-latest) or you can perform this from Azure Cloud Shell by clicking below.

   [![Launch Azure Cloud Shell](https://docs.microsoft.com/azure/includes/media/cloud-shell-try-it/launchcloudshell.png)](https://shell.azure.com)

1. [ngrok](https://ngrok.com/).
1. Microsoft Teams.
1. .NET Core SDK version 3.1.
1. fork this repo: `git clone https://github.com/mspnp/solution-architectures.git`.
1. navigate to the cicdbots folder

   ```bash
   cd ./solutions-architectures/cicdbots
   ```

1. Authenticate into your Azure subscription

   ```bash
   az login
   ```

1. create the Azure Resource Group

   ```bash
   az group create -n rg-cicd-bots -l eastus2
   ```

## Expected results

Following the steps below will result in an Azure resources as well as Azure Devops configuration that will be used throughout this CICD Bots Reference Implementation.

| Object                             | Purpose                                                 |
|------------------------------------|---------------------------------------------------------|
| Forked repo                        | This is your own copy of the CICD bots Reference Implemenation that is going to be located from  your very own GitHub repositories directory. |
| A new resourge group               | This will logically group all Azure resource in this Reference Implementation, the location has been arbitrary decided but you could choose any other if desired. |
| An App Service Plan                | This is an Standard Windows App Service Plan. |
| A Web App Service                  | This is the managed Web Application service where the Echo Bot application is going to be published. |
| An Echo Bot Service Principal      | This is the representation in your Azure AD of the Echo Bot application. |
| A new Azure DevOps project         | CI/CD pipelines are going to be created under this new project. |
| Multi-Stage YAML pipeline          | A multi-stage YAML pipeline capable of building the Echo Bot application on top of changed on its folder and deploy the artifacts being created to the Web App service. |
| An ARM Service Principal           | This is a Service Principal with `Controibutor` RBAC role in your Azure Subscription and is going to employed during the Multi-Stage YAML pipeline execution to manage your Azure Resources. |

## Create the EchoBot app and its ARM templates to be deployed into Azure

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

1. Choose a password for your bot

   ```bash
   APP_SECRET=<at-least-sixteen-characters-here>
   ```

1. register a new Azure AD App for the EchoBot

   ```bash
   APP_DETAILS_CICD_BOTS=$(az ad app create --display-name "echobot" --password ${APP_SECRET} --available-to-other-tenants -o json) && \
   APP_ID_CICD_BOTS=$(echo $APP_DETAILS_CICD_BOTS | jq ".appId" -r)
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

:bulb: Before procceding to deploy you might want to test your new EchoBot app is fully working.

1. navigate to `./solutions-architectures/cicdbots/teams-bot-manifest` folder
1. then edit the `manifest.json` to replace your Microsoft App Id (that was created when you registered your bot earlier) everywhere you see the place holder string \<\<YOUR-MICROSOFT-APP-ID\>\>
1. zip up the contents of the teamsAppManifest folder to create a manifest.zip: `zip -r manifest.zip *`
1. upload the `manifest.zip` to Teams. Go to the `Apps` view and click "Upload a custom app"
1. send any message and wait for the echo reply

## Create a new Azure DevOps CI/CD pipeline for the EchoBot

1. install de Azure DevOps Azure CLI extension

   ```bash
   az extension add --upgrade -n azure-devops
   ```

   :bulb: ops team members might want to use the [Azure CLI extension](https://docs.microsoft.com/azure/devops/cli) to interact with Azure DevOps on daily basis. Alternatevely, same steps can be done from the Azure DevOps site.

1. set your Azure DevOps organization name

   ```bash
   AZ_DEVOPS_ORG_NAME_CICD_BOTS=<your-azdevops-org-name-here>
   ```

1. set your Azure DevOps organization

   ```bash
   AZ_DEVOPS_ORG_CICD_BOTS=https://dev.azure.com/${AZ_DEVOPS_ORG_NAME_CICD_BOTS}/
   ```

1. login in your Azure DevOps account

   ```bash
   az devops login
   ```

   :key: you will be prompted for the PAT token, paste the saved in the prerequiistes section. Please let's take a look at the [Sign in with PAT documentation](https://docs.microsoft.com/azure/devops/cli/log-in-via-pat?view=azure-devops&tabs=windows#user-prompted-to-use-az-devops-login) for more information login.

1. create a new Azure DevOps project

   ```bash
   az devops project create --name cicdbots --org $AZ_DEVOPS_ORG_CICD_BOTS
   ```

1. create service principal to mange your Azure resources from Azure Pipelines

   ```bash
   SP_DETAILS_CICD_BOTS=$(az ad sp create-for-rbac --appId echo-bot --role="Contributor") && \
   ARM_TENANT_ID_CICD_BOTS=$(echo $SP_DETAILS_CICD_BOTS | jq ".tenant" -r) && \
   ARM_SP_CLIENT_ID_CICD_BOTS=$(echo $SP_DETAILS_CICD_BOTS | jq ".appId" -r) && \
   ARM_SP_CLIENT_SECRET_CICD_BOTS=$(echo $SP_DETAILS_CICD_BOTS | jq ".password" -r)
   ```

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
