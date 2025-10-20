# Rscript --no-save --no-restore --verbose test/base.R > test/log/base.R.log 2>&1

library(did)
library(haven)
library(foreign)
library(here)

source(file.path(here(), "test/common.R"))
set.seed(09142024)

tmp    <- file.path(here(), "tmp")
sp     <- did::reset.sim()
sp$ipw <- FALSE
data   <- did::build_sim_dataset(sp)
write_dta(data, file.path(tmp, "base.dta"))

methods <- c("drimp", "dripw", "reg", "stdipw")
aggtyps <- c("simple", "group", "calendar", "dynamic")
kwargs  <- list(data        = data,
                yname       = "Y",
                tname       = "period",
                gname       = "G",
                idname      = "id",
                xformla     = ~X,
                panel       = FALSE,
                cband       = FALSE,
                bstrap      = FALSE)

results <- list()
for ( m in methods ) {
    print(m); results[[m]] <- do.call(att_gt, c(kwargs, list(est_method=m)))
}

aggres <- list()
for ( m in methods ) {
    res <- results[[m]]
    for ( typ in aggtyps ) {
        print(c(m, typ)); aggres[[paste(m, typ, sep="_")]] <- aggte(res, type=typ)
    }
}

dir.create(tmp, showWarnings=F)
for ( m in methods ) {
    res <- results[[m]]
    out <- cbind(res$att,  sqrt(diag(as.matrix(res$V_analytical)) /res$n))
    .savemat(file.path(tmp, paste("tmpbase", m, sep="_")), out)
    for ( typ in aggtyps ) {
        agg <- aggres[[paste(m, typ, sep="_")]]
        all <- cbind(agg$overall.att, agg$overall.se)
        row <- cbind(agg$att.egt,     agg$se.egt)
        .savemat(file.path(tmp, paste("tmpbase", m, typ, sep="_")), rbind(all, row))
    }
}
