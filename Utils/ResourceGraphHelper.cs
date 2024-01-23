
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
       
        string KEY_VAULT_NAME = "ngobservone-kv";
        string TENANT_SECRET_PREFIX = "tenant-";
        SecretClient keyVaultClient;

        Tenant tenantObj;

        public ResourceGraphHelper(IConfiguration config, ILogger log, string tenantId)
        {
            try{
                log.LogInformation($"Creating Arm Client for {tenantId}");
                string keyVaultName = config.GetValue<string>("keyVaultName");

                
                string clientId = "";
                string clientSecret = "";

                client = new ArmClient(
                     new ManagedIdentityCredential(config.GetValue<string>("msiclientId")));
                // Added for keyvault client

                //var tenant = client.GetTenants().FirstOrDefault();

                log.LogInformation("Reading the KeyVault");
                if(tenantId == null)
                {
                    log.LogInformation($"Error Something went wrong TenantId is null");
                    throw new Exception($"Message failed to get the TenantId");
                }
                log.LogInformation($"Reading the KeyVault for tenantId {tenantId}");

                var kvUri = "https://" + keyVaultName + ".vault.azure.net";


                var msiCredential = new ManagedIdentityCredential(config.GetValue<string>("msiclientId"));


                 keyVaultClient = new SecretClient(new Uri(kvUri), msiCredential);

                var keyName = TENANT_SECRET_PREFIX+tenantId;

                var secret = keyVaultClient.GetSecret(keyName).Value;
                KeyVaultSecret keyValueSecret =  keyVaultClient.GetSecret(keyName);
                
                log.LogInformation("Below is the keyvault value");
                log.LogInformation(keyValueSecret.Value);

                string keyValueSecretStr = keyValueSecret.Value;
                if (keyValueSecretStr == null)
                {
                    log.LogInformation("Please Add service principal values for tenantId");
                    throw new ArgumentNullException($"Secret not found in the keyvault");
                }


                //var keyValueSecretStr ="{\"clientId\":\"myId\",\"tenantid\":\"mytenant\",\"ClientSecret\":\"mysecret\"}";

                tenantObj = System.Text.Json.JsonSerializer.Deserialize<Tenant>(keyValueSecretStr);

                if(tenantObj != null) {
                    log.LogInformation(tenantObj.ToString());
                    log.LogInformation(tenantObj.ClientId);
                    log.LogInformation(tenantObj.Tenantid);
                    
                    clientId = tenantObj.ClientId;
                    clientSecret = tenantObj.ClientSecret;
                }
                
                
                var credential = new ClientSecretCredential(tenantId, clientId, clientSecret);
                client = new ArmClient(
                    credential);

                
               
                log.LogInformation("Created new Arm Client successfully");
                // throw new Exception($"dummy exception failed to get the keyVault");

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