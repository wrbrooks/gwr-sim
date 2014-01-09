write.log = function(message, file, append=TRUE) {
    sink(file, append=append)
    cat(message)
    sink()
}

write.log('entry\n', 'result.txt', append=FALSE)

#Set ourselves up to import the packages:
r = getOption("repos")
r["CRAN"] = "http://cran.wustl.edu"
options(repos = r)
rm(r)
dir.create("rlibs")
Sys.setenv(R_LIBS="rlibs")
.libPaths(new="rlibs")
install.packages("sp")
install.packages("scales")
install.packages("foreach")
install.packages("iterators")
install.packages("multicore")
install.packages("geoR")
install.packages("glmnet")
install.packages("lars")
install.packages("maptools")
install.packages("R-libs/gwselect", repos=NULL, type='source')

require(sp)
require(scales)
require(foreach)
require(iterators)
require(multicore)
require(geoR)
require(glmnet)
require(lars)
require(maptools)
require(gwselect)

write.log('installations complete\n', 'result.txt')

dir.create('output')
seeds = as.vector(read.csv("seeds.txt", header=FALSE)[,1])
B = 100
N = 30
settings = 9
functions = 3
coord = seq(0, 1, length.out=N)

#Establish the simulation parameters
tau = rep(0.1, settings)
rho = rep(c(0, 0.5, 0.9), functions)
params = data.frame(tau, rho)

#Read the cluster and process arguments
args = scan('jobid.txt', 'character')
args = strsplit(args, '\\n', fixed=TRUE)[[1]]
cluster = args[1]
process = as.integer(args[2])

write.log(paste('process:', args[2], "\n", sep=''), 'result.txt')

#Simulation parameters are based on the value of process
setting = process %/% B + 1
parameters = params[setting,]
set.seed(seeds[process+1])

#Generate the covariates:
if (parameters[['tau']] > 0) {
    d1 = grf(n=N**2, grid='reg', cov.model='exponential', cov.pars=c(1,parameters[['tau']]))$data
    d2 = grf(n=N**2, grid='reg', cov.model='exponential', cov.pars=c(1,parameters[['tau']]))$data
    d3 = grf(n=N**2, grid='reg', cov.model='exponential', cov.pars=c(1,parameters[['tau']]))$data
    d4 = grf(n=N**2, grid='reg', cov.model='exponential', cov.pars=c(1,parameters[['tau']]))$data
    d5 = grf(n=N**2, grid='reg', cov.model='exponential', cov.pars=c(1,parameters[['tau']]))$data
} else {
    d1 = rnorm(N**2, mean=0, sd=1)
    d2 = rnorm(N**2, mean=0, sd=1)
    d3 = rnorm(N**2, mean=0, sd=1)
    d4 = rnorm(N**2, mean=0, sd=1)
    d5 = rnorm(N**2, mean=0, sd=1)
}

loc.x = rep(coord, times=N)
loc.y = rep(coord, each=N)

#Use the Cholesky decomposition to correlate the random fields:
S = matrix(parameters[['rho']], 5, 5)
diag(S) = rep(1, 5)
L = chol(S)

#Force correlation on the Gaussian random fields:
D = as.matrix(cbind(d1, d2, d3, d4, d5)) %*% L
    
#
X1 = matrix(D[,1], N, N)
X2 = matrix(D[,2], N, N)
X3 = matrix(D[,3], N, N)
X4 = matrix(D[,4], N, N)
X5 = matrix(D[,5], N, N)

if ((setting-1) %/% 3 == 0) {
    B1 = matrix(rep(ifelse(coord<=0.4, 0, ifelse(coord<0.6,5*(coord-0.4),1)), N), N, N)
} else if ((setting-1) %/% 3 == 1) {
    B1 = matrix(rep(coord, N), N, N)
} else if ((setting-1) %/% 3 == 2) {
    Xmat = matrix(rep(rep(coord, times=N), times=N), N**2, N**2)
    Ymat = matrix(rep(rep(coord, each=N), times=N), N**2, N**2)
    D = (Xmat-0.5)**2 + (Ymat-0.5)**2
    d = D[,435]
    B1 = matrix(max(d)-d, N, N)
}


mu = X1*B1
Y = rpois(length(mu), lambda=exp(mu))

sim = data.frame(Y=as.vector(Y), X1=as.vector(X1), X2=as.vector(X2), X3=as.vector(X3), X4=as.vector(X4), X5=as.vector(X5), loc.x, loc.y)
fitloc = cbind(rep(seq(0,1, length.out=N), each=N), rep(seq(0,1, length.out=N), times=N))

