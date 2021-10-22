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

## Expected results

Following the steps below will result in an Azure resources as well as Azure Devops configuration that will be used throughout this CICD Bots Reference Implementation.

| Object                                    | Purpose                                                 |
|-------------------------------------------|---------------------------------------------------------|
| An Azure App Service                      | This is the managed Web Application service where the Echo Bot application is going to be published. |
| An Echo Bot Service Principal             | This is the representation in your Azure AD of the Echo Bot application. |
| A new Azure DevOps project                | CI/CD pipelines are going to be created under this new project. |
| Multi-Stage YAML pipeline                 | A multi-stage YAML pipeline capable of building the Echo Bot application on top of changed on its folder and deploy the artifacts being created to the Web App service. |
| An ARM Service Principal                  | This is a Service Principal with `Controibutor` RBAC role in your Azure Subscription and is going to employed during the Multi-Stage YAML pipeline execution to manage your Azure Resources. |
| An Azure DevOps ARM Service Connection    | This service connection will use the ARM Service Principal to allow Azure Pipeline interact with Azure resources in your subscription |
| An Azure DevOps GitHub Service Connection | The code lives in GitHub and the Azure Pipeline needs to be notified when new commits are made againts the `main` branch. This is why using a GitHub PAT (Personal Access Token), you will give access to your Azure Pipeline to create a webhook and make other operations thought a new Azure DevOps GitHub Service Connection. |

## Fork the repository

1. fork this repo: `git clone https://github.com/mspnp/solution-architectures.git`.
1. navigate to the cicdbots folder

   ```bash
   cd ./solutions-architectures/cicdbots
   ```

## Create the Azure resource group

1. Authenticate into your Azure subscription

   ```bash
   az login
   ```

1. create the Azure Resource Group

   ```bash
   az group create -n rg-cicd-bots -l eastus2
   ```


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

## Create a new Azure DevOps project for testing the CI/CD pipelines

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
   AZURE_DEVOPS_EXT_AZURE_RM_TENANT_ID=$(echo $SP_DETAILS_CICD_BOTS | jq ".tenant" -r) && \
   AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_ID=$(echo $SP_DETAILS_CICD_BOTS | jq ".appId" -r) && \
   AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY=$(echo $SP_DETAILS_CICD_BOTS | jq ".password" -r)
   ```

1. create a new service endpoint for Azure RM

   ```bash
   az devops service-endpoint azurerm create \
      --azure-rm-service-principal-id $AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_ID \
      --azure-rm-subscription-id $(az account show --query id -o tsv) \
      --azure-rm-subscription-name "$(az account show --query name -o tsv)" \
      --azure-rm-tenant-id $AZURE_DEVOPS_EXT_AZURE_RM_TENANT_ID \
      --organization $AZ_DEVOPS_ORG_CICD_BOTS \
      --project cicdbots \
      --name ARMServiceConnection
   ```

   :book: this Service Endpoint needs to be added to your project under your Azure DevOps organization to access your Azure Subscription resource from the Azure Pipeline you are about to create.


## Create a new Multi-Stage YAML pipeline for the EchoBot

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

1. create the final stage to deploy your recently published artifcat into the Azure Web App production slot

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
             - task: AzureRmWebAppDeployment@4
               inputs:
                 appType: webApp
                 ConnectionType: AzureRM
                 ConnectedServiceName: 'ARMServiceConnection'
                 ResourceGroupName: 'rg-cicd-bots'
                 WebAppName: 'appsvc-echo-bot'
                 DeploymentType: runFromZip
                 enableCustomDeployment: true
                 packageForLinux: '$(Pipeline.Workspace)/drop-$(Build.BuildId)/echo-bot.zip'
                 deployToSlotOrASE: true
                 SlotName: 'production'
   EOF
   ```

## Create a new the Azure DevOps pipeline

1. enter your github user

   ```bash
   GITHUB_USER_CICD_BOTS=<github-username>
   ```
