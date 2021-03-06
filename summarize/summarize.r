library(plotrix)

vars = c('(Intercept)', 'X1', 'X2', 'X3', 'X4', 'X5')
params = c('bw', 'sigma2', 'loss.local', 's')

args = commandArgs(trailingOnly=TRUE)
root = paste(as.character(args[1]), "/", sep="")
cluster = as.integer(args[2])
#cluster = 89

B = 100
N = 30
coord = seq(0, 1, length.out=N)

#Establish the simulation parameters
tau = rep(0.03, 8)
rho = rep(0, 8)
sigma.tau = rep(0, 8)
params = data.frame(tau, rho, sigma.tau)

N = 30
settings = 1:12
nsims = 100
nvars = 5

coord = seq(0, 1, length.out=N)


sim.modes = c("gwr", "enet", "glmnet", "unshrunk.enet", "unshrunk.glmnet", "oracular")
selection.modes = c("enet", "glmnet")
file.endings = list(gwr=".gwr.csv", enet=".enet.csv", glmnet=".glmnet.csv",
                        unshrunk.enet=".unshrunk.enet.csv",
                        unshrunk.glmnet=".unshrunk.glmnet.csv", oracular=".oracle.csv")

Y.err = list()
X.err = lapply(1:nvars, function(x) {list()})
bandwidth = list()
selection = list()

for (m in sim.modes) {
    Y.err[[m]] = list()
    for (i in 1:nvars) {X.err[[i]][[m]] = list()}
}

for (m in selection.modes) {
    selection[[m]] = list()
    bandwidth[[m]] = list()
}

#remove the simulations that failed during their runs.
sims = lapply(settings, function(x) {as.character(1:nsims)})

for (setting in settings) {
	cat(paste("Begin setting ", setting, ".\n", sep=""))

    ##########################################################
    #Get the true coefficient values for this setting:
    B = list()
    B[['(Intercept)']] = rep(0, N**2)

    if ((setting-1) %/% 4 == 0) {
        B[['X1']] = matrix(rep(ifelse(coord<=0.4, 0, ifelse(coord<0.6,5*(coord-0.4),1)), N), N, N)
    } else if ((setting-1) %/% 4 == 1) {
        B[['X1']] = matrix(rep(coord, N), N, N)
    } else if ((setting-1) %/% 4 == 2) {
        Xmat = matrix(rep(rep(coord, times=N), times=N), N**2, N**2)
        Ymat = matrix(rep(rep(coord, each=N), times=N), N**2, N**2)
        D = (Xmat-t(Xmat))**2 + (Ymat-t(Ymat))**2
        d = D[435,]
        B[['X1']] = matrix(max(d)-d, N, N)
    }

    B[['X2']] = rep(0, N**2)
    B[['X3']] = rep(0, N**2)
    B[['X4']] = rep(0, N**2)
    B[['X5']] = rep(0, N**2)
    ##########################################################

    for (m in selection.modes) {
        selection[[m]][[setting]] = list()
        bandwidth[[m]][[setting]] = list()
    }

    for (m in sim.modes) {
        Y.err[[m]][[setting]] = list()
        for (i in 1:nvars) {X.err[[i]][[m]][[setting]] = list()}
    }


    vars = c('(Intercept)', 'X1', 'X2', 'X3', 'X4', 'X5')

    for (k in sims[[setting]]) {
        sim = (setting-1)*100 + as.numeric(k) - 1
        cat(paste("Begin simulation ", sim, ".\n", sep=""))

        #Get the raw data
        filename = paste(root, "output/Data.", cluster, ".", sim, ".csv", sep="")
        if (file.exists(filename)) {
            raw = read.csv(filename, header=TRUE)

            for (m in sim.modes) {
                filename = paste(root, "output/CoefEstimates.", cluster, ".", sim, file.endings[[m]], sep="")
                estimates = read.csv(filename, header=TRUE)
                colnames(estimates) = vars
            
                if (!is.na(pmatch("unshrunk", m))) {
                    fitted = diag(as.matrix(estimates) %*% t(as.matrix(cbind(rep(1,N**2), raw[,c('X1','X2','X3','X4','X5')]))))
                } else {
                    filename = paste(root, "output/MiscParams.", cluster, ".", sim, file.endings[[m]], sep="")
                    params = read.csv(filename, header=TRUE)
                    fitted = params$fitted
                }

                for (i in 1:nvars) {
                    name = paste("X", i, sep="")
                    X.err[[i]][[m]][[setting]][[k]] = as.vector(B[[name]] - estimates[,name])
                }
                Y.err[[m]][[setting]][[k]] = as.vector(raw$Y - fitted)

                if (m %in% selection.modes) {
                    filename = paste(root, "output/MiscParams.", cluster, ".", sim, file.endings[[m]], sep="")
                    params = read.csv(filename, header=TRUE)
                    bandwidth[[m]][[setting]][[k]] = params$bw

                    for (v in vars[-1]) {
                        cat(paste("Begin variable ", v, "\n", sep=""))

                        #Calculate how often each variable was selected for inclusion in the local models
                        col = which(colnames(estimates) == v)
                        if (k==1) {
                            selection[[m]][[setting]][[v]] = as.matrix(ifelse(estimates[,col]==0, 0, 1))
                        } else {
                            selection[[m]][[setting]][[v]] = cbind(selection[[m]][[setting]][[v]], as.matrix(ifelse(estimates[,col]==0, 0, 1)))
                        }
                    }
                }
            }
        }
    }
}

#Write the summary to disk
save.image(file=paste(root, "sim-", cluster, ".Rdata", sep=""))