vars = cbind(B1=as.vector(B1!=0))#, B2=as.vector(B2!=0), B3=as.vector(B3!=0))
oracle = list()
for (i in 1:N**2) { 
    oracle[[i]] = character(0)
    if (vars[i,'B1']) { oracle[[i]] = c(oracle[[i]] , "X1") }
}

write.log('generated the data.\n', 'result.txt')

#MODELS:
write.log('make GWAL-LLE model.\n', 'result.txt')
bw.glmnet = gwglmnet.sel(Y~X1+X2+X3+X4+X5-1, data=sim, family='poisson', alpha=1, coords=sim[,c('loc.x','loc.y')], longlat=FALSE, mode.select='BIC', gweight=spherical, tol.bw=0.01, bw.method='knn', adapt=TRUE, precondition=FALSE, parallel=FALSE, interact=TRUE, verbose=TRUE, shrunk.fit=FALSE, bw.select='AICc', resid.type='pearson')
model.glmnet = gwglmnet(Y~X1+X2+X3+X4+X5-1, data=sim, family='poisson', alpha=1, coords=sim[,c('loc.x','loc.y')], longlat=FALSE, N=1, mode.select='BIC', bw=bw.glmnet[['bw']], gweight=spherical, bw.method='knn', simulation=TRUE, adapt=TRUE, precondition=FALSE, parallel=FALSE, interact=TRUE, verbose=TRUE, shrunk.fit=FALSE)

write.log('make GWEN-LLE model.\n', 'result.txt')
bw.enet = gwglmnet.sel(Y~X1+X2+X3+X4+X5-1, data=sim, family='poisson', alpha='adaptive', coords=sim[,c('loc.x','loc.y')], longlat=FALSE, mode.select='BIC', gweight=spherical, tol.bw=0.01, bw.method='knn', adapt=TRUE, precondition=FALSE, parallel=FALSE, interact=TRUE, verbose=TRUE, shrunk.fit=FALSE, bw.select='AICc', resid.type='pearson')
model.enet = gwglmnet(Y~X1+X2+X3+X4+X5-1, data=sim, family='poisson', alpha='adaptive', coords=sim[,c('loc.x','loc.y')], longlat=FALSE, N=1, mode.select='BIC', bw=bw.enet[['bw']], gweight=spherical, bw.method='knn', simulation=TRUE, adapt=TRUE, precondition=FALSE, parallel=FALSE, interact=TRUE, verbose=TRUE, shrunk.fit=FALSE)

write.log('make oracular model.\n', 'result.txt')
bw.oracular = gwglmnet.sel(Y~X1+X2+X3+X4+X5-1, data=sim, family='poisson', oracle=oracle, coords=sim[,c('loc.x','loc.y')], longlat=FALSE, gweight=spherical, tol.bw=0.01, bw.method='knn', parallel=FALSE, interact=TRUE, verbose=TRUE, shrunk.fit=FALSE, bw.select='AICc', resid.type='pearson')
model.oracular = gwglmnet(Y~X1+X2+X3+X4+X5-1, data=sim, family='poisson', oracle=oracle, coords=sim[,c('loc.x','loc.y')], longlat=FALSE, N=1, bw=bw.oracular[['bw']], gweight=spherical, bw.method='knn', simulation=TRUE, parallel=FALSE, interact=TRUE, verbose=TRUE, shrunk.fit=FALSE)

write.log('make GWR-LLE model.\n', 'result.txt')
oracle2 = lapply(1:900, function(x) {return(c("X1", "X2", "X3", "X4", "X5"))})
bw.gwr = gwglmnet.sel(Y~X1+X2+X3+X4+X5-1, data=sim, family='poisson', oracle=oracle2, coords=sim[,c('loc.x','loc.y')], longlat=FALSE, gweight=spherical, tol.bw=0.01, bw.method='knn', parallel=FALSE, interact=TRUE, verbose=TRUE, shrunk.fit=FALSE, bw.select='AICc', resid.type='pearson')
model.gwr = gwglmnet(Y~X1+X2+X3+X4+X5-1, data=sim, family='poisson', oracle=oracle2, coords=sim[,c('loc.x','loc.y')], longlat=FALSE, N=1, bw=bw.oracular[['bw']], gweight=spherical, bw.method='knn', simulation=TRUE, parallel=FALSE, interact=TRUE, verbose=TRUE, shrunk.fit=FALSE)


#OUTPUT:

#First, write the data
write.log('write the data.\n', 'result.txt')
write.table(sim, file=paste("output/Data.", cluster, ".", process, ".csv", sep=""), sep=',', row.names=FALSE)


#glmnet:
write.log('summarize the GWAL-LLE model.\n', 'result.txt')
vars = c('(Intercept)', 'X1', 'X2', 'X3', 'X4', 'X5')

