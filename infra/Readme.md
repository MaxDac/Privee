## Private DNS Zone

```bash
az network private-dns record-set list --resource-group <ResourceGroupName> --zone-name <PrivateDNSZoneName> --query "[].fqdn"
```

This gets all the qualified DNSs. The DB entry should use the Private DNS Zone name as a suffix, i.e. `ed6c59338ca8.privee-db.private.postgres.database.azure.com` where the Private DNS Zone name is `privee-db.private.postgres.database.azure.com`

