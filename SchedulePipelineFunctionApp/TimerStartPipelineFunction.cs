using Azure.Messaging.ServiceBus;
using Observability.Utils;
using Observability.Utils.Data;
using Kusto.Data.Net.Client;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;

namespace Observability.SchedulePipelineFunctionApp
{
    public class TimerStartPipelineFunction
    {
        [FunctionName("TimerStartPipelineFunction")]
        public static async Task Run([TimerTrigger("0 */15 * * * *")] TimerInfo myTimer, ILogger log)
        {
            log.LogInformation($"TimerStartPipelineFunction started {DateTime.Now}");

            var config = new ConfigurationBuilder().AddEnvironmentVariables().Build();

            string queueName = config.GetValue<string>("queueName");
            string connectionString = config.GetValue<string>("ServiceBusConnection");

            var clientOptions = new ServiceBusClientOptions()
            {
                TransportType = ServiceBusTransportType.AmqpWebSockets
            };

            await using ServiceBusClient client = new ServiceBusClient(connectionString);
            var sender = client.CreateSender(queueName);

            //await using var sender = await sbHelper.GetSenderAsync(); // C# 8 feature.            

            var adx = new AdxClientHelper(config, log); //TODO Remove hard coding.

            var kcsb = adx.GetClient();

            using var kustoClient = KustoClientFactory.CreateCslQueryProvider(kcsb);

            var subscriptionsUpdateQuery = @"Subscriptions
                                            | join kind=leftouter Subscriptions_Processed on $left.subscriptionId == $right.subscriptionId
                                            | extend dp = iff(isempty(dateProcessed),ago(1d),dateProcessed)
                                            | summarize dateProcessedThrough = max(dp) by tenantId, subscriptionId
                                            | order by dateProcessedThrough asc, tenantId, subscriptionId";

            var resourceTypeQuery = @"Resource_Providers";

            using var reader = kustoClient.ExecuteQuery(subscriptionsUpdateQuery);

            // var resourceClient = new ResourceGraphHelper(config, log); // Commented for multi tenant changes.

            string prevTenantId = "";
            ResourceGraphHelper resourceClient = null;

            while (reader.Read())
            {
                using var resourceTypes = kustoClient.ExecuteQuery(resourceTypeQuery); //TODO: I moved here so that you don't need to create again after "while (resourceTypes.Read())" loop. Does that work?
            
                var tenantId = reader.GetGuid(0).ToString();

                log.LogInformation($"This is the current Tenant ID: {tenantId}");

                var subscriptionId = reader.GetGuid(1);
                log.LogInformation($"This is the current Subscription ID: {subscriptionId}");
                
                var fromDate = reader.GetDateTime(2);
                var toDate = DateTime.UtcNow;

                var subscriptionNameQuery = $"Subscription_Names | where subscriptionId == '{subscriptionId}'";

                var subscriptionNameResponse = kustoClient.ExecuteQuery(subscriptionNameQuery);

                if(tenantId != prevTenantId) {
                    log.LogInformation($"Creating new resource client for {tenantId}");
                    prevTenantId = tenantId;
                    resourceClient = new ResourceGraphHelper(config, log, tenantId); 
                }

                var subscriptionName = "";
                if (subscriptionNameResponse.Read())
                {
                    subscriptionNameResponse.Read();
                    subscriptionName = subscriptionNameResponse.GetString(1);
                }
                else
                {
                    subscriptionName = resourceClient.GetSubscriptionName(subscriptionId.ToString()); //TODO: make asynchronous
                    await adx.IngestSubscriptionNameAsync(subscriptionId.ToString(), subscriptionName);
                }

                log.LogInformation($"This is the Subscription name: {subscriptionName}");

                while (resourceTypes.Read())
                {
                    var resources = new List<AzureResource>();
                    var type = resourceTypes.GetString(1);
                    var resultTable = resourceTypes.GetString(2);

                    var result = resourceClient.QueryGraph(subscriptionId.ToString(), type);

                    log.LogInformation($"This is the graph result : {result.Data}");

                    var resultArray = result.Data.ToArray();
                    string str = Encoding.ASCII.GetString(resultArray);

                    resources = JsonConvert.DeserializeObject<List<AzureResource>>(str);

                    var finalResources = new List<AzureResource>();

                    // Send to service bus and clear resources array for next batch
                    using ServiceBusMessageBatch messageBatch = await sender.CreateMessageBatchAsync();

                    int i = 0;
                    int j = 0;
                    while (i < resources.Count)
                    {
                        var queueMessage = new Message();

                        queueMessage.SubscriptionID = subscriptionId.ToString();
                        queueMessage.Type = type;
                        queueMessage.From = fromDate;
                        queueMessage.To = toDate;
                        queueMessage.ResultTable = resultTable;
                        queueMessage.TenantId = tenantId ;

                        var curResource = resources[i];
                        var curLocation = curResource.Location;

                        var count = 0;
                        while ((j < resources.Count) && (curLocation == resources[j].Location) && (count < 50))
                        {
                            finalResources.Add(resources[j]);
                            count++;
                            j++;
                            i = j;
                        }

                        queueMessage.Location = curLocation;
                        queueMessage.Resources = finalResources;

                        var messageJson = System.Text.Json.JsonSerializer.Serialize(queueMessage);

                        log.LogInformation("Adding message to queue");
                        if (messageBatch.TryAddMessage(new ServiceBusMessage(messageJson)))
                        {
                            log.LogInformation("Message added to queue");

                            log.LogInformation("Sending messages now...");
                            await sender.SendMessagesAsync(messageBatch);

                        }
                        else
                        {
                            throw new Exception($"Message {messageJson} failed to get to queue");
                        }

                        finalResources.Clear();
                    }

                    log.LogInformation("Clearing resources");
                    resources.Clear();
                    messageBatch.Dispose();
                }
                await adx.IngestSubscriptionDateAsync(subscriptionId.ToString(), toDate);
                resourceTypes.Close();
            }
            reader.Close();
            await sender.CloseAsync();
        }
    }
}