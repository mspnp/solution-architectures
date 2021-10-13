using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.SignalRService;
using Microsoft.Extensions.Logging;
using System.Threading.Tasks;

/*
 * This function is triggered by a Service Bus Trigger. 
 * It has a binding with SignalR service. 
 * It pulls the message from the queue and passes it on to a SignalR hub.
 * Replace "QUEUE_NAME" below with the name of your Azure Service Bus Queue
 * "AzureWebJobsStorage" is the name of the connection string for Azure Service Bus. You can replace it in local.settings file.
 */

namespace SignalIRFunctionApp
{
    public static class MessageFunction
    {
        [FunctionName("message")]
        public static async Task Run([ServiceBusTrigger("QUEUE_NAME", Connection = "AzureWebJobsStorage")]string myQueueItem, [SignalR(HubName = "chat")]IAsyncCollector<SignalRMessage> signalRMessages, ILogger log)
        {

            if (string.IsNullOrEmpty(myQueueItem))
            {
                log.LogInformation("Please pass a payload to broadcast in the request body.");
                return ;
            }

            await signalRMessages.AddAsync(new SignalRMessage()
            {
                Target = "notify",  //"notify" is the name of the channel to broadcast the message on
                Arguments = new object[] { myQueueItem }
            });

            log.LogInformation(myQueueItem);
            return;
        }
        
    }

}
