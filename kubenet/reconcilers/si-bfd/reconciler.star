def reconcile(self):
  # self = si
  # todo need to check if bfd needs to be enabled or not
        
  rsp = client_create(get_bfd(self))
  if rsp["error"] != None:
    return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])
  
  return reconcile_result(self, False, 0, "", False)


def get_bfd(si):
  spec = si.get("spec", {})

  bfd_spec = {
      "partition": spec.get("partition", ""),
      "region": spec.get("region", ""),
      "site": spec.get("site", ""),
      "node": spec.get("node", ""),
      "port": int(spec.get("port", 0)),
      "endpoint": int(spec.get("endpoint", 0)),
      "name": spec.get("name", ""),
      "id": int(spec.get("id", 0)),
      "enabled": True,
      "minTx": spec.get("minTx", None),
      "minRx": spec.get("minRx", None),
      "minEchoRx": spec.get("minEchoRx", None),
      "multiplier": spec.get("multiplier", None),
      "ttl": spec.get("ttl", None),
    }
  
  # Create a new dictionary excluding None values
  filtered_bfd_spec = {}
  for key, value in bfd_spec.items():
     if value != None:
         filtered_bfd_spec[key] = value

  bfd = {
    "apiVersion": "device.network.kubenet.dev/v1alpha1",
    "kind": "BFD",
    "metadata": {
      "name": si.get("metadata", {}).get("name", ""),
      "namespace": si.get("metadata", {}).get("namespace", ""),
    },
    "spec": filtered_bfd_spec
  }
  return bfd
  