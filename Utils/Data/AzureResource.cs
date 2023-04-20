namespace Observability.Utils.Data
{
    public class AzureResource
    {
        public string ID { get; set; }
        public string Name { get; set; }
        public string SubscriptionId { get; set; }
        public string Location { get; set; }

        public AzureResource()
        {
            ID = Name = SubscriptionId = Location = "";
        }
    }
}