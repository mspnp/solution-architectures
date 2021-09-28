## Prerequisites

1. clone this repo: `git clone https://github.com/mspnp/solution-architectures.git`.
1. [ngrok](https://ngrok.com/).
1. Ms Teams.
1. .NET Core SDK version 3.1.
1. follow the steps [here](https://docs.microsoft.com/en-us/azure/bot-service/bot-service-quickstart-registration?view=azure-bot-service-4.0&tabs=csharp) to create a basic bot in azure.
1. execute the following to add the MS Temas channel: `az bot msteams create -n <bot-name> -g <resource-group-name>`

## Run the EchoBot app locally

1. navigate to `./solutions-architectures/cicdbots/echo-bot`
1. configure the `appsettings.json` using new bot client id and password
1. execute `dotnet run`
1. open another terminal window, and execute `ngrok http -host-header=rewrite 3978`

## Validation

1. navigate to `./solutions-architectures/cicdbots/teams-bot-manifest` folder
1. then edit the `manifest.json` to replace your Microsoft App Id (that was created when you registered your bot earlier) everywhere you see the place holder string \<\<YOUR-MICROSOFT-APP-ID\>\>
1. zip up the contents of the teamsAppManifest folder to create a manifest.zip: `zip -r manifest.zip *`
1. upload the `manifest.zip` to Teams. Go to the `Apps` view and click "Upload a custom app"
1. send any message and wait for the echo reply
