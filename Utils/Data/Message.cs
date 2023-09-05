using Microsoft.Azure.Management.ResourceManager.Fluent.Models;

namespace Observability.Utils.Data
{
    public class Message
    {
        public string Type { get; set; }
        public string Metric { get; set; }
        public string SubscriptionID { get; set; }
        public string Location { get; set; }
        public DateTime From { get; set; }
        public DateTime To { get; set; }
        public string ResultTable { get; set; }
        public List<AzureResource> Resources { get; set; }

        public Message()
        {
            SubscriptionID = Location = Type = ResultTable = "";
            Resources = new List<AzureResource>();
        }
    }
}