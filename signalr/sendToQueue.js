const { ServiceBusClient } = require("@azure/service-bus"); 

// Define connection string and related Service Bus entity names here
const connectionString = "YOUR_SERVICE_BUS_CONNECTION_STRING";
const queueName = "YOUR_QUEUE_NAME"; 

async function main(){
  const sbClient = ServiceBusClient.createFromConnectionString(connectionString); 
  const queueClient = sbClient.createQueueClient(queueName);
  const sender = queueClient.createSender();

  try {

    //Message to send should be in the 'body' property. 
    const message= {
    body: { 
        orderid: '321',
        storeid: '123',
        lat:'30',
        longitude:'70'        
    },
    label: `driveby`,
    contentType: 'application/json'
    };
    console.log(`Sending message: ${message.body}`);
    await sender.send(message);
    

    await queueClient.close();
  } finally {
    await sbClient.close();
  }
}

main().catch((err) => {
  console.log("Error occurred: ", err);
});