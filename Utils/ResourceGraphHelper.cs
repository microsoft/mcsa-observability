
using Azure.Identity;
using Azure.ResourceManager;
using Azure.ResourceManager.ResourceGraph;
using Azure.ResourceManager.ResourceGraph.Models;
using Observability.Utils.Data;
using Microsoft.Azure.Management.ResourceGraph.Models;
using Newtonsoft.Json;
using System.Text;
using Azure.Security.KeyVault.Secrets;


namespace Observability.Utils
{
    //TODO: Make methods asynchronous
    public class ResourceGraphHelper
    {
        ArmClient client;

        Tenant tenantObj;

        private static KeyVaultManager keyVaultManager = null;

        public ResourceGraphHelper(IConfiguration config, ILogger log, string tenantId)
        {
            try{
                log.LogInformation($"Creating Arm Client for {tenantId}");
                            
                string clientId = "";
                string clientSecret = "";

                //client = new ArmClient(
                     // new ManagedIdentityCredential(config.GetValue<string>("msiclientId")));
                // Commentted for MultiTenant changes

                //var tenant = client.GetTenants().FirstOrDefault();
                if(tenantId == null)
                {
                    log.LogInformation($"Error Something went wrong TenantId is null");
                    throw new Exception($"Message failed to get the TenantId");
                }
                log.LogInformation($"Reading the KeyVault for tenantId {tenantId}");
                if(keyVaultManager == null)
                {
                      keyVaultManager = new KeyVaultManager(config, log);
                }

                tenantObj = keyVaultManager.GetServicePrincipalCredential(tenantId);
                

                if(tenantObj == null) {
                    log.LogInformation($"SP not defined in keyvault");
                    throw new Exception($"Message failed to get the SP credential"); 
                }
                
                clientId = tenantObj.ClientId;
                clientSecret = tenantObj.ClientSecret;
                var credential = new ClientSecretCredential(tenantId, clientId, clientSecret);
                client = new ArmClient(
                    credential);
               
                log.LogInformation("Created new Arm Client successfully");
                
            }
            catch(Exception e)
            {
                log.LogInformation("Exception failed to read secret from keyvault");
                log.LogError(e.Message);
                throw new Exception($"Message {e.Message} failed to get the keyVault");
            }
        }

        public ResourceQueryResult QueryGraph(string subscriptionId, string resourceType)
        {
            var tenant = client.GetTenants().FirstOrDefault();
  
            string query = $"Resources | where subscriptionId == '{subscriptionId}' | where type == '{resourceType}' | distinct id, name, subscriptionId, location | sort by location asc";

            var request = new QueryRequest(query);

            var queryContent = new ResourceQueryContent(query);

            var response = tenant.GetResources(queryContent);

            var result = response.Value;

            var resources = new List<AzureResource>();

            return result;
        }

        public string GetSubscriptionName(string subscriptionId)
        {
            var tenant = client.GetTenants().FirstOrDefault();
            string query = $"resourcecontainers | where id == \"/subscriptions/{subscriptionId}\" | project name";

            var request = new QueryRequest(query);

            var queryContent = new ResourceQueryContent(query);

            var response = tenant.GetResources(queryContent);
            var result = response.Value.Data;

            var stringSub = Encoding.ASCII.GetString(result);

            List<dynamic> results = JsonConvert.DeserializeObject<List<dynamic>>(stringSub);

            var subscriptionName = results[0].name;

            return subscriptionName;
        }
    }
}