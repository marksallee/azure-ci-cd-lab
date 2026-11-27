environment  = "prod"
min_replicas = 0 # lab setting: scales to zero so nothing runs between demos (first request has a cold start). A real prod would set 1+.
max_replicas = 2