1. create a [new GitHub PAT with specific scopes (admin:repo_hook, repo, user)](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token#creating-a-token), and then set the token to an env var:

   ```bash
   AZURE_DEVOPS_EXT_GITHUB_PAT=<your-new-PAT>
   ```

1. get your forked repo github url

   ```bash
   NEW_REMOTE_URL_CICD_BOTS=https://github.com/${GITHUB_USER_CICD_BOTS}/solution-architectures.git
   ```

1. create a new github service connection in Azure DevOps. This will be needed to create a hook in your github repo that notifies Azure DevOps, so it can trigger your pipelines accordingly.

  ```bash
  AZURE_DEVOPS_SE_EXT_GITHUB_OUTPUT_CICD_BOTS=$(az devops service-endpoint github create --name github-svc-conn --github-url ${NEW_REMOTE_URL_CICD_BOTS}) && \
  AZURE_DEVOPS_SE_EXT_GITHUB_ID_CICD_BOTS=$(echo $AZURE_DEVOPS_SE_EXT_GITHUB_OUTPUT_CICD_BOTS | jq ".id" -r)
  ```

1. use the Multi-Stage YAML from  the previous section to create the new pipeline.

   :eyes:  The command will give you the service connection options. Please, choose the one already created.

   ```bash
   az pipelines create \
      --organization $AZ_DEVOPS_ORG_CICD_BOTS \
      --project cicdbots \
      --name echo-bot \
      --yml-path cicdbots/echo-bot/azure-pipelines.yml \
      --repository-type github \
      --repository $NEW_REMOTE_URL_CICD_BOTS \
      --branch main \
      --service-connection $AZURE_DEVOPS_SE_EXT_GITHUB_ID_CICD_BOTS \
      --skip-first-run=true
   ```

## Create yourt Azure DevOps Pipelines Environment

1. before having a first run of your pipeline, you must create an environment to host them

   ```bash
   echo '{ "name": "echobot-prod" }' > env.json && \
   az devops invoke --area environments --resource environments --route-parameters project=cicdbots --http-method POST  --api-version 6.0-preview --in-file env.json
   ```

## Execute your pipeline

1. kick off the first run to validate all is working just fine

   ```bash
   az pipelines build queue --organization $AZ_DEVOPS_ORG_CICD_BOTS --project cicdbots --definition-name=echo-bot`
   ```

1. monitor the current pipeline execution status

   ```bash
   export COMMIT_SHA1=$(git rev-parse HEAD) && \
   until export AZ_PIPELINE_STATUS=$(az pipelines build list --organization $AZ_DEVOPS_ORG_CICD_BOTS --project cicdbots --query "[?sourceVersion=='${COMMIT_SHA1}']".status -o tsv 2> /dev/null) && [[ $AZ_PIPELINE_STATUS == "completed" ]]; do echo "Monitoring multi-stage pipeline: ${AZ_PIPELINE_STATUS}" && sleep 20; done
   ```

   :warning: The first time you execute your pipeline, Azure Pipelines will request you to approve the access the new associated environment resource and the ARM Service Connection in the Deploy stage. Please navigate to the your pipeline, and approve this from the `Azure DevOps` -> `Pipelines` -> `echo-bot`. For more information, please take a look at the [Azure DevOps Pipelines Approvals](https://docs.microsoft.com/azure/devops/pipelines/process/approvals?view=azure-devops&tabs=check-pass#approvals).

1. once the deployment is completed you can now update the Azure Bot endpoint to start using the EchoBot app running on Azure Web Apps

   ```bash
   az bot update -g rg-cicd-bots -n bot-echo -e https://appsvc-echo-bot.azurewebsites.net/api/messages
   ```

## Final validation

:important: Before procceding ensure your local copy of the EchoBot has been shutdown (the being tunneled with ngrok from the `Local Validation` section).

1. Open Microsoft Teams.
1. Navigate to the previous chat window with your bot.
1. send another message and wait for the echo reply.

:eyes: Please note that now it is your live version of the EchoBot app running over Azure Web App service that you just recently deployed from code using Azure Pipelines

:book: Now you could make any further changes over your EchoBot app, and that will be built and continously deployed.

## Clean up

1. delete the SP you create for the Echo Bot application
1. delete the SP you creted for ARM
1. delete the Azure resource group
1. delete the Azure DevOps project
