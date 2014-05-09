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
install.packages("doMC")
install.packages("R-libs/RandomFields", repos=NULL, type='source')
install.packages("geoR")
install.packages("glmnet")
install.packages("maptools")
install.packages('ggplot2')
install.packages("plotrix")
install.packages("R-libs/lagr", repos=NULL, type='source')

require(sp)
require(scales)
require(foreach)
require(iterators)
require(multicore)
require(geoR)
require(glmnet)
require(maptools)
require(lagr)

write.log('installations complete\n', 'result.txt')

seeds = as.vector(read.csv("seeds.txt", header=FALSE)[,1])
B = 100
N = 30
settings = 18
functions = 3
coord = seq(0, 1, length.out=N)

#Establish the simulation parameters
tau = rep(0.1, settings)
rho = rep(c(rep(0,2), rep(0.5,2), rep(0.9,2)), functions)
sigma.tau = rep(0, settings)
sigma = rep(c(0.5,1), settings/2)
params = data.frame(tau, rho, sigma.tau, sigma)

#Read the cluster and process arguments
args = scan('jobid.txt', 'character')
args = strsplit(args, '\\n', fixed=TRUE)[[1]]
cluster = args[1]
process = as.integer(args[2]) - 1

write.log(paste('process:', process, "\n", sep=''), 'result.txt')

#Simulation parameters are based on the value of process
setting = process %/% B + 1
parameters = params[setting,]
set.seed(seeds[process+1])

write.log(paste('seed:', seeds[process+1], "\n", sep=''), 'result.txt')

#Generate the covariates:
if (parameters[['tau']] > 0) {
    write.log(paste('generating GRFs with tau of ', parameters[['tau']], sep=''), 'result.txt')
    d1 = grf(n=N**2, grid='reg', cov.model='exponential', cov.pars=c(1,parameters[['tau']]))$data
    d2 = grf(n=N**2, grid='reg', cov.model='exponential', cov.pars=c(1,parameters[['tau']]))$data
    d3 = grf(n=N**2, grid='reg', cov.model='exponential', cov.pars=c(1,parameters[['tau']]))$data
    d4 = grf(n=N**2, grid='reg', cov.model='exponential', cov.pars=c(1,parameters[['tau']]))$data
    d5 = grf(n=N**2, grid='reg', cov.model='exponential', cov.pars=c(1,parameters[['tau']]))$data
} else {
    write.log('generating GRFs with tau of 0', 'result.txt')
    d1 = rnorm(N**2, mean=0, sd=1)
    d2 = rnorm(N**2, mean=0, sd=1)
    d3 = rnorm(N**2, mean=0, sd=1)
    d4 = rnorm(N**2, mean=0, sd=1)
    d5 = rnorm(N**2, mean=0, sd=1)
}

write.log('generated GRFs', 'result.txt')

loc.x = rep(coord, times=N)
loc.y = rep(coord, each=N)

#Use the Cholesky decomposition to correlate the random fields:
S = matrix(parameters[['rho']], 5, 5)
diag(S) = rep(1, 5)
L = chol(S)

write.log('generated correlation matrix', 'result.txt')

#Force correlation on the Gaussian random fields:
D = as.matrix(cbind(d1, d2, d3, d4, d5)) %*% L
    
#
X1 = matrix(D[,1], N, N)
X2 = matrix(D[,2], N, N)
X3 = matrix(D[,3], N, N)
X4 = matrix(D[,4], N, N)
X5 = matrix(D[,5], N, N)

write.log('generated Xs', 'result.txt')

if (parameters[['sigma.tau']] == 0) {epsilon = rnorm(N**2, mean=0, sd=parameters[['sigma']])}
if (parameters[['sigma.tau']] > 0) {epsilon = grf(n=N**2, grid='reg', cov.model='exponential', cov.pars=c(parameters[['sigma']]**2,parameters[['sigma.tau']]))$data}

write.log('generated epsilon', 'result.txt')

