## Load your packages, e.g. library(targets).
source("./packages.R")
source("./conflicts.R")

## Load your R files
lapply(list.files("./R", full.names = TRUE), source)

## tar_plan supports drake-style targets and also tar_target()
tar_plan(

 fig_surv_bm = viz_surv_bm(eval_metric = 'ibs_scaled'),

 fig_penguins = viz_penguins()

)
