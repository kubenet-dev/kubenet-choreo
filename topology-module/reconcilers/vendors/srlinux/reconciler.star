load("device.network.kubenet.dev.nodetemplates.star", "get_node_template", "build_port", "build_adaptor", "build_endpoint")

def reconcile(self):
  # self = node
  provider = self.get("spec", {}).get("provider", None)
  platformType = self.get("spec", {}).get("platformType", None)
  namespace = self.get("metadata", {}).get("namespace", None)

  nodeTemplate, err = get_node_template(".".join([provider, platformType]), namespace)
  if err != None:
    return reconcile_result(self, True, 0, err, False)
          
  for port in nodeTemplate.get("spec", {}).get("ports", []):
    start = port.get("ids", {}).get("start", 0)
    end = port.get("ids", {}).get("end", 0)
    for portID in range(int(start), int(end) + 1):
      rsp = client_create(build_port(self, portID))
      if rsp["error"] != None:
        return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])

      adaptor = port.get("adaptor", {})
      rsp = client_create(build_adaptor(self, portID, adaptor))
      if rsp["error"] != None:
        return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])

      connectors = port.get("ids", {}).get("adaptor", {}).get("connectors", 1)
      for connectorID in range(int(1), int(connectors) + 1):
        rsp = client_create(build_endpoint(self, portID, adaptor, connectorID))
        if rsp["error"] != None:
          return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])
  
  return reconcile_result(self, False, 0, "", False)