if ((setting-1) %/% 6 == 0) {
    B1 = matrix(rep(ifelse(coord<=0.4, 0, ifelse(coord<0.6,5*(coord-0.4),1)), N), N, N)
} else if ((setting-1) %/% 6 == 1) {
    B1 = matrix(rep(coord, N), N, N)
} else if ((setting-1) %/% 6 == 2) {
    Xmat = matrix(rep(rep(coord, times=N), times=N), N**2, N**2)
    Ymat = matrix(rep(rep(coord, each=N), times=N), N**2, N**2)
    D = (Xmat-0.5)**2 + (Ymat-0.5)**2
    d = D[,435]
    B1 = matrix(max(d)-d, N, N)
    B1 = B1 / max(B1)
}

write.log('generated B1 coefficient surface', 'result.txt')

mu = X1*B1
Y = mu + epsilon

sim = data.frame(Y=as.vector(Y), X1=as.vector(X1), X2=as.vector(X2), X3=as.vector(X3), X4=as.vector(X4), X5=as.vector(X5), loc.x, loc.y)
fitloc = cbind(rep(seq(0,1, length.out=N), each=N), rep(seq(0,1, length.out=N), times=N))

vars = cbind(B1=as.vector(B1!=0))#, B2=as.vector(B2!=0), B3=as.vector(B3!=0))
oracle = list()
for (i in 1:N**2) { 
    oracle[[i]] = character(0)
    if (vars[i,'B1']) { oracle[[i]] = c(oracle[[i]] , "X1") }
}

write.log('generated data\n', 'result.txt')


#MODELS:
write.log('making lagr model.\n', 'result.txt')
bw.lagr = lagr.sel(Y~X1+X2+X3+X4+X5-1, data=sim, family='gaussian', coords=sim[,c('loc.x','loc.y')], longlat=FALSE, varselect.method='AICc', kernel=epanechnikov, tol.bw=0.01, bw.type='knn', parallel=FALSE, interact=TRUE, verbose=FALSE, bwselect.method='AICc', resid.type='pearson')
model.lagr = lagr(Y~X1+X2+X3+X4+X5-1, data=sim, family='gaussian', coords=sim[,c('loc.x','loc.y')], longlat=FALSE, N=1, varselect.method='AICc', bw=bw.lagr[['bw']], kernel=epanechnikov, bw.type='knn', simulation=TRUE, parallel=FALSE, interact=TRUE, verbose=FALSE)

#write.log('making oracular model.\n', 'result.txt')
#bw.oracular = gwglmnet.sel(Y~X1+X2+X3+X4+X5-1, data=sim, family='gaussian', oracle=oracle, coords=sim[,c('loc.x','loc.y')], longlat=FALSE, mode.select='BIC', gweight=spherical, tol.bw=0.01, bw.method='knn', parallel=FALSE, interact=TRUE, verbose=FALSE, shrunk.fit=FALSE, bw.select='AICc', resid.type='pearson')
#model.oracular = gwglmnet(Y~X1+X2+X3+X4+X5-1, data=sim, family='gaussian', oracle=oracle, coords=sim[,c('loc.x','loc.y')], longlat=FALSE, N=1, mode.select='BIC', bw=bw.oracular[['bw']], gweight=spherical, bw.method='knn', simulation=TRUE, parallel=FALSE, interact=TRUE, verbose=FALSE, shrunk.fit=FALSE)

#write.log('making gwr model.\n', 'result.txt')
#oracle2 = lapply(1:nrow(sim), function(x) {return(c("X1", "X2", "X3", "X4", "X5"))})
#bw.gwr = gwglmnet.sel(Y~X1+X2+X3+X4+X5-1, data=sim, family='gaussian', oracle=oracle, coords=sim[,c('loc.x','loc.y')], longlat=FALSE, mode.select='BIC', gweight=spherical, tol.bw=0.01, bw.method='knn', parallel=FALSE, interact=TRUE, verbose=FALSE, shrunk.fit=FALSE, bw.select='AICc', resid.type='pearson')
#model.gwr = gwglmnet(Y~X1+X2+X3+X4+X5-1, data=sim, family='gaussian', oracle=oracle2, coords=sim[,c('loc.x','loc.y')], longlat=FALSE, N=1, mode.select='BIC', bw=bw.oracular[['bw']], gweight=spherical, bw.method='knn', simulation=TRUE, parallel=FALSE, interact=TRUE, verbose=FALSE, shrunk.fit=FALSE)



