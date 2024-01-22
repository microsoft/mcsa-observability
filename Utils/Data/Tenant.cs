namespace Observability.Utils.Data
{
    public class Tenant
    {
        public string ClientId { get; set; }
        public string ClientSecretId { get; set; }
        public string TenantId { get; set; }
        

        public Tenant()
        {
            ClientId = ClientSecretId = TenantId =  "";
        }
    }
}