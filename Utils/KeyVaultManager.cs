
using Azure.Identity;
using Observability.Utils.Data;
using Azure.Security.KeyVault.Secrets;
using Newtonsoft.Json;


namespace Observability.Utils
{
    //TODO: Make methods asynchronous
    public class KeyVaultManager
    {

        string TENANT_SECRET_PREFIX = "tenant-";
        SecretClient keyVaultClient;
        ILogger log;

        public KeyVaultManager(IConfiguration config, ILogger log)
        {
            this.log = log;
            try
            {
                string keyVaultName = config.GetValue<string>("keyVaultName");
                log.LogInformation("Reading the KeyVault");

                var kvUri = "https://" + keyVaultName + ".vault.azure.net";

                var msiCredential = new ManagedIdentityCredential(config.GetValue<string>("msiclientId"));

                keyVaultClient = new SecretClient(new Uri(kvUri), msiCredential);

                if (keyVaultClient == null)
                {
                    log.LogInformation("KeyVault client is null");
                    throw new ArgumentNullException($"Please check the keyVaultName");
                }

            }
            catch (Exception e)
            {
                log.LogInformation("Exception failed to create a keyvault");
                log.LogError(e.Message);
                throw new Exception($"Message {e.Message} failed to get the keyVault");
            }
        }

        public Tenant GetServicePrincipalCredential(string tenantId)
        {
            Tenant tenantObj = new Tenant();
            var keyName = TENANT_SECRET_PREFIX + tenantId;

            var secret = keyVaultClient.GetSecret(keyName).Value;
            KeyVaultSecret keyValueSecret = keyVaultClient.GetSecret(keyName);

            log.LogInformation("Below is the keyvault value");
            log.LogInformation(keyValueSecret.Value);

            string keyValueSecretStr = keyValueSecret.Value;
            if (keyValueSecretStr == null)
            {
                log.LogInformation("Please Add service principal values for tenantId");
                throw new ArgumentNullException($"Secret not found in the keyvault");
            }
            tenantObj = System.Text.Json.JsonSerializer.Deserialize<Tenant>(keyValueSecretStr);

            return tenantObj;
        }


    }
}