coefs = t(sapply(1:N**2, function(y) {as.vector(model.glmnet[['model']][['models']][[y]][['coef']])}))
write.table(coefs, file=paste("output/CoefEstimates.", cluster, ".", process, ".glmnet.csv", sep=""), col.names=vars, sep=',', row.names=FALSE)

coefs = t(sapply(1:N**2, function(y) {as.vector(model.glmnet[['model']][['models']][[y]][['coef.unshrunk']])}))
write.table(coefs, file=paste("output/CoefEstimates.", cluster, ".", process, ".unshrunk.glmnet.csv", sep=""), col.names=vars, sep=',', row.names=FALSE)

params = c('bw', 'sigma2', 'loss.local', 's2.unshrunk', 'fitted')
target = params[1]
output = sapply(1:N**2, function(y) {model.glmnet[['model']][['models']][[y]][[target]]})

for (i in 2:length(params)) {
    target = params[i]
    output = cbind(output, sapply(1:N**2, function(y) {model.glmnet[['model']][['models']][[y]][[target]]}))
}
write.table(output, file=paste("output/MiscParams.", cluster, ".", process, ".glmnet.csv", sep=""), col.names=params, sep=',', row.names=FALSE)






#enet:
write.log('summarize the GWEN-LLE model.\n', 'result.txt')
vars = c('(Intercept)', 'X1', 'X2', 'X3', 'X4', 'X5')

coefs = t(sapply(1:N**2, function(y) {as.vector(model.enet[['model']][['models']][[y]][['coef']])}))
write.table(coefs, file=paste("output/CoefEstimates.", cluster, ".", process, ".enet.csv", sep=""), col.names=vars, sep=',', row.names=FALSE)

coefs = t(sapply(1:N**2, function(y) {as.vector(model.enet[['model']][['models']][[y]][['coef.unshrunk']])}))
write.table(coefs, file=paste("output/CoefEstimates.", cluster, ".", process, ".unshrunk.enet.csv", sep=""), col.names=vars, sep=',', row.names=FALSE)

params = c('bw', 'sigma2', 'loss.local', 's2.unshrunk', 'fitted')
target = params[1]
output = sapply(model.enet[['model']][['models']], function(y) {y[[target]]})

for (i in 2:length(params)) {
    target = params[i]
    output = cbind(output, sapply(model.enet[['model']][['models']], function(y) {y[[target]]}))
}
write.table(output, file=paste("output/MiscParams.", cluster, ".", process, ".enet.csv", sep=""), col.names=params, sep=',', row.names=FALSE)








#For oracle property:
write.log('summarize the oracle model.\n', 'result.txt')
vars = c('(Intercept)', 'X1', 'X2', 'X3', 'X4', 'X5')

coefs = t(sapply(1:N**2, function(y) {as.vector(model.oracular[['model']][['models']][[y]][['coef']])}))
write.table(coefs, file=paste("output/CoefEstimates.", cluster, ".", process, ".oracle.csv", sep=""), col.names=vars, sep=',', row.names=FALSE)

params = c('bw', 'sigma2', 'loss.local', 'fitted')
target = params[1]
output = sapply(1:N**2, function(y) {model.oracular[['model']][['models']][[y]][[target]]})

for (i in 2:length(params)) {
    target = params[i]
    output = cbind(output, sapply(1:N**2, function(y) {model.oracular[['model']][['models']][[y]][[target]]}))
}
write.table(output, file=paste("output/MiscParams.", cluster, ".", process, ".oracle.csv", sep=""), col.names=params, sep=',', row.names=FALSE)





#For all vars:
write.log('summarize the GWR-LLE model.\n', 'result.txt')
vars = c('(Intercept)', 'X1', 'X2', 'X3', 'X4', 'X5')

coefs = t(sapply(1:N**2, function(y) {as.vector(model.gwr[['model']][['models']][[y]][['coef']])}))
write.table(coefs, file=paste("output/CoefEstimates.", cluster, ".", process, ".gwr.csv", sep=""), col.names=vars, sep=',', row.names=FALSE)

params = c('bw', 'sigma2', 'loss.local', 'fitted')
target = params[1]
output = sapply(1:N**2, function(y) {model.gwr[['model']][['models']][[y]][[target]]})

for (i in 2:length(params)) {
    target = params[i]
    output = cbind(output, sapply(1:N**2, function(y) {model.gwr[['model']][['models']][[y]][[target]]}))
}
write.table(output, file=paste("output/MiscParams.", cluster, ".", process, ".gwr.csv", sep=""), col.names=params, sep=',', row.names=FALSE)

write.log('done.\n', 'result.txt')
