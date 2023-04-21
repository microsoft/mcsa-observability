
using Azure.Identity;
using Azure.ResourceManager;
using Azure.ResourceManager.ResourceGraph;
using Azure.ResourceManager.ResourceGraph.Models;
using Observability.Utils.Data;
using Microsoft.Azure.Management.ResourceGraph.Models;
using Newtonsoft.Json;
using System.Text;

namespace Observability.Utils
{
    public class ResourceGraphHelper
    {
        ArmClient client;

        public ResourceGraphHelper(IConfiguration config)
        {

            client = new ArmClient(
                new ManagedIdentityCredential(config.GetValue<string>("msiclientId")));
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