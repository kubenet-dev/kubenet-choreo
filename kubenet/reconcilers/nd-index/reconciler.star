load("core.network.kubenet.dev.networkdesigns.star", "get_ipindex", "get_asindex", "get_genidindex")

def reconcile(self):
  # self = networkdesign
  ipindex = get_ipindex(self)
  rsp = client_create(ipindex)
  if rsp["error"] != None:
    return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])

  asindex = get_asindex(self)
  rsp = client_create(asindex)
  if rsp["error"] != None:
    return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])
  
  #genidindex = get_genidindex(self)
  #rsp = client_create(genidindex)
  #if rsp["error"] != None:
  #  return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])

  return reconcile_result(self, False, 0, "", False)