#OUTPUT:

#First, write the data
write.log('write the data.\n', 'result.txt')
write.table(sim, file=paste("Data.", cluster, ".", process, ".csv", sep=""), sep=',', row.names=FALSE)


#LAGR:
write.log('summarize LAGR model.\n', 'result.txt')
write.log(paste('LAGR bandwidth: ', bw.lagr[['bw']], '.\n', sep=''), 'result.txt')
vars = c('(Intercept)', 'X1', 'X2', 'X3', 'X4', 'X5')

coefs = t(sapply(1:N**2, function(y) {as.vector(model.lagr[['model']][['models']][[y]][['coef']])}))
write.table(coefs, file=paste("CoefEstimates.", cluster, ".", process, ".lagr.csv", sep=""), col.names=vars, sep=',', row.names=FALSE)

params = c('bw', 'sigma2', 'fitted')
target = params[1]
output = sapply(1:N**2, function(y) {model.lagr[['model']][['models']][[y]][[target]]})

for (i in 2:length(params)) {
    target = params[i]
    output = cbind(output, sapply(1:N**2, function(y) {model.lagr[['model']][['models']][[y]][[target]]}))
}
write.table(output, file=paste("MiscParams.", cluster, ".", process, ".lagr.csv", sep=""), col.names=params, sep=',', row.names=FALSE)






#For oracle property:
#write.log('summarize oracle model.\n', 'result.txt')
#vars = c('(Intercept)', 'X1', 'X2', 'X3', 'X4', 'X5')

#coefs = t(sapply(1:N**2, function(y) {as.vector(model.oracular[['model']][['models']][[y]][['coef']])}))
write.table(coefs, file=paste("CoefEstimates.", cluster, ".", process, ".oracle.csv", sep=""), col.names=vars, sep=',', row.names=FALSE)

#params = c('bw', 'sigma2', 'loss.local', 'fitted')
#target = params[1]
#output = sapply(1:N**2, function(y) {model.oracular[['model']][['models']][[y]][[target]]})

#for (i in 2:length(params)) {
#    target = params[i]
#    output = cbind(output, sapply(1:N**2, function(y) {model.oracular[['model']][['models']][[y]][[target]]}))
#}
#write.table(output, file=paste("MiscParams.", cluster, ".", process, ".oracle.csv", sep=""), col.names=params, sep=',', row.names=FALSE)






#For all vars:
#write.log('summarize GWR-LLE model.\n', 'result.txt')
#vars = c('(Intercept)', 'X1', 'X2', 'X3', 'X4', 'X5')

#coefs = t(sapply(1:N**2, function(y) {as.vector(model.gwr[['model']][['models']][[y]][['coef']])}))
#write.table(coefs, file=paste("CoefEstimates.", cluster, ".", process, ".gwr.csv", sep=""), col.names=vars, sep=',', row.names=FALSE)

#params = c('bw', 'sigma2', 'loss.local', 'fitted')
#target = params[1]
#output = sapply(1:N**2, function(y) {model.gwr[['model']][['models']][[y]][[target]]})

#for (i in 2:length(params)) {
#    target = params[i]
#    output = cbind(output, sapply(1:N**2, function(y) {model.gwr[['model']][['models']][[y]][[target]]}))
#}
#write.table(output, file=paste("MiscParams.", cluster, ".", process, ".gwr.csv", sep=""), #col.names=params, sep=',', row.names=FALSE)

write.log('done.\n', 'result.txt')
