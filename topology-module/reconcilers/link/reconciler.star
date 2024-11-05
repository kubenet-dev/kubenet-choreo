def reconcile(self):
  # self = link
  namespace = self.get("metadata", {}).get("namespace", "")

  for ep in self.get("spec", {}).get("endpoints", []):
    endpoint = get_resource("infra.kuid.dev/v1alpha1", "Endpoint")
    items = [
      ep.get("partition", ""),
      ep.get("region", ""),
      ep.get("site", ""),
      ep.get("node", ""),
      str(int(ep.get("port", 0))),
      ep.get("adaptor", ""),
      str(int(ep.get("endpoint", 0))),
    ]
    name = ".".join(items)
    
    rsp = client_get(name, namespace, endpoint["resource"])
    if rsp["error"] != None:
      return reconcile_result(self, True, 0, "endpoint " + name + " err: " + rsp["error"], False)
    # happy path
    return reconcile_result(self, False, 0, "", False)
  # should lever happen since validation check for 2 endpoints in a link
  return reconcile_result(self, False, 0, "link w/o endpoints", False)