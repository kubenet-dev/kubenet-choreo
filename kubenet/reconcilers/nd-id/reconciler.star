load("core.network.kubenet.dev.networkdesigns.star", "get_asclaims")

def reconcile(self):
  # self = networkdesign

  if is_conditionready(self, "IndexReady") != True:
    return reconcile_result(self, True, 0, "index not ready", False)

  as_claims = get_asclaims(self)
  for as_claim in as_claims:
    rsp = client_create(as_claim)
    if rsp["error"] != None:
      return reconcile_result(self, True, 0, rsp["error"], rsp["fatal"])

  return reconcile_result(self, False, 0, "", False)
