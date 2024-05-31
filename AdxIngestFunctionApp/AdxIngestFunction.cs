using Azure.Core;
using Azure.Identity;
using Observability.Utils;
using Observability.Utils.Data;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using System;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Azure.Management.ResourceManager.Fluent.Models;


namespace Observability.AdxIngestFunctionApp
{
    
    public class AdxIngestFunction
    {
        private static HttpClient _httpClient = new HttpClient();
        private static KeyVaultManager keyVaultManager = null;
        private static readonly IConfiguration _config = new ConfigurationBuilder().AddEnvironmentVariables().Build();

        static AdxIngestFunction()
        {
            string DefaultRequestHeaders = _config.GetValue<string>("DefaultRequestHeaders");
            _httpClient.DefaultRequestHeaders.UserAgent.TryParseAdd(DefaultRequestHeaders);
        }

        [FunctionName("AdxIngestFunction")]
        public static async Task Run([ServiceBusTrigger("%queueName%", Connection = "ServiceBusConnection", IsSessionsEnabled = false)] String myQueueItem, ILogger log)
        {
            ClientSecretCredential spCredential;

            AccessToken accessToken;

            //TODO: Add Debug Asserts for parameters etc. But also check in realease?
            //Debug.Assert(descriptor.Name != null);
            //Debug.Assert(store != null);

            log.LogInformation($"AdxIngestFunction processing message: {myQueueItem}");

            var config = new ConfigurationBuilder().AddEnvironmentVariables().Build(); //TODO: Consider moving to static AdxIngestionFunction
            var message = System.Text.Json.JsonSerializer.Deserialize<Message>(myQueueItem);
            var resourceIds = message.Resources.Select(r => r.ID).ToList();
            var jsonResouces = System.Text.Json.JsonSerializer.Serialize(new { resourceids = resourceIds });

            var timeSpan = message.From.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") + "/" + message.To.ToString("yyyy-MM-ddTHH:mm:ss.fffZ");

            var batchUrl = $"https://{message.Location}.metrics.monitor.azure.com/subscriptions/{message.SubscriptionID}/metrics:getBatch?timespan={timeSpan}&interval=PT1M&metricnames=Availability&aggregation=average&metricNamespace={message.Type}&autoadjusttimegrain=true&api-version=2023-03-01-preview";

            if (message.Type == "microsoft.network/azurefirewalls")
            {
                batchUrl = $"https://{message.Location}.metrics.monitor.azure.com/subscriptions/{message.SubscriptionID}/metrics:getBatch?timespan={timeSpan}&interval=PT1M&metricnames=FirewallHealth&aggregation=average&metricNamespace={message.Type}&autoadjusttimegrain=true&api-version=2023-03-01-preview";
            }
            if (message.Type == "microsoft.network/loadbalancers")
            {
                batchUrl = $"https://{message.Location}.metrics.monitor.azure.com/subscriptions/{message.SubscriptionID}/metrics:getBatch?timespan={timeSpan}&interval=PT1M&metricnames=VipAvailability&aggregation=average&metricNamespace={message.Type}&autoadjusttimegrain=true&api-version=2023-03-01-preview";
            }
            if (message.Type == "microsoft.containerservice/managedclusters")
            {
            batchUrl = $"https://{message.Location}.metrics.monitor.azure.com/subscriptions/{message.SubscriptionID}/metrics:getBatch?timespan={timeSpan}&interval=PT1M&metricnames=kube_node_status_condition&aggregation=average&metricNamespace={message.Type}&filter=status2 eq '*'&validatedimensions=false&autoadjusttimegrain=true&api-version=2023-03-01-preview";
            }
            if (message.Type == "microsoft.documentdb/databaseaccounts")
            {
                batchUrl = $"https://{message.Location}.metrics.monitor.azure.com/subscriptions/{message.SubscriptionID}/metrics:getBatch?timespan={timeSpan}&interval=PT1M&metricnames=ServiceAvailability&aggregation=average&metricNamespace={message.Type}&autoadjusttimegrain=true&api-version=2023-03-01-preview";
            }
            if (message.Type == "microsoft.cognitiveservices/accounts")
            {
                batchUrl = $"https://{message.Location}.metrics.monitor.azure.com/subscriptions/{message.SubscriptionID}/metrics:getBatch?timespan={timeSpan}&interval=PT1M&metricnames=SuccessRate&aggregation=average&metricNamespace={message.Type}&autoadjusttimegrain=true&api-version=2023-03-01-preview";
            }
            if (message.Type == "microsoft.eventhub/namespaces")
            {
                batchUrl = $"https://{message.Location}.metrics.monitor.azure.com/subscriptions/{message.SubscriptionID}/metrics:getBatch?timespan={timeSpan}&interval=PT1M&metricnames=IncomingRequests,ServerErrors&aggregation=average&metricNamespace={message.Type}&autoadjusttimegrain=true&api-version=2023-03-01-preview";
            }
            if (message.Type == "microsoft.containerregistry/registries")
            {
                batchUrl = $"https://{message.Location}.metrics.monitor.azure.com/subscriptions/{message.SubscriptionID}/metrics:getBatch?timespan={timeSpan}&interval=PT1M&metricnames=SuccessfulPullCount,TotalPullCount,SuccessfulPushCount,TotalPushCount&aggregation=average&metricNamespace={message.Type}&autoadjusttimegrain=true&api-version=2023-03-01-preview";
            }
            if (message.Type == "microsoft.operationalinsights/workspaces")
            {
                batchUrl = $"https://{message.Location}.metrics.monitor.azure.com/subscriptions/{message.SubscriptionID}/metrics:getBatch?timespan={timeSpan}&interval=PT1M&metricnames=AvailabilityRate_Query&aggregation=average&metricNamespace={message.Type}&autoadjusttimegrain=true&api-version=2023-03-01-preview";
            }
            log.LogInformation($"Batch url: {batchUrl}");

            string currTime = timeSpan.Split('/')[0];
            string currResource = message.Type.Substring(message.Type.IndexOf('/') + 1);
            string filePrefix = $"{message.Location}_{message.SubscriptionID}_{currTime}_{currResource}";
            log.LogInformation($"Storage Blob File Prefix: {filePrefix}");

            using HttpRequestMessage httpRequest = new HttpRequestMessage(HttpMethod.Post, batchUrl);

            string msftTenantId = config.GetValue<string>("msftTenantId");

            string tenantId = message.TenantId;

            

            // If Tenant Id from the Message Queue is not null
            
            if(tenantId != null && tenantId != msftTenantId)
            {
                log.LogInformation($"Tenant Id: {tenantId}");
                if(keyVaultManager == null)
                {
                      keyVaultManager = new KeyVaultManager(config, log);
                }
                Tenant tenant = keyVaultManager.GetServicePrincipalCredential(tenantId);
                string clientId = tenant.ClientId;
                string clientSecret = tenant.ClientSecret;
                log.LogInformation(clientId);
                
                spCredential =  new ClientSecretCredential(tenantId, clientId, clientSecret);
                log.LogInformation("Done ClientSecretCredential");
                
                accessToken = spCredential.GetToken(new TokenRequestContext(new[] { "https://metrics.monitor.azure.com/.default" }));     
                log.LogInformation("Got accessToken");

            }
            else
            {
                log.LogInformation($"MSFT Tenant Id: {tenantId}");
                string userAssignedClientId = config.GetValue<string>("msiclientId");
                var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions { ManagedIdentityClientId = userAssignedClientId });
                accessToken = credential.GetToken(new TokenRequestContext(new[] { "https://metrics.monitor.azure.com/" }));
            }
            
            
            httpRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken.Token);

            httpRequest.Content = new StringContent(jsonResouces, Encoding.UTF8, "application/json");
  
            using var response = await _httpClient.SendAsync(httpRequest);

            //TODO: Logging and not throwing. Confirm that this is correct approach
            if (response is { StatusCode: >= HttpStatusCode.BadRequest })
            {
                log.LogInformation("Something went wrong with the Monitor API call");
                log.LogInformation($"Response status code: {response.StatusCode}");
            }
            log.LogInformation("Sucess response from Monitor API call");

            var responseContent = await response.Content.ReadAsStringAsync(); //TODO: Should handle as stream and not bring into memory as a string. // see later converting string back to a stream in IngestToAdx2Async, AppendToBlobAsync

            var adx = new AdxClientHelper(config, log); 
            await adx.IngestToAdx2Async(responseContent, message.ResultTable, filePrefix);
        }
    }
}