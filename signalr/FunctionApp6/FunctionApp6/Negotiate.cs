using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.Azure.WebJobs.Extensions.SignalRService;

/*
 * This function is triggered by a Http request. 
 * It is used by client applications to get a token from the SignalR service which clients can use to subscribe to a hub. 
 * This should always be named negotiate. 
 */
namespace FunctionApp6
{
    public static class NegotiateFunction
    {
        [FunctionName("negotiate")]
        public static SignalRConnectionInfo Negotiate(
            [HttpTrigger(AuthorizationLevel.Anonymous)]HttpRequest req,
            [SignalRConnectionInfo(HubName = "chat")]SignalRConnectionInfo connectionInfo) //"chat" is the name of the Hub that your clients will subscribe to
        {
            return connectionInfo;
        }
    }
}
